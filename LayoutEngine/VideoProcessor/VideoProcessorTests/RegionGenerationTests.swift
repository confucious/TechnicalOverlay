//
//  RegionGenerationTests.swift
//  VideoProcessorTests
//

import Testing
import CoreMedia
import CoreImage
@testable import VideoProcessor

@Suite struct RegionGenerationTests {

    private var slide: Slide {
        Slide(image: CIImage.clear, startTime: CMTime(seconds: 10, preferredTimescale: 1))
    }

    private var videoDuration: CMTime {
        CMTime(seconds: 120, preferredTimescale: 1)
    }

    private var transitionTime: CMTime {
        CMTime(seconds: 1, preferredTimescale: 1)
    }

    // MARK: - No slides

    @Test func noSlidesReturnsSingleNoOverlay() {
        let regions = generateRegions(
            slides: [],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        #expect(regions.count == 1)
        #expect(regions[0].type == .noOverlay)
        #expect(regions[0].timeRange.start == .zero)
        #expect(regions[0].timeRange.duration == videoDuration)
    }

    // MARK: - Single slide

    @Test func singleSlideAtTenReturnsNoOverlayTransitionConstant() {
        let regions = generateRegions(
            slides: [slide],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        #expect(regions.count == 3)
        #expect(regions[0].type == .noOverlay)
        #expect(regions[0].timeRange.start.seconds == 0)
        #expect(regions[0].timeRange.duration.seconds == 10)

        // Region 1: transition(nil -> slide)
        if case .transition = regions[1].type { } else {
            Issue.record("expected transition at index 1")
        }
        #expect(regions[1].timeRange.start.seconds == 10)
        #expect(regions[1].timeRange.duration.seconds == 1)

        // Region 2: constant(slide)
        if case .constant = regions[2].type { } else {
            Issue.record("expected constant at index 2")
        }
        #expect(regions[2].timeRange.start.seconds == 11)
        #expect(regions[2].timeRange.duration.seconds == 109) // 120 - 11
    }

    @Test func slideAtZeroStartsWithTransition() {
        let zeroSlide = Slide(
            image: CIImage.clear,
            startTime: CMTime.zero
        )
        let regions = generateRegions(
            slides: [zeroSlide],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        #expect(regions[0].type == .transition(from: nil, to: zeroSlide) ||
                regions[0].type != .noOverlay)
        #expect(regions[0].timeRange.start == .zero)
    }

    // MARK: - Multiple slides

    @Test func twoSlidesProducesExpectedRegions() {
        let slide1 = Slide(
            image: CIImage.clear,
            startTime: CMTime(seconds: 10, preferredTimescale: 1)
        )
        let slide2 = Slide(
            image: CIImage.clear,
            startTime: CMTime(seconds: 20, preferredTimescale: 1)
        )
        let regions = generateRegions(
            slides: [slide1, slide2],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        // Expected: noOverlay(0-10), transition(10-11), constant(11-20),
        //           transition(20-21), constant(21-120)
        #expect(regions.count == 5)

        #expect(regions[0].type == .noOverlay)
        #expect(regions[0].timeRange.start.seconds == 0)
        #expect(regions[0].timeRange.duration.seconds == 10)

        if case .transition = regions[1].type { } else {
            Issue.record("expected transition at index 1")
        }
        #expect(regions[1].timeRange.start.seconds == 10)
        #expect(regions[1].timeRange.duration.seconds == 1)

        if case .constant = regions[2].type { } else {
            Issue.record("expected constant at index 2")
        }
        #expect(regions[2].timeRange.start.seconds == 11)
        #expect(regions[2].timeRange.duration.seconds == 9)

        if case .transition = regions[3].type { } else {
            Issue.record("expected transition at index 3")
        }
        #expect(regions[3].timeRange.start.seconds == 20)
        #expect(regions[3].timeRange.duration.seconds == 1)

        if case .constant = regions[4].type { } else {
            Issue.record("expected constant at index 4")
        }
        #expect(regions[4].timeRange.start.seconds == 21)
    }

    // MARK: - Transition time

    @Test func transitionTimeControlsDuration() {
        let transTime = CMTime(seconds: 3, preferredTimescale: 1)
        let regions = generateRegions(
            slides: [slide],
            videoDuration: videoDuration,
            transitionTime: transTime
        )
        #expect(regions[1].timeRange.duration.seconds == 3)
        #expect(regions[2].timeRange.start.seconds == 13)
    }

    // MARK: - Last slide constant extends to video duration

    @Test func lastSlideConstantExtendsToVideoDuration() {
        let regions = generateRegions(
            slides: [slide],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        let lastConstant = regions[2]
        let end = lastConstant.timeRange.start + lastConstant.timeRange.duration
        #expect(end.seconds == videoDuration.seconds)
    }

    // MARK: - Content identity

    @Test func regionContentIdentitiesMatchTypes() {
        let regions = generateRegions(
            slides: [slide],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        #expect(regions[0].identity.kind == .noOverlay)
        #expect(regions[1].identity.kind == .transition)
        #expect(regions[2].identity.kind == .constant)
    }
}
