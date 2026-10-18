//
//  OverlaySpanTests.swift
//  VideoProcessorTests
//
//  The plan the preview and the export share: one walk over the slides, a transition that always runs
//  its full length, and the per-frame answer both paths consult.
//

import AVFoundation
import CoreImage
import Foundation
import Testing
@testable import VideoProcessor

@Suite struct OverlaySpanTests {

    private let videoDuration = CMTime(seconds: 10, preferredTimescale: 1000)
    private let transitionTime = CMTime(seconds: 0.75, preferredTimescale: 1000)

    private func image(_ gray: CGFloat) -> CIImage {
        CIImage(color: CIColor(red: gray, green: gray, blue: gray))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    // MARK: - The walk

    @Test func previewAndExportComeFromTheSameWalk() {
        let slides = [
            Slide(image: image(0.2), startTime: CMTime(seconds: 2, preferredTimescale: 1000)),
            Slide(image: image(0.4), startTime: CMTime(seconds: 2.4, preferredTimescale: 1000)),
            Slide(image: nil, startTime: CMTime(seconds: 6, preferredTimescale: 1000))
        ]
        let spans = overlaySpans(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
        let regions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)

        #expect(spans.map(\.timeRange) == regions.map(\.timeRange))
        #expect(spans.map(\.type.contentIdentity) == regions.map(\.identity))
    }

    /// Two slides 0.4 s apart with 0.75 s transitions: the first dissolve finishes before the second
    /// begins, so neither is cut short.
    @Test func crowdedSlidesStillGetFullTransitions() {
        let first = image(0.2)
        let second = image(0.4)
        let slides = [
            Slide(image: first, startTime: CMTime(seconds: 2, preferredTimescale: 1000)),
            Slide(image: second, startTime: CMTime(seconds: 2.4, preferredTimescale: 1000))
        ]
        let spans = overlaySpans(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)

        // noOverlay 0–2, transition 2–2.75, transition 2.75–3.5, constant 3.5–10
        #expect(spans.count == 4)
        #expect(spans[0].timeRange == CMTimeRange(start: .zero, end: CMTime(seconds: 2, preferredTimescale: 1000)))

        for span in spans[1...2] {
            #expect(span.timeRange.duration == transitionTime)
        }
        if case .transition(let from, let to) = spans[1].type {
            #expect(from == nil)
            #expect(to === first)
        } else {
            Issue.record("expected a transition into the first slide")
        }
        if case .transition(let from, let to) = spans[2].type {
            #expect(from === first)
            #expect(to === second)
        } else {
            Issue.record("expected a transition into the second slide")
        }
        // Coverage stays exact: no gap opened where a transition was pushed later.
        for (previous, next) in zip(spans, spans.dropFirst()) {
            #expect(previous.timeRange.end == next.timeRange.start)
        }
    }

    // MARK: - The per-frame answer

    /// The regression this change is about: mid-way through the *first* dissolve, the preview used to
    /// show the second slide fading in (its start time had already passed) while the export was still
    /// dissolving the first one in.
    @Test func midFirstDissolveIsTheFirstSlideNotTheSecond() {
        let first = image(0.2)
        let second = image(0.4)
        let slides = [
            Slide(image: first, startTime: CMTime(seconds: 2, preferredTimescale: 1000)),
            Slide(image: second, startTime: CMTime(seconds: 2.4, preferredTimescale: 1000))
        ]
        let spans = overlaySpans(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)

        let content = spans.content(
            at: CMTime(seconds: 2.6, preferredTimescale: 1000),
            transitionTime: transitionTime
        )
        guard case .dissolve(let from, let to, let progress) = content else {
            Issue.record("expected a dissolve at 2.6 s")
            return
        }
        #expect(from == nil)
        #expect(to === first)
        #expect(abs(progress - 0.8) < 0.001)
    }

    @Test func midSecondDissolveIsBetweenTheTwoSlides() {
        let first = image(0.2)
        let second = image(0.4)
        let slides = [
            Slide(image: first, startTime: CMTime(seconds: 2, preferredTimescale: 1000)),
            Slide(image: second, startTime: CMTime(seconds: 2.4, preferredTimescale: 1000))
        ]
        let spans = overlaySpans(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)

        let content = spans.content(
            at: CMTime(seconds: 3, preferredTimescale: 1000),
            transitionTime: transitionTime
        )
        guard case .dissolve(let from, let to, let progress) = content else {
            Issue.record("expected a dissolve at 3 s")
            return
        }
        #expect(from === first)
        #expect(to === second)
        #expect(abs(progress - 0.25 / 0.75) < 0.001)
    }

    @Test func heldAndUncoveredTimesResolveToHoldAndNone() {
        let only = image(0.2)
        let slides = [Slide(image: only, startTime: CMTime(seconds: 2, preferredTimescale: 1000))]
        let spans = overlaySpans(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)

        if case .none = spans.content(at: CMTime(seconds: 1, preferredTimescale: 1000), transitionTime: transitionTime) {
        } else {
            Issue.record("expected no overlay before the slide")
        }
        if case .hold(let image) = spans.content(at: CMTime(seconds: 5, preferredTimescale: 1000), transitionTime: transitionTime) {
            #expect(image === only)
        } else {
            Issue.record("expected the slide to be held at 5 s")
        }
        // A fade-out slide (no image) resolves to no overlay rather than an empty hold.
        let fadeOut = overlaySpans(
            slides: [Slide(image: nil, startTime: CMTime(seconds: 2, preferredTimescale: 1000))],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        if case .none = fadeOut.content(at: CMTime(seconds: 5, preferredTimescale: 1000), transitionTime: transitionTime) {
        } else {
            Issue.record("expected a fade-out slide to resolve to no overlay")
        }
    }
}
