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
    let image: CIImage
    public let startTime: CMTime
    
    public init(image: CIImage, startTime: CMTime) {
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
                        request.finish(
                            with: slide.image.composited(over: request.sourceImage),
                            context: nil
                        )
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

    public static func constant(slide: Slide) -> ContentIdentity {
        ContentIdentity(kind: .constant, hash: slide.image.hashValue)
    }

    public static func transition(from: Slide?, to: Slide?) -> ContentIdentity {
        var hasher = Hasher()
        hasher.combine(from?.image.hashValue)
        hasher.combine(to?.image.hashValue)
        return ContentIdentity(kind: .transition, hash: hasher.finalize())
    }
}

// MARK: - Chunk Types

public enum ChunkType: Sendable, Equatable {
    case noOverlay
    case constant(Slide)
    case transition(from: Slide?, to: Slide?)

    public var contentIdentity: ContentIdentity {
        switch self {
        case .noOverlay:
            return .noOverlay()
        case .constant(let slide):
            return .constant(slide: slide)
        case .transition(let from, let to):
            return .transition(from: from, to: to)
        }
    }
}

public enum ChunkState: Sendable, Equatable {
    case pending
    case rendering
    case rendered(URL)
    case stale
}

// MARK: - Chunk

public struct Chunk: Sendable {
    public let id: UUID
    public var timeRange: CMTimeRange
    public let type: ChunkType
    public let contentIdentity: ContentIdentity
    public var state: ChunkState

    public init(
        id: UUID = UUID(),
        timeRange: CMTimeRange,
        type: ChunkType,
        state: ChunkState = .pending
    ) {
        self.id = id
        self.timeRange = timeRange
        self.type = type
        self.contentIdentity = type.contentIdentity
        self.state = state
    }

    public var isRendered: Bool {
        if case .rendered = state { return true }
        return false
    }

    public var isStale: Bool {
        if case .stale = state { return true }
        return false
    }

    public var outputURL: URL? {
        if case .rendered(let url) = state { return url }
        return nil
    }
}

// MARK: - Protocols

public protocol ChunkRendererProtocol: AsyncSequence {
    associatedtype Element = Chunk
    func render(_ chunk: Chunk) async -> URL?
}

public protocol StitcherProtocol: Sendable {
    func stitch(
        chunks: [Chunk],
        sourceAsset: AVAsset,
        videoDuration: CMTime,
        to outputURL: URL
    ) async -> URL?
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
        let transType: ChunkType = .transition(from: previousSlide, to: slide)
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
            let constType: ChunkType = .constant(slide)
            regions.append(ChunkRegion(
                identity: constType.contentIdentity,
                timeRange: constRange,
                type: constType
            ))
            cursor = nextSlideStart
        }

        // After last slide: transition out (fade to noOverlay)
        if index == sorted.count - 1 {
            if cursor < videoDuration {
                let transDuration = min(transitionTime, videoDuration - cursor)
                if transDuration.value > 0 {
                    let transRange = CMTimeRange(start: cursor, duration: transDuration)
                    // Transition out: from slide to noOverlay (fade out).
                    let transType: ChunkType = .transition(from: slide, to: nil)
                    regions.append(ChunkRegion(
                        identity: transType.contentIdentity,
                        timeRange: transRange,
                        type: transType
                    ))
                    cursor = cursor + transDuration
                }
            }

            // Final noOverlay if there's remaining time
            if cursor < videoDuration {
                let gapDuration = videoDuration - cursor
                let gapRange = CMTimeRange(start: cursor, duration: gapDuration)
                regions.append(ChunkRegion(identity: .noOverlay(), timeRange: gapRange, type: .noOverlay))
            }
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
            updated.state = .stale
            return updated
        }
    }

    var available = existingChunks.map { ($0, false) }
    var result: [Chunk] = []

    for region in newRegions {
        var bestIndex: Int?
        for (i, (chunk, reused)) in available.enumerated() {
            guard !reused else { continue }
            guard chunk.contentIdentity == region.identity else { continue }
            guard !chunk.isStale else { continue }
            let overlap = chunk.timeRange.intersection(region.timeRange)
            guard !overlap.isEmpty else { continue }
            bestIndex = i
            break
        }

        if let idx = bestIndex {
            let (chunk, _) = available[idx]
            var updated = chunk
            updated.timeRange = region.timeRange
            result.append(updated)
            available[idx] = (chunk, true)
        } else {
            let newChunk = Chunk(timeRange: region.timeRange, type: region.type, state: .pending)
            result.append(newChunk)
        }
    }

    for (chunk, reused) in available {
        if !reused {
            var updated = chunk
            updated.state = .stale
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
                chunks[i].state = .stale
            }
        }
    }

    public func startRendering() async {
        await drain()
    }

    public func waitForCompletion() async {
        while !Task.isCancelled {
            let hasPending = chunks.contains { chunk in
                chunk.state == .pending && chunk.type != .noOverlay
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
            markChunkState(next.id, state: .rendering)
            if let outputURL = await renderer.render(next) {
                markChunkRendered(next.id, outputURL: outputURL)
            } else {
                markChunkState(next.id, state: .stale)
            }
        }
    }

    private func dequeueNextRenderable() -> Chunk? {
        guard let index = chunks.firstIndex(where: { $0.state == .pending && $0.type != .noOverlay })
        else { return nil }
        return chunks[index]
    }

    private func markChunkState(_ id: UUID, state: ChunkState) {
        if let index = chunks.firstIndex(where: { $0.id == id }) {
            chunks[index].state = state
        }
    }

    private func markChunkRendered(_ id: UUID, outputURL: URL) {
        markChunkState(id, state: .rendered(outputURL))
    }
}
