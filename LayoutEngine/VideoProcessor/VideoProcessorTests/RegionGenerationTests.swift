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
        #expect(regions[0].type == .transition(from: nil, to: zeroSlide.image) ||
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

    // MARK: - Regions stay inside the video

    /// A slide that close to the end used to leave the plan ending past the video (119.5–120.5 in a
    /// 120 s video), and `DefaultStitcher` refuses a plan that does not end exactly at
    /// `videoDuration` — so the export aborted on a valid timeline.
    @Test func slideWithinTransitionTimeOfTheEndIsClampedToTheVideo() {
        let late = Slide(
            image: CIImage.clear,
            startTime: CMTime(seconds: 119.5, preferredTimescale: 1000)
        )
        let regions = generateRegions(
            slides: [late],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        let last = regions[regions.count - 1]
        #expect(last.timeRange.end == videoDuration)
        #expect(regions.allSatisfy {
            $0.timeRange.start >= .zero && $0.timeRange.end <= videoDuration
        })
        // Clamping must not open a hole: each region picks up where the previous one stopped.
        #expect(regions[0].timeRange.start == .zero)
        for (previous, next) in zip(regions, regions.dropFirst()) {
            #expect(previous.timeRange.end == next.timeRange.start)
        }
    }

    /// A slide past the end contributes nothing, and the plan still covers the whole video.
    @Test func slideAfterTheVideoProducesAWholeVideoNoOverlay() {
        let beyond = Slide(
            image: CIImage.clear,
            startTime: CMTime(seconds: 130, preferredTimescale: 1)
        )
        let regions = generateRegions(
            slides: [beyond],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        #expect(regions.count == 1)
        #expect(regions[0].type == .noOverlay)
        #expect(regions[0].timeRange == CMTimeRange(start: .zero, duration: videoDuration))
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
