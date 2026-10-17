//
//  VideoProcessor.swift
//  VideoProcessor
//
//  Created by Jerry Hsu on 10/12/25.
//

import AVFoundation
import CoreImage

public struct Slide: Sendable, Equatable {
    let image: CIImage?
    public let startTime: CMTime
    
    public init(image: CIImage?, startTime: CMTime) {
        self.image = image
        self.startTime = startTime
    }
}

public enum Metrics {
    public static let transitionTime = 0.75
}

// MARK: - Preview compositor

/// Everything the preview compositor needs to draw a frame.
///
/// AVFoundation instantiates a custom compositor itself (`init()`), so the recipe is published here
/// by `setupComposition()` rather than handed to the instance. The app keeps exactly one preview
/// composition — and therefore one live compositor — at a time.
nonisolated struct PreviewRecipe: Sendable {
    var slides: [Slide] = []
    var preferredTransform: CGAffineTransform = .identity
    /// Supplied by `setupComposition()`: `Metrics` is main-actor isolated, and the recipe is read
    /// from the compositor's own thread.
    var transitionTime: CMTime = CMTime(seconds: 0.75, preferredTimescale: 1000)
}

/// `PreviewRecipe` is written from the main actor and read from the compositor's own thread.
private nonisolated final class PreviewRecipeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var recipe = PreviewRecipe()

    var current: PreviewRecipe {
        get { lock.lock(); defer { lock.unlock() }; return recipe }
        set { lock.lock(); recipe = newValue; lock.unlock() }
    }
}

nonisolated private let previewRecipe = PreviewRecipeBox()

/// The **preview**'s frame applier — the compositor behind `setupComposition()`, which therefore
/// does not use `AVVideoComposition(applyingFiltersTo:applier:)`.
///
/// It owns the preview's compositing so that a cancelled frame request never blocks: frames are
/// composited synchronously in `startRequest`, and an interrupted request is dropped by never calling
/// `finish` on it. AVFoundation's own Core Image compositor waits for outstanding requests in its
/// cancel path, which stalls the main thread on a playhead drag — **do not** put the preview back on
/// the filter API (`docs/HISTORY.md` → *Playhead freeze*).
///
/// The recipe is the same Core Image program the chunk renderer runs, so the preview keeps matching
/// what the export writes out.
public final class PreviewVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])

    public nonisolated var sourcePixelBufferAttributes: [String: any Sendable]? {
        // Advertise what a 1080p source can arrive in; the render context then converts to the
        // format asked for below instead of failing the composition.
        [kCVPixelBufferPixelFormatTypeKey as String: [
            Int(kCVPixelFormatType_32BGRA),
            Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]]
    }

    public nonisolated var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    }

    public nonisolated func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    /// Returns immediately: a request that has been cancelled is simply never finished. Waiting here
    /// is what stalls the main thread on a playhead drag (`docs/HISTORY.md` → *Playhead freeze*).
    public nonisolated func cancelAllPendingVideoCompositionRequests() {}

    public nonisolated func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let trackID = request.sourceTrackIDs.first?.int32Value,
              let sourceFrame = request.sourceFrame(byTrackID: trackID),
              let destination = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: PreviewCompositorError.missingSourceFrame)
            return
        }

        let recipe = previewRecipe.current
        // A custom compositor is handed the raw source frame: the layer instruction's transform is
        // not applied for us, so the track's preferred orientation has to be baked in here.
        let oriented = CIImage(cvPixelBuffer: sourceFrame)
            .transformed(by: recipe.preferredTransform)
        let source = oriented.transformed(
            by: CGAffineTransform(
                translationX: -oriented.extent.origin.x,
                y: -oriented.extent.origin.y
            )
        )
        context.render(
            composited(source, at: request.compositionTime, recipe: recipe),
            to: destination
        )
        request.finish(withComposedVideoFrame: destination)
    }

    /// The slide that owns `time`, faded in from (or out to) the one before it while a transition
    /// is in progress — the same `OverlayComposite` program the chunk renderer runs.
    private nonisolated func composited(_ source: CIImage, at time: CMTime, recipe: PreviewRecipe) -> CIImage {
        let slides = recipe.slides
        let indexed = slides.enumerated().last { (_, slide) in time >= slide.startTime }
        guard let indexed else { return source }

        let index = indexed.offset
        let slide = indexed.element
        let elapsed = time - slide.startTime
        if elapsed <= recipe.transitionTime {
            return OverlayComposite.dissolve(
                from: index > 0 ? slides[index - 1].image : nil,
                to: slide.image,
                progress: elapsed.seconds / recipe.transitionTime.seconds,
                over: source
            )
        }
        return OverlayComposite.hold(slide.image, over: source)
    }
}

