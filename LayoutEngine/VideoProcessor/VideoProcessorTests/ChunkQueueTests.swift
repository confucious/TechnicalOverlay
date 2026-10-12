//
//  ChunkQueueTests.swift
//  VideoProcessorTests
//

import Testing
import CoreMedia
import CoreImage
@testable import VideoProcessor

// MARK: - Fake Renderer

final class FakeRenderer: ChunkRendererProtocol, @unchecked Sendable {

    var rendered: [Chunk] = []
    var shouldFail = false

    init() {}

    func render(_ chunk: Chunk) async -> URL? {
        if shouldFail { return nil }
        let url = URL(fileURLWithPath: "/fake/output/\(chunk.id.uuidString).mov")
        rendered.append(chunk)
        return url
    }
}

// MARK: - Slow Renderer

/// Renderer that takes real time, so a chunk can still be in flight while another caller waits.
/// The first render is deliberately much slower than the rest: with a prompt renderer the race
/// this guards against is invisible (every chunk finishes before anyone looks).
final class SlowRenderer: ChunkRendererProtocol, @unchecked Sendable {

    private(set) var rendered: [Chunk] = []
    private var isFirstRender = true

    func render(_ chunk: Chunk) async -> URL? {
        let delay: Duration = isFirstRender ? .milliseconds(300) : .milliseconds(10)
        isFirstRender = false
        try? await Task.sleep(for: delay)
        rendered.append(chunk)
        return URL(fileURLWithPath: "/fake/output/\(chunk.id.uuidString).mov")
    }
}

// MARK: - Tests

@Suite struct ChunkQueueTests {

    var queue: ChunkQueue!
    var renderer: FakeRenderer!
    private let transitionTime: CMTime = CMTime(seconds: 1, preferredTimescale: 1)
    private let videoDuration: CMTime = CMTime(seconds: 120, preferredTimescale: 1)

    private var slide: Slide {
        Slide(image: CIImage.clear, startTime: CMTime(seconds: 10, preferredTimescale: 1))
    }

    init() {
        renderer = FakeRenderer()
        queue = ChunkQueue(renderer: renderer, transitionTime: transitionTime)
    }

    // MARK: - Basic enqueue + drain

    @Test func enqueueAndDrainRendersAllChunks() async {
        await queue.enqueue(slides: [slide], videoDuration: videoDuration)
        await queue.waitForCompletion()

        let renderable = await queue.chunks.filter { $0.type != .noOverlay }
        #expect(renderable.allSatisfy { $0.isRendered })
        #expect(renderer.rendered.count == renderable.count)
    }

    /// Regression: enqueue() starts its own drain, so a chunk can be in flight when
    /// waitForCompletion() is called. It used to return as soon as nothing was *pending*,
    /// leaving that chunk unrendered — the caller then stitched a plan with a hole in it and
    /// the stitcher refused it (the app's "Save Video" produced nothing at all).
    @Test func waitForCompletionWaitsForAnInFlightRender() async {
        let slowRenderer = SlowRenderer()
        let slowQueue = ChunkQueue(renderer: slowRenderer, transitionTime: transitionTime)

        await slowQueue.enqueue(slides: [slide], videoDuration: videoDuration)
        // Let the enqueue drain pick up the first chunk and start its slow render.
        try? await Task.sleep(for: .milliseconds(20))

        await slowQueue.waitForCompletion()

        let renderable = await slowQueue.chunks.filter { $0.type != .noOverlay }
        #expect(renderable.allSatisfy { $0.isRendered })
        #expect(renderable.count == slowRenderer.rendered.count)
    }

    @Test func emptyEnqueueDoesNothing() async {
        await queue.enqueue(slides: [], videoDuration: videoDuration)
        // Should have single noOverlay
        let chunks = await queue.chunks
        #expect(chunks.count == 1)
        #expect(chunks[0].type == .noOverlay)
    }

    // MARK: - Chunk type generation

    @Test func singleSlideProducesTransitionAndConstant() async {
        await queue.enqueue(slides: [slide], videoDuration: videoDuration)
        let chunks = await queue.chunks

        let types = chunks.map { $0.type }
        #expect(types.contains { if case .noOverlay = $0 { return true }; return false })
        #expect(types.contains { if case .transition = $0 { return true }; return false })
        #expect(types.contains { if case .constant = $0 { return true }; return false })
    }

    @Test func noSlidesProducesNoRenderableChunks() async {
        await queue.enqueue(slides: [], videoDuration: videoDuration)
        let chunks = await queue.chunks
        #expect(chunks.count == 1)
        #expect(chunks[0].type == .noOverlay)
    }

