//
//  OverlayDataChangeTests.swift
//  VideoProcessorTests
//
//  Simulates incremental OverlayData changes and verifies that chunks
//  always span the entire video with no gaps or overlaps.
//
//  Each test mirrors what OverlayData.makeSlides() produces:
//    - Intro slides with displayTime create Slide objects
//    - A fadeout (mode .none) slide is added 5s after the last intro
//    - Element slides with displayTime create Slide objects
//    - A fadeout slide is added 5s after the last element (replacing the intro fadeout)

import Testing
import CoreMedia
import CoreImage
@testable import VideoProcessor

// MARK: - Distinct test images

/// Each slide type gets a unique CIImage so content identity distinguishes them.
private let imgIntro1  = CIImage(color: CIColor(red: 0, green: 0, blue: 1, alpha: 0.5))
private let imgIntro2  = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 0.5))
private let imgElem1   = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
private let imgElem2   = CIImage(color: CIColor(red: 1, green: 1, blue: 0, alpha: 0.5))
private let imgElem3   = CIImage(color: CIColor(red: 1, green: 0, blue: 1, alpha: 0.5))
private let imgFadeout = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0))

private func slide(_ image: CIImage?, _ seconds: Double) -> Slide {
    Slide(image: image, startTime: CMTime(seconds: seconds, preferredTimescale: 1))
}

// MARK: - Suite

@Suite struct OverlayDataChangeTests {

    private let transitionTime: CMTime = CMTime(seconds: 1, preferredTimescale: 1)
    private let videoDuration: CMTime = CMTime(seconds: 120, preferredTimescale: 1)

    // -----------------------------------------------------------------------
    // Coverage invariant helper
    // -----------------------------------------------------------------------

    /// Asserts that non-stale chunks form a contiguous timeline from 0 to videoDuration.
    private func assertCoverage(_ chunks: [Chunk], videoDuration: CMTime) {
        let valid = chunks.filter { !$0.isStale }

        guard !valid.isEmpty else {
            Issue.record("no valid chunks")
            return
        }

        #expect(valid.first?.timeRange.start == .zero, "first chunk starts at 0")
        #expect(valid.last?.timeRange.end == videoDuration, "last chunk ends at videoDuration")

        for i in 1..<valid.count {
            #expect(
                valid[i - 1].timeRange.end == valid[i].timeRange.start,
                "gap or overlap between chunk \(i - 1) and \(i)"
            )
        }