enum PreviewCompositorError: Error {
    case missingSourceFrame
}
public class VideoComposer {
    
    var asset: AVAsset
    var slides: [Slide]
    
    public init(asset: AVAsset, slides: [Slide]) {
        self.asset = asset
        self.slides = slides.sorted(by: { a, b in
            a.startTime < b.startTime
        })
    }
    
    /// Builds the **preview** composition — the one attached to the `AVPlayerItem`.
    ///
    /// Unlike the chunk-renderer builders below, this does **not** go through
    /// `AVVideoComposition(applyingFiltersTo:applier:)`: frames are composited by
    /// `PreviewVideoCompositor`, driven by the recipe published here. Do not put it back on the filter
    /// API (`docs/HISTORY.md` → *Playhead freeze*).
    public func setupComposition() async throws -> AVVideoComposition? {
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            print("No video track to compose for")
            return nil
        }
        let duration = try await asset.load(.duration)
        previewRecipe.current = PreviewRecipe(
            slides: slides,
            preferredTransform: (try? await videoTrack.load(.preferredTransform)) ?? .identity,
            transitionTime: CMTime(seconds: Metrics.transitionTime, preferredTimescale: 1000)
        )

        var configuration = try await AVVideoComposition.Configuration(for: asset)
        configuration.customVideoCompositorClass = PreviewVideoCompositor.self

        var instruction = AVVideoCompositionInstruction.Configuration()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.enablePostProcessing = false
        // `requiredSourceTrackIDs` is computed from the layer instructions, so the compositor is
        // only handed frames for this track if the track is declared here.
        instruction.layerInstructions = [
            AVVideoCompositionLayerInstruction(configuration: .init(assetTrack: videoTrack))
        ]
        configuration.instructions = [AVVideoCompositionInstruction(configuration: instruction)]
        return AVVideoComposition(configuration: configuration)
    }
    
    public func setupExport(
        withPreset preset: String = AVAssetExportPresetHighestQuality,
        toFileType outputFileType: AVFileType = .mov,
        atURL outputURL: URL
    ) async -> ExportSession? {
            
        // Check the compatibility of the preset to export the video to the output file type.
        guard await AVAssetExportSession.compatibility(ofExportPreset: preset,
                                                       with: asset,
                                                       outputFileType: outputFileType) else {
            print("The preset can't export the video to the output file type.")
            return nil
        }
        
        // Create and configure the export session.
        guard let exportSession = AVAssetExportSession(asset: asset,
                                                       presetName: preset) else {
            print("Failed to create export session.")
            return nil
        }
        
        // Convert the video to the output file type and export it to the output URL.
        do {
            exportSession.videoComposition = try await setupComposition()
            return ExportSession(
                exportSession: exportSession,
                outputUrl: outputURL,
                outputFileType: outputFileType
            )
        } catch {
            print("export failed \(error)")
            return nil
        }
    }
    public struct ExportSession {
        let exportSession: AVAssetExportSession
        let outputUrl: URL
        let outputFileType: AVFileType
        public let exportState: any AsyncSequence<AVAssetExportSession.State, Never>
        
        init(
            exportSession: AVAssetExportSession,
            outputUrl: URL,
            outputFileType: AVFileType,
        ) {
            self.exportSession = exportSession
            self.outputUrl = outputUrl
            self.outputFileType = outputFileType
            self.exportState = exportSession.states(updateInterval: 0.1)
        }
        
        /// Writes the composition to `outputUrl`, throwing on failure so the caller can surface it.
        public func performExport() async throws {
            try await exportSession.export(to: outputUrl, as: outputFileType)
        }
    }
}

// MARK: - Content Identity

/// Stable identifier for chunk content independent of time range.
public struct ContentIdentity: Hashable, Sendable {
    public let kind: Kind
    public let hash: Int

    public enum Kind: Sendable {
        case noOverlay
        case constant
        case transition
    }

