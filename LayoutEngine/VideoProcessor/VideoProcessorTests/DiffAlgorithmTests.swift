//
//  DiffAlgorithmTests.swift
//  VideoProcessorTests
//

import Testing
import CoreMedia
import CoreImage
@testable import VideoProcessor

@Suite struct DiffAlgorithmTests {

    private var slide: Slide {
        Slide(image: CIImage.clear, startTime: CMTime(seconds: 10, preferredTimescale: 1))
    }

    private var videoDuration: CMTime {
        CMTime(seconds: 120, preferredTimescale: 1)
    }

    private var transitionTime: CMTime {
        CMTime(seconds: 1, preferredTimescale: 1)
    }

    private func makeRenderedChunk(
        timeRange: CMTimeRange,
        type: ChunkType
    ) -> Chunk {
        var chunk = Chunk(timeRange: timeRange, type: type, renderState: .pending)
        chunk.renderState = .rendered(URL(fileURLWithPath: "/tmp/fake.mov"))
        return chunk
    }

    // MARK: - Empty regions

    @Test func emptyRegionsMarksAllStale() {
        let existing = [
            makeRenderedChunk(
                timeRange: CMTimeRange(start: .zero, duration: videoDuration),
                type: .noOverlay
            ),
            makeRenderedChunk(
                timeRange: .init(
                    start: .init(seconds: 10, preferredTimescale: 1),
                    duration: .init(seconds: 1, preferredTimescale: 1)
                ),
                type: .transition(from: nil, to: slide.image)
            ),
        ]
        let result = diffRegionsIntoChunks(newRegions: [], existingChunks: existing)
        #expect(result.count == existing.count)
        for chunk in result {
            #expect(chunk.isStale)
        }
    }

    // MARK: - Identical regions

    @Test func identicalRegionsReusesAllChunks() {
        let regions = generateRegions(
            slides: [slide],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        let existing = regions.map { region in
            var chunk = Chunk(timeRange: region.timeRange, type: region.type)
            chunk.renderState = .rendered(URL(fileURLWithPath: "/tmp/fake.mov"))
            return chunk
        }

        let result = diffRegionsIntoChunks(newRegions: regions, existingChunks: existing)

        #expect(result.count == existing.count)
        for chunk in result {
            #expect(chunk.isRendered)
            #expect(!chunk.isStale)
        }
    }

    // MARK: - Slide move trims and extends chunks

    @Test func slideMoveCreatesNewNoOverlayChunks() {
        // Old: slide at 10→100, transitionTime=1
        let oldSlide = Slide(image: CIImage.clear, startTime: CMTime(seconds: 10, preferredTimescale: 1))
        let oldRegions = generateRegions(
            slides: [oldSlide],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        let existing = oldRegions.map { region in
            var chunk = Chunk(timeRange: region.timeRange, type: region.type)
            chunk.renderState = .rendered(URL(fileURLWithPath: "/tmp/fake.mov"))
            return chunk
        }

        // New: slide at 12→102
        let newSlide = Slide(image: CIImage.clear, startTime: CMTime(seconds: 12, preferredTimescale: 1))
        let newRegions = generateRegions(
            slides: [newSlide],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )

        let result = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: existing)

        // The new noOverlay at [0-12] is a fresh chunk (noOverlay never reused)
        let firstChunk = result[0]
        #expect(firstChunk.type == .noOverlay)
        #expect(firstChunk.renderState == .pending) // new, not reused
        #expect(firstChunk.timeRange.start.seconds == 0)
        #expect(firstChunk.timeRange.duration.seconds == 12)
    }

    @Test func slideMoveCreatesNewChunksForGaps() {
        let oldSlide = Slide(image: CIImage.clear, startTime: CMTime(seconds: 10, preferredTimescale: 1))
        let oldRegions = generateRegions(
            slides: [oldSlide],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        let existing = oldRegions.map { region in
            var chunk = Chunk(timeRange: region.timeRange, type: region.type)
            chunk.renderState = .rendered(URL(fileURLWithPath: "/tmp/fake.mov"))
            return chunk
        }

        let newSlide = Slide(image: CIImage.clear, startTime: CMTime(seconds: 12, preferredTimescale: 1))
        let newRegions = generateRegions(
            slides: [newSlide],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )

        let result = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: existing)

        // New transition at [12-13] has no matching existing chunk (old was at [10-11]).
        // Transitions require exact timeRange match, so it creates new pending.
        let transitionChunk = result.first { chunk in
            if case .transition = chunk.type {
                return chunk.timeRange.start.seconds == 12
            }
            return false
        }
        #expect(transitionChunk != nil)
        #expect(transitionChunk?.renderState == .pending)
    }

    @Test func removedRegionMarksChunkStale() {
        let regions = generateRegions(
            slides: [slide],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        let existing = regions.map { region in
            var chunk = Chunk(timeRange: region.timeRange, type: region.type)
            chunk.renderState = .rendered(URL(fileURLWithPath: "/tmp/fake.mov"))
            return chunk
        }

        // New: no slides → single noOverlay
        let newRegions = generateRegions(
            slides: [],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )

        let result = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: existing)

        // All non-noOverlay chunks should be stale.
        for chunk in result where chunk.type != .noOverlay {
            #expect(chunk.isStale)
        }
    }

    // MARK: - NoOverlay never reused

    @Test func noOverlayChunksNeverReused() {
        let oldRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 1))
        let existing = [makeRenderedChunk(timeRange: oldRange, type: .noOverlay)]

