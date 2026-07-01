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
        var chunk = Chunk(timeRange: timeRange, type: type, state: .pending)
        chunk.state = .rendered(URL(fileURLWithPath: "/tmp/fake.mov"))
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
                timeRange: CMTimeRange(
                    start: .init(seconds: 10, preferredTimescale: 1),
                    duration: .init(seconds: 1, preferredTimescale: 1)
                ),
                type: .transition(from: nil, to: slide)
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
            chunk.state = .rendered(URL(fileURLWithPath: "/tmp/fake.mov"))
            return chunk
        }

        let result = diffRegionsIntoChunks(newRegions: regions, existingChunks: existing)

        #expect(result.count == existing.count)
        for chunk in result {
            #expect(chunk.isRendered)
            #expect(!chunk.isStale)
        }
    }

    // MARK: - Slide move trims and extends chunks (user's example)

    @Test func slideMoveTrimsConstantChunk() {
        // Old: slide at 10→100, transitionTime=1
        // Regions: noOverlay(0-10), transition(10-11), constant(11-100), transition(100-101), noOverlay(101-120)
        let oldSlide = Slide(image: CIImage.clear, startTime: CMTime(seconds: 10, preferredTimescale: 1))
        let oldRegions = generateRegions(
            slides: [oldSlide],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        let existing = oldRegions.map { region in
            var chunk = Chunk(timeRange: region.timeRange, type: region.type)
            chunk.state = .rendered(URL(fileURLWithPath: "/tmp/fake.mov"))
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

        // The noOverlay at [0-10] should NOT match noOverlay at [0-12] (different time range but same identity).
        // Wait — noOverlay identity is always the same (hash: 0, kind: .noOverlay).
        // So the first noOverlay region [0-12] should match the first existing noOverlay chunk [0-10].
        // It will be trimmed/extended to [0-12].
        let firstChunk = result[0]
        #expect(firstChunk.type == .noOverlay)
        #expect(firstChunk.isRendered) // reused
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
            chunk.state = .rendered(URL(fileURLWithPath: "/tmp/fake.mov"))
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
        // It should be pending.
        let transitionChunk = result.first { chunk in
            if case .transition = chunk.type {
                return chunk.timeRange.start.seconds == 12
            }
            return false
        }
        #expect(transitionChunk != nil)
        #expect(transitionChunk?.state == .pending)
    }

    @Test func removedRegionMarksChunkStale() {
        let regions = generateRegions(
            slides: [slide],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        let existing = regions.map { region in
            var chunk = Chunk(timeRange: region.timeRange, type: region.type)
            chunk.state = .rendered(URL(fileURLWithPath: "/tmp/fake.mov"))
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

    // MARK: - NoOverlay reuse

    @Test func noOverlayChunksReusedByIdentity() {
        let oldRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 1))
        let existing = [makeRenderedChunk(timeRange: oldRange, type: .noOverlay)]

        let newRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 15, preferredTimescale: 1))
        let newRegion = ChunkRegion(
            identity: .noOverlay(),
            timeRange: newRange,
            type: .noOverlay
        )

        let result = diffRegionsIntoChunks(newRegions: [newRegion], existingChunks: existing)

        #expect(result.count == 1)
        #expect(result[0].isRendered) // reused
        #expect(result[0].timeRange.duration == newRange.duration) // extended
    }

    // MARK: - Pending chunks

    @Test func pendingChunksCanBeReused() {
        let region = ChunkRegion(
            identity: .noOverlay(),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 1)),
            type: .noOverlay
        )
        let pendingChunk = Chunk(timeRange: region.timeRange, type: .noOverlay, state: .pending)

        let result = diffRegionsIntoChunks(newRegions: [region], existingChunks: [pendingChunk])

        #expect(result.count == 1)
        #expect(result[0].state == .pending) // reused, stays pending
        #expect(!result[0].isStale)
    }

    @Test func staleChunksNotReused() {
        let region = ChunkRegion(
            identity: .noOverlay(),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 1)),
            type: .noOverlay
        )
        var staleChunk = Chunk(timeRange: region.timeRange, type: .noOverlay, state: .pending)
        staleChunk.state = .stale

        let result = diffRegionsIntoChunks(newRegions: [region], existingChunks: [staleChunk])

        #expect(result.count == 2)
        let newChunk = result.first { $0.state == .pending && !$0.isStale }
        let oldChunk = result.first { $0.isStale }
        #expect(newChunk != nil)
        #expect(oldChunk != nil)
    }

    // MARK: - New region with no match

    @Test func newRegionWithNoMatchCreatesNewChunk() {
        let region = ChunkRegion(
            identity: .constant(slide: slide),
            timeRange: CMTimeRange(start: CMTime(seconds: 50, preferredTimescale: 1), duration: CMTime(seconds: 10, preferredTimescale: 1)),
            type: .constant(slide)
        )

        let result = diffRegionsIntoChunks(newRegions: [region], existingChunks: [])

        #expect(result.count == 1)
        #expect(result[0].state == .pending)
        #expect(result[0].timeRange == region.timeRange)
    }
}