    public static func noOverlay() -> ContentIdentity {
        ContentIdentity(kind: .noOverlay, hash: 0)
    }

    public static func constant(image: CIImage) -> ContentIdentity {
        ContentIdentity(kind: .constant, hash: image.hashValue)
    }

    public static func transition(from: CIImage?, to: CIImage?) -> ContentIdentity {
        var hasher = Hasher()
        hasher.combine(from?.hashValue)
        hasher.combine(to?.hashValue)
        return ContentIdentity(kind: .transition, hash: hasher.finalize())
    }
}

// MARK: - Chunk Types

public enum ChunkType: Sendable, Equatable {
    case noOverlay
    case constant(CIImage)
    case transition(from: CIImage?, to: CIImage?)

    public var contentIdentity: ContentIdentity {
        switch self {
        case .noOverlay:
            return .noOverlay()
        case .constant(let image):
            return .constant(image: image)
        case .transition(let from, let to):
            return .transition(from: from, to: to)
        }
    }
}

public enum ChunkState: Sendable, Equatable {
    case pending
    case rendering
    case rendered(URL)
}

// MARK: - Chunk

public struct Chunk: Sendable {
    public let id: UUID
    public let timeRange: CMTimeRange
    public let type: ChunkType
    public let contentIdentity: ContentIdentity
    public var renderState: ChunkState
    public var stitchingTimeRange: CMTimeRange?

    public init(
        id: UUID = UUID(),
        timeRange: CMTimeRange,
        type: ChunkType,
        renderState: ChunkState = .pending
    ) {
        self.id = id
        self.timeRange = timeRange
        self.type = type
        self.contentIdentity = type.contentIdentity
        self.renderState = renderState
        self.stitchingTimeRange = timeRange
    }

    /// `true` for the chunks that carry an overlay — the only ones the queue renders and the
    /// stitcher copies from a rendered file.
    public var hasOverlay: Bool {
        type != .noOverlay
    }

    /// Whether the chunk is part of the current plan. `stitchingTimeRange` is the plan's own record
    /// of the range this chunk contributes: `diffRegionsIntoChunks` clears it to drop a chunk the
    /// new plan no longer covers (`markStale(where:)` does the same for a failed render).
    public var isInPlan: Bool {
        stitchingTimeRange != nil
    }

    /// Work the queue still owes this chunk: an overlay chunk with no render yet.
    public var needsRender: Bool {
        hasOverlay && renderState == .pending
    }

    /// Whether the chunk can be stitched: in the plan, and either rendered or an overlay-free range
    /// of the source. `ChunkQueue.validChunks()` and `DefaultStitcher.stitch` both filter on this.
    public var isValid: Bool {
        hasOverlay ? isRendered && isInPlan : isInPlan
    }

    public var isRendered: Bool {
        if !hasOverlay {
            // noOverlay chunks have no work to render, so they count as rendered.
            return true
        }
        if case .rendered = renderState {
            return true
        }
        return false
    }

    public var outputURL: URL? {
        if case .rendered(let url) = renderState { return url }
        return nil
    }
}

// MARK: - Protocols

public protocol ChunkRendererProtocol {
    func render(_ chunk: Chunk) async -> URL?
}

public protocol StitcherProtocol: Sendable {
    func stitch(
        chunks: [Chunk],
        sourceAsset: AVAsset,
        videoDuration: CMTime,
        to outputURL: URL
    ) async throws -> VideoComposer.ExportSession?
}

// MARK: - Region

public struct ChunkRegion: Sendable {
    public let identity: ContentIdentity
    public let timeRange: CMTimeRange
    public let type: ChunkType

    public init(identity: ContentIdentity, timeRange: CMTimeRange, type: ChunkType) {
        self.identity = identity
        self.timeRange = timeRange
        self.type = type
    }
}

// MARK: - generateRegions

