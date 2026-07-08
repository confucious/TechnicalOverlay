//
//  VideoProcessor.swift
//  VideoProcessor
//
//  Created by Jerry Hsu on 10/12/25.
//

import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

public struct Slide: Sendable, Equatable {
    let image: CIImage?
    public let startTime: CMTime
    
    public init(image: CIImage?, startTime: CMTime) {
        self.image = image
        self.startTime = startTime
    }
}

enum Metrics {
    static let transitionTime = 0.75
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
    
    public func setupComposition() async throws -> AVVideoComposition? {
        return try await AVVideoComposition.videoComposition(
            with: asset) { [slides] request in
                // find slide appropriate for the compositionTime
                let indexedSlide = slides.enumerated().last { (_, slide) in
                    return request.compositionTime >= slide.startTime
                }
                if let indexedSlide {
                    let index = indexedSlide.offset
                    let previousImage = index > 0 ? slides[index - 1].image : CIImage.clear
                    let slide = indexedSlide.element
//                    print("Found slide \(slide.startTime)")
                    let diff = request.compositionTime - slide.startTime
                    if diff <= CMTime(
                        seconds: Metrics.transitionTime,
                        preferredTimescale: 1000
                    ) {
                        let dissolve = CIFilter.dissolveTransition()
                        dissolve.inputImage = previousImage
                        dissolve.targetImage = slide.image
                        dissolve.time = Float(
                            diff.seconds / Metrics.transitionTime
                        )
                        request.finish(
                            with: dissolve.outputImage!
                                .composited(over: request.sourceImage),
                            context: nil
                        )
                    } else {
                        if let slideImage = slide.image {
                            request.finish(
                                with: slideImage.composited(over: request.sourceImage),
                                context: nil
                            )
                        } else {
                            request.finish(
                                with: request.sourceImage,
                                context: nil
                            )
                        }
                    }
                } else {
                    request.finish(with: request.sourceImage, context: nil)
                }
            }
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
        
        public func performExport() async {
            do {
                try await exportSession.export(to: outputUrl, as: outputFileType)
            } catch {
                print("export failed \(error)")
            }
        }
    }

    // MARK: - CIImage-based Composition (for chunk rendering)