        let total = valid.reduce(CMTime.zero) { $0 + $1.timeRange.duration }
        #expect(total == videoDuration, "total duration mismatch")
    }

    // -----------------------------------------------------------------------
    // Step 0: Empty OverlayData
    // -----------------------------------------------------------------------

    @Test func step0_emptyOverlayDataProducesSingleNoOverlay() {
        let regions = generateRegions(slides: [], videoDuration: videoDuration, transitionTime: transitionTime)
        let chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: [])

        #expect(chunks.count == 1)
        #expect(chunks[0].type == .noOverlay)
        #expect(chunks[0].timeRange.start == .zero)
        #expect(chunks[0].timeRange.duration == videoDuration)
        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 1: Introduction slides WITHOUT timestamps
    // makeSlides filters by displayTime → no slides → no change
    // -----------------------------------------------------------------------

    @Test func step1_introductionSlidesWithoutTimestampsDoNotChangeChunks() {
        let slides: [Slide] = []

        let regions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
        let chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: [])

        #expect(chunks.count == 1)
        #expect(chunks[0].type == .noOverlay)
        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 2: Element scores WITHOUT timestamps
    // Still no slides → no change
    // -----------------------------------------------------------------------

    @Test func step2_elementScoresWithoutTimestampsDoNotChangeChunks() {
        let slides: [Slide] = []

        let regions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
        let chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: [])

        #expect(chunks.count == 1)
        #expect(chunks[0].type == .noOverlay)
        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 3: Set timestamp for first introduction slide
    // makeSlides: [intro1@10, fadeout@15]
    // Regions: [0-10] noOverlay, [10-11] trans(nil→intro1),
    //          [11-15] const(intro1), [15-16] trans(intro1→fadeout),
    //          [16-120] const(fadeout)
    // -----------------------------------------------------------------------

    @Test func step3_settingFirstIntroductionTimestampSplitsChunks() {
        // Previous state: single noOverlay
        let initialRegions = generateRegions(slides: [], videoDuration: videoDuration, transitionTime: transitionTime)
        var chunks = diffRegionsIntoChunks(newRegions: initialRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        // Simulate: setIntroTime(index: 0, time: 10)
        // makeSlides produces: [intro1@10, fadeout@15]
        let slides = [
            slide(imgIntro1, 10),
            slide(nil, 15),
        ]
        let newRegions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        let valid = chunks.filter { !$0.isStale }
        #expect(valid.count == 5)

        // [0-10] noOverlay
        #expect(valid[0].type == .noOverlay)
        #expect(valid[0].timeRange.start.seconds == 0)
        #expect(valid[0].timeRange.duration.seconds == 10)

        // [10-11] transition(nil→intro1)
        #expect(valid[1].type == .transition(from: nil, to: slides[0]))
        #expect(valid[1].timeRange.start.seconds == 10)
        #expect(valid[1].timeRange.duration.seconds == 1)

        // [11-15] constant(intro1)
        #expect(valid[2].type == .constant(slides[0]))
        #expect(valid[2].timeRange.start.seconds == 11)
        #expect(valid[2].timeRange.duration.seconds == 4)

        // [15-16] transition(intro1→fadeout)
        #expect(valid[3].type == .transition(from: slides[0], to: nil))
        #expect(valid[3].timeRange.start.seconds == 15)
        #expect(valid[3].timeRange.duration.seconds == 1)

        // [16-120] constant(fadeout)
        #expect(valid[4].type == .noOverlay)
        #expect(valid[4].timeRange.start.seconds == 16)
        #expect(valid[4].timeRange.end.seconds == 120)

        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 4: Set timestamp for second introduction slide
    // makeSlides: [intro1@10, intro2@20, fadeout@25]
    // Reuse: [0-10] noOverlay, [10-11] transition, [11-15] constant(intro1) reused
    // -----------------------------------------------------------------------

    @Test func step4_settingSecondIntroductionTimestampSplitsChunks() {
        // Previous: intro1@10, fadeout@15
        let prevSlides = [
            slide(imgIntro1, 10),
            slide(imgFadeout, 15),
        ]
        let prevRegions = generateRegions(slides: prevSlides, videoDuration: videoDuration, transitionTime: transitionTime)
        var chunks = diffRegionsIntoChunks(newRegions: prevRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        // Simulate: setIntroTime(index: 1, time: 20)
        // makeSlides produces: [intro1@10, intro2@20, fadeout@25]
        let slides = [
            slide(imgIntro1, 10),
            slide(imgIntro2, 20),
            slide(imgFadeout, 25),
        ]
        let newRegions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        let valid = chunks.filter { !$0.isStale }
        #expect(valid.count == 7)

        // [0-10] noOverlay
        #expect(valid[0].timeRange.start.seconds == 0)
        #expect(valid[0].timeRange.duration.seconds == 10)

        // [10-11] transition(nil→intro1)
        #expect(valid[1].timeRange.start.seconds == 10)
        #expect(valid[1].timeRange.duration.seconds == 1)

        // [11-20] constant(intro1) — note: the gap 11-20 is intro1 constant
        //   because intro2 starts at 20, so intro1 holds until then
        //   but there's a transition region from 15-16 for the old fadeout
        //   that gets invalidated. The new regions are:
        //   [11-20] const(intro1), [20-21] trans(intro1→intro2),
        //   [21-25] const(intro2), [25-26] trans(intro2→fadeout),
        //   [26-120] const(fadeout)
        #expect(valid[2].timeRange.start.seconds == 11)
        #expect(valid[2].timeRange.duration.seconds == 9) // 20 - 11

        // [20-21] transition(intro1→intro2)
        #expect(valid[3].timeRange.start.seconds == 20)
        #expect(valid[3].timeRange.duration.seconds == 1)

        // [21-25] constant(intro2)
        #expect(valid[4].timeRange.start.seconds == 21)
        #expect(valid[4].timeRange.duration.seconds == 4)

        // [25-26] transition(intro2→fadeout)
        #expect(valid[5].timeRange.start.seconds == 25)
        #expect(valid[5].timeRange.duration.seconds == 1)

        // [26-120] constant(fadeout)
        #expect(valid[6].timeRange.start.seconds == 26)
        #expect(valid[6].timeRange.end.seconds == 120)

        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 5: Set timestamp for first element score
    // makeSlides: [intro1@10, intro2@20, elem1@30, fadeout@35]
    // -----------------------------------------------------------------------

    @Test func step5_settingFirstElementTimestampAddsChunks() {
        // Previous: intro1@10, intro2@20, fadeout@25
        let prevSlides = [
            slide(imgIntro1, 10),
            slide(imgIntro2, 20),
            slide(imgFadeout, 25),
        ]
        let prevRegions = generateRegions(slides: prevSlides, videoDuration: videoDuration, transitionTime: transitionTime)
        var chunks = diffRegionsIntoChunks(newRegions: prevRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        // Simulate: setElementTime(index: 0, time: 30)
        // makeSlides produces: [intro1@10, intro2@20, elem1@30, fadeout@35]
        let slides = [
            slide(imgIntro1, 10),
            slide(imgIntro2, 20),
            slide(imgElem1, 30),
            slide(imgFadeout, 35),
        ]
        let newRegions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        let valid = chunks.filter { !$0.isStale }

        // Verify structure
        #expect(valid[0].type == .noOverlay)
        #expect(valid[0].timeRange.start.seconds == 0)

        // Last chunk extends to video end
        #expect(valid.last?.timeRange.end.seconds == 120)

        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 6: Adjust a timestamp (shift earlier)
    // Move intro2 from t=20 to t=15
    // Tests partial invalidation: trim + reuse + new chunks + stale
    // -----------------------------------------------------------------------

    @Test func step6_adjustingTimestampTrimsAndReusesChunks() {
        // Previous: intro1@10, intro2@20, elem1@30, fadeout@35
        let prevSlides = [
            slide(imgIntro1, 10),
            slide(imgIntro2, 20),
            slide(imgElem1, 30),
            slide(imgFadeout, 35),
        ]
        let prevRegions = generateRegions(slides: prevSlides, videoDuration: videoDuration, transitionTime: transitionTime)
        var chunks = diffRegionsIntoChunks(newRegions: prevRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        // Move intro2 from t=20 to t=15
        // makeSlides produces: [intro1@10, intro2@15, elem1@30, fadeout@35]
        let slides = [
            slide(imgIntro1, 10),
            slide(imgIntro2, 15),
            slide(imgElem1, 30),
            slide(imgFadeout, 35),
        ]
        let newRegions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        let valid = chunks.filter { !$0.isStale }

        // [0-10] noOverlay (reused)
        #expect(valid[0].timeRange.start.seconds == 0)
        #expect(valid[0].timeRange.duration.seconds == 10)

        // [10-11] transition(nil→intro1) (reused)
        #expect(valid[1].timeRange.start.seconds == 10)
        #expect(valid[1].timeRange.duration.seconds == 1)

        // [11-15] constant(intro1) (trimmed from 11-20)
        #expect(valid[2].timeRange.start.seconds == 11)
        #expect(valid[2].timeRange.duration.seconds == 4) // was 9, now 4

        // [15-16] transition(intro1→intro2) (new)
        #expect(valid[3].timeRange.start.seconds == 15)
        #expect(valid[3].timeRange.duration.seconds == 1)

        // [16-30] constant(intro2) (new, holds until elem1)
        #expect(valid[4].timeRange.start.seconds == 16)
        #expect(valid[4].timeRange.duration.seconds == 14)

        // Remaining chunks for elem1 + fadeout
        #expect(valid.last?.timeRange.end.seconds == 120)

        // Some old chunks should be stale
        let staleCount = chunks.filter { $0.isStale }.count
        #expect(staleCount > 0)

        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 7: Multiple element scores with timestamps
    // Progressive: add elem1@30, then elem2@40, then elem3@50
    // Coverage verified at each step
    // -----------------------------------------------------------------------

    @Test func step7_multipleElementScoresWithTimestamps() {
        var chunks: [Chunk] = []

        // Start from empty
        let initialRegions = generateRegions(slides: [], videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: initialRegions, existingChunks: [])

        // Add element1 at t=30
        let slides1 = [
            slide(imgElem1, 30),
            slide(imgFadeout, 35),
        ]
        let regions1 = generateRegions(slides: slides1, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: regions1, existingChunks: chunks)
        assertCoverage(chunks, videoDuration: videoDuration)

        // Add element2 at t=40
        let slides2 = [
            slide(imgElem1, 30),
            slide(imgElem2, 40),
            slide(imgFadeout, 45),
        ]
        let regions2 = generateRegions(slides: slides2, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: regions2, existingChunks: chunks)
        assertCoverage(chunks, videoDuration: videoDuration)

        // Add element3 at t=50
        let slides3 = [
            slide(imgElem1, 30),
            slide(imgElem2, 40),
            slide(imgElem3, 50),
            slide(imgFadeout, 55),
        ]
        let regions3 = generateRegions(slides: slides3, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: regions3, existingChunks: chunks)

        let valid = chunks.filter { !$0.isStale }

        // Verify structure: [0-30] noOverlay, [30-31] trans, [31-40] const(e1),
        //   [40-41] trans, [41-50] const(e2), [50-51] trans, [51-55] const(e3),
        //   [55-56] trans(e3→fadeout), [56-120] const(fadeout)
        #expect(valid.count == 9)
        #expect(valid[0].timeRange.start.seconds == 0)
        #expect(valid[0].timeRange.duration.seconds == 30)
        #expect(valid.last?.timeRange.end.seconds == 120)

        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 8: Remove all timestamps (clear display times)
    // Reverts to single noOverlay. All previous chunks become stale.
    // -----------------------------------------------------------------------

    @Test func step8_clearingTimestampsRevertsToNoOverlay() {
        // Build up state with multiple slides
        let prevSlides = [
            slide(imgIntro1, 10),
            slide(imgIntro2, 20),
            slide(imgElem1, 30),
            slide(imgFadeout, 35),
        ]
        let prevRegions = generateRegions(slides: prevSlides, videoDuration: videoDuration, transitionTime: transitionTime)
        var chunks = diffRegionsIntoChunks(newRegions: prevRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        let prevValidCount = chunks.filter { !$0.isStale }.count
        #expect(prevValidCount > 1)

        // Clear all timestamps → no slides
        let clearedRegions = generateRegions(slides: [], videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: clearedRegions, existingChunks: chunks)

        let valid = chunks.filter { !$0.isStale }
        #expect(valid.count == 1)
        #expect(valid[0].type == .noOverlay)
        #expect(valid[0].timeRange.start == .zero)
        #expect(valid[0].timeRange.duration == videoDuration)

        let staleCount = chunks.filter { $0.isStale }.count
        #expect(staleCount == prevValidCount - 1) // all except reused noOverlay

        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Composite: Full workflow from empty through all changes
    // -----------------------------------------------------------------------

    @Test func composite_fullWorkflowFromEmptyToCleared() {
        var chunks: [Chunk] = []

        // Step 0: Empty
        do {
            let regions = generateRegions(slides: [], videoDuration: videoDuration, transitionTime: transitionTime)
            chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: chunks)
            assertCoverage(chunks, videoDuration: videoDuration)
            #expect(chunks.filter { !$0.isStale }.count == 1)
        }

        // Step 1: Add intro at t=10 with fadeout at t=15
        do {
            let slides = [
                slide(imgIntro1, 10),
                slide(imgFadeout, 15),
            ]
            let regions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
            chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: chunks)
            assertCoverage(chunks, videoDuration: videoDuration)
        }

        // Step 2: Add second intro at t=20, fadeout at t=25
        do {
            let slides = [
                slide(imgIntro1, 10),
                slide(imgIntro2, 20),
                slide(imgFadeout, 25),
            ]
            let regions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
            chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: chunks)
            assertCoverage(chunks, videoDuration: videoDuration)
        }

        // Step 3: Add element at t=30, fadeout at t=35
        do {
            let slides = [
                slide(imgIntro1, 10),
                slide(imgIntro2, 20),
                slide(imgElem1, 30),
                slide(imgFadeout, 35),
            ]
            let regions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
            chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: chunks)
            assertCoverage(chunks, videoDuration: videoDuration)
        }

        // Step 4: Shift second intro from t=20 to t=15
        do {
            let slides = [
                slide(imgIntro1, 10),
                slide(imgIntro2, 15),
                slide(imgElem1, 30),
                slide(imgFadeout, 35),
            ]
            let regions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
            chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: chunks)
            assertCoverage(chunks, videoDuration: videoDuration)
        }

        // Step 5: Clear everything
        do {
            let regions = generateRegions(slides: [], videoDuration: videoDuration, transitionTime: transitionTime)
            chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: chunks)
            assertCoverage(chunks, videoDuration: videoDuration)
            #expect(chunks.filter { !$0.isStale }.count == 1)
        }
    }
}