public func generateRegions(
    slides: [Slide],
    videoDuration: CMTime,
    transitionTime: CMTime
) -> [ChunkRegion] {
    let wholeVideo = CMTimeRange(start: .zero, duration: videoDuration)
    guard !slides.isEmpty else {
        return [ChunkRegion(identity: .noOverlay(), timeRange: wholeVideo, type: .noOverlay)]
    }

    let sorted = slides.sorted { $0.startTime < $1.startTime }
    var regions: [ChunkRegion] = []

    /// Appends the region covering `start..<end`, clipped to the video. A transition that begins
    /// within `transitionTime` of the end would otherwise run past `videoDuration`, and the plan is
    /// what the stitcher checks against the video's exact length (`DefaultStitcher.stitch`), so an
    /// overrun aborts the export. An entirely empty region adds nothing.
    func append(_ type: ChunkType, from start: CMTime, to end: CMTime) {
        let clippedStart = max(start, .zero)
        let clippedEnd = min(end, videoDuration)
        guard clippedEnd > clippedStart else { return }
        regions.append(ChunkRegion(
            identity: type.contentIdentity,
            timeRange: CMTimeRange(start: clippedStart, end: clippedEnd),
            type: type
        ))
    }

    var cursor = CMTime.zero

    for (index, slide) in sorted.enumerated() {
        let slideStart = slide.startTime

        // Gap before this slide's transition starts → noOverlay
        if cursor < slideStart {
            append(.noOverlay, from: cursor, to: slideStart)
        }

        // Transition region, starting at the slide — or where the previous transition left off,
        // when the slides are closer together than `transitionTime`.
        let transitionStart = max(cursor, slideStart)
        let transitionEnd = transitionStart + transitionTime
        append(
            .transition(from: index > 0 ? sorted[index - 1].image : nil, to: slide.image),
            from: transitionStart,
            to: transitionEnd
        )
        cursor = transitionEnd

        // Constant region: from end of transition to next slide start (or video end)
        let nextSlideStart = (index + 1 < sorted.count) ? sorted[index + 1].startTime : videoDuration
        if cursor < nextSlideStart {
            append(slide.image.map { .constant($0) } ?? .noOverlay, from: cursor, to: nextSlideStart)
            cursor = nextSlideStart
        }
    }

    if regions.isEmpty {
        return [ChunkRegion(identity: .noOverlay(), timeRange: wholeVideo, type: .noOverlay)]
    }

    return regions
}

// MARK: - diffRegionsIntoChunks

public func diffRegionsIntoChunks(
    newRegions: [ChunkRegion],
    existingChunks: [Chunk]
) -> [Chunk] {
    guard !newRegions.isEmpty else {
        return existingChunks.map { chunk in
            var updated = chunk
            updated.stitchingTimeRange = nil
            return updated
        }
    }

    var reusedIDs: Set<UUID> = []
    var result: [Chunk] = []

    for region in newRegions {
        switch region.type {
        case .noOverlay:
            // noOverlay chunks are never reused — always create new
            let newChunk = Chunk(timeRange: region.timeRange, type: region.type, renderState: .pending)
            result.append(newChunk)

        case .transition:
            // Transition chunks require exact timeRange match
            var matchIndex: Int?
            for (i, chunk) in existingChunks.enumerated() {
                guard !reusedIDs.contains(chunk.id) else { continue }
                guard chunk.contentIdentity == region.identity else { continue }
                guard chunk.timeRange.start == region.timeRange.start &&
                      chunk.timeRange.duration == region.timeRange.duration else { continue }
                matchIndex = i
                break
            }

            if let idx = matchIndex {
                let chunk = existingChunks[idx]
                var updated = chunk
                updated.stitchingTimeRange = region.timeRange
                result.append(updated)
                reusedIDs.insert(chunk.id)
            } else {
                let newChunk = Chunk(timeRange: region.timeRange, type: region.type, renderState: .pending)
                result.append(newChunk)
            }

        case .constant:
            // Constant chunks can be reused for overlapping portions
            var matchIndex: Int?
            for (i, chunk) in existingChunks.enumerated() {
                guard !reusedIDs.contains(chunk.id) else { continue }
                guard chunk.contentIdentity == region.identity else { continue }
                let overlap = chunk.timeRange.intersection(region.timeRange)
                guard !overlap.isEmpty else { continue }
                matchIndex = i
                break
            }

            if let idx = matchIndex {
                let chunk = existingChunks[idx]
                let overlap = chunk.timeRange.intersection(region.timeRange)

                // If region extends before the overlap, create a new pending chunk
                if region.timeRange.start < overlap.start {
                    let gapDuration = overlap.start - region.timeRange.start
                    let gapRange = CMTimeRange(start: region.timeRange.start, duration: gapDuration)
                    let gapChunk = Chunk(timeRange: gapRange, type: region.type, renderState: .pending)
                    result.append(gapChunk)
                }

                // Reuse the existing chunk trimmed to the overlap. The chunk's own timeRange does not
                // change; only the region used for stitching does.
                var updated = chunk
                updated.stitchingTimeRange = overlap
                result.append(updated)
                reusedIDs.insert(chunk.id)

                // If region extends after the overlap, create a new pending chunk
                if overlap.end < region.timeRange.end {
                    let gapDuration = region.timeRange.end - overlap.end
                    let gapRange = CMTimeRange(start: overlap.end, duration: gapDuration)
                    let gapChunk = Chunk(timeRange: gapRange, type: region.type, renderState: .pending)
                    result.append(gapChunk)
                }
            } else {
                let newChunk = Chunk(timeRange: region.timeRange, type: region.type, renderState: .pending)
                result.append(newChunk)
            }
        }
    }

    // Mark unreused existing chunks as stale (stitchingTimeRange = nil)
    for chunk in existingChunks {
        if !reusedIDs.contains(chunk.id) && chunk.hasOverlay {
            var updated = chunk
            updated.stitchingTimeRange = nil
            result.append(updated)
        }
    }

    return result
}