    /// Creates an `AVVideoComposition` that composites a single overlay image
    /// over the source video for every frame. Mirrors the constant-overlay
    /// path of `setupComposition()` but operates directly on `CIImage`.
    public func setupComposition(overlay image: CIImage?) async throws -> AVVideoComposition {
        return try await AVVideoComposition.videoComposition(with: asset) { request in
            guard let image else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }
            request.finish(
                with: image.composited(over: request.sourceImage),
                context: nil
            )
        }
    }

    /// Creates an `AVVideoComposition` that applies a cross-dissolve transition
    /// between `from` and `to` images, composited over the source video.
    /// The transition begins at `transitionStart` and lasts `Metrics.transitionTime`.
    /// After the transition, the `to` image is held for remaining frames.
    public func setupComposition(
        from: CIImage?,
        to: CIImage?,
        transitionStart: CMTime
    ) async throws -> AVVideoComposition {
        let transitionTime = CMTime(seconds: Metrics.transitionTime, preferredTimescale: 1000)
        return try await AVVideoComposition.videoComposition(with: asset) { request in
            guard let fromImage = from, let toImage = to else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }

            let diff = request.compositionTime - transitionStart
            if diff <= transitionTime {
                let dissolve = CIFilter.dissolveTransition()
                dissolve.inputImage = fromImage
                dissolve.targetImage = toImage
                let progress = max(0.0, min(diff.seconds, transitionTime.seconds)) / transitionTime.seconds
                dissolve.time = Float(progress)
                request.finish(
                    with: dissolve.outputImage!.composited(over: request.sourceImage),
                    context: nil
                )
            } else {
                request.finish(
                    with: toImage.composited(over: request.sourceImage),
                    context: nil
                )
            }
        }
    }

    // MARK: - CIImage-based Export

    /// Creates an `ExportSession` for exporting the asset with a constant overlay.
    /// Mirrors `setupExport()` but uses `setupComposition(overlay:)`.
    public func setupExport(
        overlay image: CIImage?,
        withPreset preset: String = AVAssetExportPresetHighestQuality,
        toFileType outputFileType: AVFileType = .mov,
        atURL outputURL: URL
    ) async -> ExportSession? {
        guard await AVAssetExportSession.compatibility(
            ofExportPreset: preset,
            with: asset,
            outputFileType: outputFileType
        ) else {
            print("The preset can't export the video to the output file type.")
            return nil
        }

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: preset
        ) else {
            print("Failed to create export session.")
            return nil
        }

        do {
            exportSession.videoComposition = try await setupComposition(overlay: image)
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

    /// Creates an `ExportSession` for exporting the asset with a transition overlay.
    /// Mirrors `setupExport()` but uses `setupComposition(from:to:transitionStart:)`.
    public func setupExport(
        from: CIImage?,
        to: CIImage?,
        transitionStart: CMTime,
        withPreset preset: String = AVAssetExportPresetHighestQuality,
        toFileType outputFileType: AVFileType = .mov,
        atURL outputURL: URL
    ) async -> ExportSession? {
        guard await AVAssetExportSession.compatibility(
            ofExportPreset: preset,
            with: asset,
            outputFileType: outputFileType
        ) else {
            print("The preset can't export the video to the output file type.")
            return nil
        }

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: preset
        ) else {
            print("Failed to create export session.")
            return nil
        }

        do {
            exportSession.videoComposition = try await setupComposition(
                from: from,
                to: to,
                transitionStart: transitionStart
            )
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

    public var isRendered: Bool {
        if type == .noOverlay {
            // noOverlay chunks are always considered rendered regardless
            // of renderState because there is no work to do for them.
            return true
        }
        if case .rendered = renderState {
            return true
        }
        return false
    }

    public var isStale: Bool {
        stitchingTimeRange == nil
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
    guard !slides.isEmpty else {
        let range = CMTimeRange(start: .zero, duration: videoDuration)
        return [ChunkRegion(identity: .noOverlay(), timeRange: range, type: .noOverlay)]
    }

    let sorted = slides.sorted { $0.startTime < $1.startTime }
    var regions: [ChunkRegion] = []
    var cursor = CMTime.zero

    for (index, slide) in sorted.enumerated() {
        let slideStart = slide.startTime
        let transEnd = slideStart + transitionTime

        // Gap before this slide's transition starts → noOverlay
        if cursor < slideStart {
            let gapDuration = slideStart - cursor
            let gapRange = CMTimeRange(start: cursor, duration: gapDuration)
            regions.append(ChunkRegion(identity: .noOverlay(), timeRange: gapRange, type: .noOverlay))
        }

        if slideStart > cursor {
            cursor = slideStart
        }

        // Transition region
        let transDuration = transitionTime
        let transRange = CMTimeRange(start: cursor, duration: transDuration)
        let previousSlide = index > 0 ? sorted[index - 1] : nil
        let effectivePreviousSlide = previousSlide?.image == nil ? nil : previousSlide
        let effectiveSlide = slide.image == nil ? nil : slide // nil if the current slide has no image.
        let transType: ChunkType = .transition(from: effectivePreviousSlide?.image, to: effectiveSlide?.image)
        regions.append(ChunkRegion(
            identity: transType.contentIdentity,
            timeRange: transRange,
            type: transType
        ))
        cursor = transEnd

        // Constant region: from end of transition to next slide start (or video end)
        let nextSlideStart = (index + 1 < sorted.count) ? sorted[index + 1].startTime : videoDuration
        if cursor < nextSlideStart {
            let constDuration = nextSlideStart - cursor
            let constRange = CMTimeRange(start: cursor, duration: constDuration)
            let constType: ChunkType = slide.image == nil ?
                .noOverlay :
                .constant(slide.image!)
            regions.append(ChunkRegion(
                identity: constType.contentIdentity,
                timeRange: constRange,
                type: constType
            ))
            cursor = nextSlideStart
        }
    }

    if regions.isEmpty {
        let range = CMTimeRange(start: .zero, duration: videoDuration)
        return [ChunkRegion(identity: .noOverlay(), timeRange: range, type: .noOverlay)]
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

                // Reuse the existing chunk trimmed to the overlap
                // Existing chunk's timeRange should not change. just the region used for stitching.
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
        if !reusedIDs.contains(chunk.id) && chunk.type != .noOverlay {
            var updated = chunk
            updated.stitchingTimeRange = nil
            result.append(updated)
        }
    }

    return result
}

// MARK: - ChunkQueue

public actor ChunkQueue {
    public var chunks: [Chunk] = []
    private let renderer: any ChunkRendererProtocol
    private let transitionTime: CMTime
    private var isDraining = false

    public init(renderer: any ChunkRendererProtocol, transitionTime: CMTime) {
        self.renderer = renderer
        self.transitionTime = transitionTime
    }

    public func enqueue(slides: [Slide], videoDuration: CMTime) {
        let newRegions = generateRegions(
            slides: slides,
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)
        if !isDraining {
            Task { await self.startRendering() }
        }
    }

    public func markStale(where predicate: (Chunk) -> Bool) {
        for i in chunks.indices {
            if predicate(chunks[i]) {
                chunks[i].stitchingTimeRange = nil
            }
        }
    }

    public func startRendering() async {
        await drain()
    }

    public func waitForCompletion() async {
        while !Task.isCancelled {
            let hasPending = chunks.contains { chunk in
                chunk.renderState == .pending && chunk.type != .noOverlay
            }
            guard hasPending else { break }
            await drain()
        }
    }

    public func validChunks() -> [Chunk] {
        chunks.filter { chunk in
            switch chunk.type {
            case .noOverlay:
                return !chunk.isStale
            case .constant, .transition:
                return chunk.isRendered && !chunk.isStale
            }
        }
    }

    // MARK: - Internal

    private func drain() async {
        isDraining = true
        while !Task.isCancelled {
            guard let next = dequeueNextRenderable() else {
                isDraining = false
                break
            }
            markChunkRenderState(next.id, state: .rendering)
            if let outputURL = await renderer.render(next) {
                markChunkRendered(next.id, outputURL: outputURL)
            } else {
                markChunkStale(next.id)
            }
        }
    }

    private func dequeueNextRenderable() -> Chunk? {
        guard let index = chunks.firstIndex(where: { $0.renderState == .pending && $0.type != .noOverlay })
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