    // MARK: - Staleness

    @Test func enqueueWithNewSlidesMarksOldChunksStale() async {
        await queue.enqueue(slides: [slide], videoDuration: videoDuration)
        await queue.waitForCompletion()

        // Enqueue different slide at different time
        let newSlide = Slide(
            image: CIImage.clear,
            startTime: CMTime(seconds: 50, preferredTimescale: 1)
        )
        await queue.enqueue(slides: [newSlide], videoDuration: videoDuration)

        let chunks = await queue.chunks
        let staleCount = chunks.filter { $0.isStale }.count
        // Old chunks should be stale since no new region matched their time ranges
        #expect(staleCount > 0)
    }

    @Test func markStaleByPredicate() async {
        await queue.enqueue(slides: [slide], videoDuration: videoDuration)

        await queue.markStale { $0.type == .noOverlay }

        let chunks = await queue.chunks
        for chunk in chunks where chunk.type == .noOverlay {
            #expect(chunk.isStale)
        }
    }

    // MARK: - NoOverlay never enters render queue

    @Test func drainSkipsNoOverlayChunks() async {
        await queue.enqueue(slides: [], videoDuration: videoDuration)
        await queue.waitForCompletion()

        // NoOverlay should not be rendered
        #expect(renderer.rendered.isEmpty)
    }

    // MARK: - Ordering

    @Test func chunksRenderInTimeOrder() async {
        let slide1 = Slide(image: CIImage.clear, startTime: CMTime(seconds: 10, preferredTimescale: 1))
        let slide2 = Slide(image: CIImage.clear, startTime: CMTime(seconds: 20, preferredTimescale: 1))
        let slide3 = Slide(image: CIImage.clear, startTime: CMTime(seconds: 30, preferredTimescale: 1))

        await queue.enqueue(slides: [slide1, slide2, slide3], videoDuration: videoDuration)
        await queue.waitForCompletion()

        var prevTime = CMTime.zero
        for chunk in renderer.rendered {
            #expect(chunk.timeRange.start >= prevTime)
            prevTime = chunk.timeRange.start
        }
    }

    // MARK: - Valid chunks

    @Test func validChunksReturnsOnlyRenderedNonStale() async {
        await queue.enqueue(slides: [slide], videoDuration: videoDuration)
        await queue.waitForCompletion()

        let valid = await queue.validChunks()
        for chunk in valid {
            switch chunk.type {
            case .noOverlay:
                #expect(!chunk.isStale)
            case .constant, .transition:
                #expect(chunk.isRendered)
                #expect(!chunk.isStale)
            }
        }
    }

    @Test func validChunksIncludesNoOverlayAlways() async {
        await queue.enqueue(slides: [], videoDuration: videoDuration)
        // noOverlay doesn't need rendering
        let valid = await queue.validChunks()
        #expect(valid.contains { $0.type == .noOverlay })
    }

    @Test func validChunksSortedByTime() async {
        let slide1 = Slide(image: CIImage.clear, startTime: CMTime(seconds: 10, preferredTimescale: 1))
        let slide2 = Slide(image: CIImage.clear, startTime: CMTime(seconds: 20, preferredTimescale: 1))

        await queue.enqueue(slides: [slide1, slide2], videoDuration: videoDuration)
        await queue.waitForCompletion()

        let valid = await queue.validChunks()
        var prevEnd = CMTime.zero
        for chunk in valid {
            #expect(chunk.timeRange.start >= prevEnd)
            prevEnd = chunk.timeRange.start + chunk.timeRange.duration
        }
    }

    // MARK: - Render failure

    @Test func renderFailureMarksChunkStale() async {
        renderer.shouldFail = true
        await queue.enqueue(slides: [slide], videoDuration: videoDuration)
        await queue.waitForCompletion()

        let renderable = await queue.chunks.filter { $0.type != .noOverlay }
        // All renderable chunks should be stale (render failed)
        #expect(renderable.allSatisfy { $0.isStale })
    }

    // MARK: - Re-enqueue after invalidation

    @Test func reEnqueueAfterInvalidation() async {
        await queue.enqueue(slides: [slide], videoDuration: videoDuration)
        await queue.waitForCompletion()

        let firstRenderCount = renderer.rendered.count

        // Re-enqueue same slides — should reuse rendered chunks
        await queue.enqueue(slides: [slide], videoDuration: videoDuration)
        await queue.waitForCompletion()

        // No additional renders since chunks were reused
        #expect(renderer.rendered.count == firstRenderCount)
    }
}