// MARK: - ChunkQueue

/// Progress reported during chunk rendering.
public struct ChunkQueueProgress: Sendable {
    public let completed: Int
    public let total: Int

    /// True while any chunk is queued or being rendered — i.e. the background pipeline still has
    /// work to do. Drives a status indicator in the app (green when false, yellow when true).
    public let isRendering: Bool
}

public actor ChunkQueue {
    public var chunks: [Chunk] = []
    private let renderer: any ChunkRendererProtocol
    private let transitionTime: CMTime
    private var drainTask: Task<Void, Never>?
    private var progressCallback: (@Sendable (ChunkQueueProgress) -> Void)?

    public init(renderer: any ChunkRendererProtocol, transitionTime: CMTime) {
        self.renderer = renderer
        self.transitionTime = transitionTime
    }

    public func setProgressCallback(_ callback: @escaping @Sendable (ChunkQueueProgress) -> Void) {
        progressCallback = callback
    }

    public func enqueue(slides: [Slide], videoDuration: CMTime) {
        let newRegions = generateRegions(
            slides: slides,
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        Trace.log(.queue, "enqueue: \(slides.count) slides, video \(videoDuration.traceDescription) → \(newRegions.count) regions (\(newRegions.traceBreakdown))")

        let previousCount = chunks.count
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        let toRender = chunks.count(where: { $0.needsRender })
        let reused = chunks.count(where: { $0.hasOverlay && $0.isInPlan && !$0.needsRender })
        let stale = chunks.count(where: { $0.hasOverlay && !$0.isInPlan })
        Trace.log(.queue, "enqueue: \(chunks.count) chunks (was \(previousCount)) → \(toRender) to render, \(reused) reused, \(stale) stale")

        for chunk in chunks where chunk.hasOverlay {
            let disposition: String
            if !chunk.isInPlan {
                disposition = "stale (not reused)"
            } else if chunk.needsRender {
                disposition = "new → pending"
            } else {
                disposition = "reused → \(chunk.renderState.traceName)"
            }
            Trace.log(.queue, "  \(chunk.traceLabel) stitch=\(chunk.stitchingTimeRange?.traceDescription ?? "none") \(disposition)")
        }

        // Tell observers immediately: the queue now has work, even before the first render starts.
        reportProgress()

        if drainTask == nil {
            Trace.log(.queue, "enqueue: queue idle, starting drain")
            drainTask = Task { [weak self] in
                await self?.drain()
                await self?.finishDrain()
            }
        } else {
            Trace.log(.queue, "enqueue: drain already running, it will pick these up")
        }
    }

    private func finishDrain() {
        drainTask = nil
    }

    public func markStale(where predicate: (Chunk) -> Bool) {
        var newlyStale = 0
        for i in chunks.indices {
            if predicate(chunks[i]) {
                if chunks[i].isInPlan { newlyStale += 1 }
                chunks[i].stitchingTimeRange = nil
            }
        }
        Trace.log(.queue, "markStale: \(newlyStale) newly stale of \(chunks.count) chunks (\(chunks.count(where: { !$0.isInPlan })) stale total)")
        reportProgress()
    }

    public func startRendering() async {
        await drain()
    }

    public func waitForCompletion() async {
        let pendingAtStart = chunks.count(where: { $0.needsRender })
        let timer = TraceTimer()
        if pendingAtStart > 0 {
            Trace.log(.queue, "waitForCompletion: waiting on \(pendingAtStart) pending chunks")
        }

        while !Task.isCancelled {
            // A drain started by enqueue() may still be rendering a chunk it has already dequeued, so
            // wait for it: the caller stitches as soon as we return.
            if let drainTask {
                Trace.log(.queue, "waitForCompletion: awaiting the in-flight drain")
                await drainTask.value
                continue
            }
            guard dequeueNextRenderable() != nil else { break }
            await drain()
        }

        if pendingAtStart > 0 {
            let renderable = chunks.count(where: { $0.hasOverlay && $0.isRendered && $0.isInPlan })
            Trace.log(.queue, "waitForCompletion: done in \(timer.elapsedDescription), \(renderable) rendered and in plan")
        }
    }

    public func validChunks() -> [Chunk] {
        let valid = chunks.filter(\.isValid)
        Trace.log(.queue, "validChunks: \(valid.count) of \(chunks.count) chunks valid — dropping \(chunks.count(where: { $0.hasOverlay && !$0.isInPlan })) stale, \(chunks.count(where: { $0.needsRender })) pending")
        return valid
    }

    // MARK: - Internal

    private func reportProgress() {
        let total = chunks.count(where: { $0.hasOverlay })
        let completed = chunks.count(where: {
            $0.hasOverlay && $0.isRendered
        })
        // Stale chunks are excluded: they have no stitching range, so the queue will never touch them
        // again.
        let isRendering = chunks.contains { chunk in
            chunk.hasOverlay && chunk.isInPlan
                && (chunk.renderState == .pending || chunk.renderState == .rendering)
        }
        progressCallback?(ChunkQueueProgress(
            completed: completed,
            total: total,
            isRendering: isRendering
        ))
    }

    private func drain() async {
        let pendingAtStart = chunks.count(where: { $0.needsRender })
        let drainTimer = TraceTimer()
        var rendered = 0
        var failed = 0
        if pendingAtStart > 0 {
            Trace.log(.queue, "drain: start, \(pendingAtStart) pending")
            reportProgress()
        }

        while !Task.isCancelled {
            guard let next = dequeueNextRenderable() else {
                break
            }
            Trace.log(.queue, "drain: dequeue \(next.traceLabel) stitch=\(next.stitchingTimeRange?.traceDescription ?? "none")")
            markChunkRenderState(next.id, state: .rendering)

            let chunkTimer = TraceTimer()
            if let outputURL = await renderer.render(next) {
                markChunkRendered(next.id, outputURL: outputURL)
                rendered += 1
                Trace.log(.queue, "drain: rendered \(next.traceID) in \(chunkTimer.elapsedDescription) → \(outputURL.lastPathComponent)")
            } else {
                markChunkStale(next.id)
                failed += 1
                Trace.log(.queue, "drain: render failed for \(next.traceID) after \(chunkTimer.elapsedDescription), marked stale")
            }
            reportProgress()
        }

        if pendingAtStart > 0 || rendered > 0 || failed > 0 {
            let stillPending = chunks.count(where: { $0.needsRender })
            Trace.log(.queue, "drain: done, \(rendered) rendered, \(failed) failed, \(stillPending) still pending in \(drainTimer.elapsedDescription)")
            reportProgress()
        }
    }

    private func dequeueNextRenderable() -> Chunk? {
        guard let index = chunks.firstIndex(where: { $0.needsRender })
        else { return nil }
        return chunks[index]
    }

    private func markChunkRenderState(_ id: UUID, state: ChunkState) {
        if let index = chunks.firstIndex(where: { $0.id == id }) {
            chunks[index].renderState = state
        }
    }

    private func markChunkStale(_ id: UUID) {
        if let index = chunks.firstIndex(where: { $0.id == id }) {
            chunks[index].stitchingTimeRange = nil
        }
    }

    private func markChunkRendered(_ id: UUID, outputURL: URL) {
        markChunkRenderState(id, state: .rendered(outputURL))
    }
}