        let newRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 15, preferredTimescale: 1))
        let newRegion = ChunkRegion(
            identity: .noOverlay(),
            timeRange: newRange,
            type: .noOverlay
        )

        let result = diffRegionsIntoChunks(newRegions: [newRegion], existingChunks: existing)

        #expect(result.count == 1) // just the new 15 second noOverlay chunk. Old one is dropped entirely.
        let newChunk = result.first { !$0.isStale }
        let oldChunk = result.first { $0.isStale }
        #expect(newChunk != nil)
        #expect(newChunk?.renderState == .pending)
        #expect(newChunk?.timeRange == newRange)
        #expect(oldChunk == nil)
    }

    // MARK: - Pending constant chunks can be reused

    @Test func pendingConstantChunksCanBeReused() {
        let image = CIImage.clear
        let region = ChunkRegion(
            identity: .constant(image: image),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 1)),
            type: .constant(image)
        )
        let pendingChunk = Chunk(timeRange: region.timeRange, type: .constant(image), renderState: .pending)

        let result = diffRegionsIntoChunks(newRegions: [region], existingChunks: [pendingChunk])

        #expect(result.count == 1)
        #expect(result[0].renderState == .pending) // reused, stays pending
        #expect(!result[0].isStale)
    }

    // Stale chunks should be eligible to be reused if time stamps change to enter their range again.
    @Test func staleChunksCanBeReused() {
        let image = CIImage.clear
        let region = ChunkRegion(
            identity: .constant(image: image),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 1)),
            type: .constant(image)
        )
        var staleChunk = Chunk(timeRange: region.timeRange, type: .constant(image), renderState: .pending)
        staleChunk.stitchingTimeRange = nil

        let result = diffRegionsIntoChunks(newRegions: [region], existingChunks: [staleChunk])

        #expect(result.count == 1)
        let newChunk = result.first { $0.renderState == .pending && !$0.isStale }
        let oldChunk = result.first { $0.isStale }
        #expect(newChunk != nil)
        #expect(oldChunk == nil)
    }

    // A chunk with the same time stamp but different image should not match.
    @Test func chunkWithSameTimestampButDifferentImageShouldNotMatch() {
        let image1 = CIImage.clear
        let image2 = CIImage.red
        let region = ChunkRegion(
            identity: .constant(image: image1),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 1)),
            type: .constant(image1)
        )
        var staleChunk = Chunk(timeRange: region.timeRange, type: .constant(image2), renderState: .pending)
        staleChunk.stitchingTimeRange = region.timeRange

        let result = diffRegionsIntoChunks(newRegions: [region], existingChunks: [staleChunk])

        #expect(result.count == 2)
        let newChunk = result.first { $0.renderState == .pending && !$0.isStale }
        let oldChunk = result.first { $0.isStale }
        #expect(newChunk != nil)
        #expect(oldChunk != nil)
    }

    // MARK: - New region with no match

    @Test func newRegionWithNoMatchCreatesNewChunk() {
        let region = ChunkRegion(
            identity: .constant(image: slide.image!),
            timeRange: CMTimeRange(start: CMTime(seconds: 50, preferredTimescale: 1), duration: CMTime(seconds: 10, preferredTimescale: 1)),
            type: .constant(slide.image!)
        )

        let result = diffRegionsIntoChunks(newRegions: [region], existingChunks: [])

        #expect(result.count == 1)
        #expect(result[0].renderState == .pending)
        #expect(result[0].timeRange == region.timeRange)
    }

    // MARK: - Constant chunk split on overlap

    @Test func constantChunkSplitOnOverlap() {
        let image = CIImage.clear

        // Existing constant chunk [10,20] rendered
        let existingRange = CMTimeRange(start: CMTime(seconds: 10, preferredTimescale: 1), duration: CMTime(seconds: 10, preferredTimescale: 1))
        let existing = [makeRenderedChunk(timeRange: existingRange, type: .constant(image))]

        // New region wants [5,15]
        let newRange = CMTimeRange(start: CMTime(seconds: 5, preferredTimescale: 1), duration: CMTime(seconds: 10, preferredTimescale: 1))
        let newRegion = ChunkRegion(
            identity: .constant(image: image),
            timeRange: newRange,
            type: .constant(image)
        )

        let result = diffRegionsIntoChunks(newRegions: [newRegion], existingChunks: existing)
        let valid = result.filter { !$0.isStale }

        // Expected: new pending [5,10], reused [10,15], stale [15,20]
        #expect(valid.count == 2)

        // First: new pending chunk [5,10]
        #expect(valid[0].timeRange.start.seconds == 5)
        #expect(valid[0].timeRange.duration.seconds == 5)
        #expect(valid[0].renderState == .pending)

        // Second: reused chunk trimmed to [10,15]
        #expect(valid[1].timeRange.start.seconds == 10)
        // timeRange of chunk (representing the video that was rendered) shoudl not change.
        #expect(valid[1].timeRange.duration.seconds == 10)
        #expect(valid[1].stitchingTimeRange?.start.seconds == 10)
        #expect(valid[1].stitchingTimeRange?.duration.seconds == 5)
        #expect(valid[1].isRendered) // was rendered, stays rendered

        // Old [15,20] portion is stale, but the chunk overall is not stale.
        let staleChunks = result.filter { $0.isStale }
        #expect(staleChunks.count == 0)
    }

    // MARK: - Transition requires exact timeRange match

    @Test func transitionReuseRequiresExactMatch() {
        let imageA = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        let imageB = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 0.5))

        // Existing transition chunk at [10,11]
        let existingRange = CMTimeRange(start: CMTime(seconds: 10, preferredTimescale: 1), duration: CMTime(seconds: 1, preferredTimescale: 1))
        let existing = [makeRenderedChunk(
            timeRange: existingRange,
            type: .transition(from: imageA, to: imageB)
        )]

        // New region at [12,13] — same images, different time → no reuse
        let newRange = CMTimeRange(start: CMTime(seconds: 12, preferredTimescale: 1), duration: CMTime(seconds: 1, preferredTimescale: 1))
        let newRegion = ChunkRegion(
            identity: .transition(from: imageA, to: imageB),
            timeRange: newRange,
            type: .transition(from: imageA, to: imageB)
        )

        let result = diffRegionsIntoChunks(newRegions: [newRegion], existingChunks: existing)
        let valid = result.filter { !$0.isStale }

        #expect(valid.count == 1)
        #expect(valid[0].renderState == .pending) // new chunk
        #expect(valid[0].timeRange == newRange)
    }

    @Test func transitionReuseWithExactMatch() {
        let imageA = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        let imageB = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 0.5))

        let existingRange = CMTimeRange(start: CMTime(seconds: 10, preferredTimescale: 1), duration: CMTime(seconds: 1, preferredTimescale: 1))
        let existing = [makeRenderedChunk(
            timeRange: existingRange,
            type: .transition(from: imageA, to: imageB)
        )]

        // Same timeRange, same images → reuse
        let newRegion = ChunkRegion(
            identity: .transition(from: imageA, to: imageB),
            timeRange: existingRange,
            type: .transition(from: imageA, to: imageB)
        )

        let result = diffRegionsIntoChunks(newRegions: [newRegion], existingChunks: existing)

        #expect(result.count == 1)
        #expect(result[0].isRendered)
        #expect(!result[0].isStale)
    }
}
