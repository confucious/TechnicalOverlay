//
//  OverlayDataChangeTests.swift
//  VideoProcessorTests
//
//  Simulates incremental OverlayData changes and verifies that chunks
//  always span the entire video with no gaps or overlaps.

import Testing
import CoreMedia
import CoreImage
@testable import VideoProcessor

// MARK: - Helpers

/// Distinct CIImages for test slides so each has a unique content identity.
private let testImage1 = CIImage(color: CIColor(red: 0, green: 0, blue: 1, alpha: 0.5))
private let testImage2 = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 0.5))
private let testImage3 = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
private let testImage4 = CIImage(color: CIColor(red: 1, green: 1, blue: 0, alpha: 0.5))
private let testImage5 = CIImage(color: CIColor(red: 1, green: 0, blue: 1, alpha: 0.5))

/// Verifies non-stale chunks form a contiguous timeline from 0 to videoDuration.
@Suite struct OverlayDataChangeTests {

    private let transitionTime: CMTime = CMTime(seconds: 1, preferredTimescale: 1)
    private let videoDuration: CMTime = CMTime(seconds: 120, preferredTimescale: 1)

    // -----------------------------------------------------------------------
    // Coverage invariant helper
    // -----------------------------------------------------------------------

    /// Asserts that the given non-stale chunks cover the video with no gaps or overlaps.
    private func assertCoverage(
        _ chunks: [Chunk],
        videoDuration: CMTime,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let valid = chunks.filter { !$0.isStale }

        guard !valid.isEmpty else {
            Issue.record("no valid chunks", sourceLocation: sourceLocation)
            return
        }

        // First chunk starts at 0
        #expect(
            valid.first?.timeRange.start == .zero,
            "first chunk starts at 0",
            sourceLocation: sourceLocation
        )

        // Last chunk ends at videoDuration
        #expect(
            valid.last?.timeRange.end == videoDuration,
            "last chunk ends at videoDuration",
            sourceLocation: sourceLocation
        )

        // Consecutive chunks touch (no gap, no overlap)
        for i in 1..<valid.count {
            #expect(
                valid[i - 1].timeRange.end == valid[i].timeRange.start,
                "gap or overlap between chunk \(i - 1) and \(i)",
                sourceLocation: sourceLocation
            )
        }

        // Total duration matches
        let total = valid.reduce(CMTime.zero) { $0 + $1.timeRange.duration }
        #expect(
            total == videoDuration,
            "total duration mismatch",
            sourceLocation: sourceLocation
        )
    }

    // -----------------------------------------------------------------------
    // Step 0: Empty OverlayData
    // -----------------------------------------------------------------------

    @Test func step0_emptyOverlayDataProducesSingleNoOverlay() {
        // OverlayData() -> makeSlides() -> []
        let regions = generateRegions(
            slides: [],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        let chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: [])

        #expect(chunks.count == 1)
        #expect(chunks[0].type == .noOverlay)
        #expect(chunks[0].timeRange.start == .zero)
        #expect(chunks[0].timeRange.duration == videoDuration)
        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 1: Introduction slides WITHOUT timestamps
    // No displayTime -> makeSlides returns [] -> no change
    // -----------------------------------------------------------------------

    @Test func step1_introductionSlidesWithoutTimestampsDoNotChangeChunks() {
        // Simulating: OverlayData with introductionTexts but no displayTime
        // makeSlides filters by displayTime, so result is still []
        let slides: [Slide] = []

        let regions = generateRegions(
            slides: slides,
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        let chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: [])

        #expect(chunks.count == 1)
        #expect(chunks[0].type == .noOverlay)
        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 2: Element scores WITHOUT timestamps
    // Still no slides -> no change
    // -----------------------------------------------------------------------

    @Test func step2_elementScoresWithoutTimestampsDoNotChangeChunks() {
        // Simulating: OverlayData with elementScores but no displayTime
        let slides: [Slide] = []

        let regions = generateRegions(
            slides: slides,
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        let chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: [])

        #expect(chunks.count == 1)
        #expect(chunks[0].type == .noOverlay)
        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 3: Set timestamp for first introduction slide
    // Splits the noOverlay: [0-10] noOverlay, [10-11] transition, [11-120] constant
    // -----------------------------------------------------------------------

    @Test func step3_settingFirstIntroductionTimestampSplitsChunks() {
        // Previous state: single noOverlay chunk
        let initialRegions = generateRegions(
            slides: [],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        var chunks = diffRegionsIntoChunks(newRegions: initialRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        // Set displayTime for first intro at t=10
        let intro1 = Slide(image: testImage1, startTime: CMTime(seconds: 10, preferredTimescale: 1))
        let newRegions = generateRegions(
            slides: [intro1],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        // Expected: [0-10] noOverlay, [10-11] transition(nil->intro1), [11-120] constant(intro1)
        let valid = chunks.filter { !$0.isStale }
        #expect(valid.count == 3)
        #expect(valid[0].type == .noOverlay)
        #expect(valid[0].timeRange.start.seconds == 0)
        #expect(valid[0].timeRange.duration.seconds == 10)

        if case .transition = valid[1].type { } else {
            Issue.record("expected transition at index 1")
        }
        #expect(valid[1].timeRange.start.seconds == 10)
        #expect(valid[1].timeRange.duration.seconds == 1)

        if case .constant = valid[2].type { } else {
            Issue.record("expected constant at index 2")
        }
        #expect(valid[2].timeRange.start.seconds == 11)
        #expect(valid[2].timeRange.end.seconds == 120)

        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 4: Set timestamp for second introduction slide
    // Adds transition + constant for intro2, trims intro1 constant
    // -----------------------------------------------------------------------

    @Test func step4_settingSecondIntroductionTimestampSplitsChunks() {
        // Previous state: intro1 at t=10
        let intro1 = Slide(image: testImage1, startTime: CMTime(seconds: 10, preferredTimescale: 1))
        let prevRegions = generateRegions(
            slides: [intro1],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        var chunks = diffRegionsIntoChunks(newRegions: prevRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        // Set displayTime for second intro at t=20
        let intro2 = Slide(image: testImage2, startTime: CMTime(seconds: 20, preferredTimescale: 1))
        let newRegions = generateRegions(
            slides: [intro1, intro2],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        // Expected:
        // [0-10] noOverlay, [10-11] transition(nil->intro1),
        // [11-20] constant(intro1), [20-21] transition(intro1->intro2),
        // [21-120] constant(intro2)
        let valid = chunks.filter { !$0.isStale }
        #expect(valid.count == 5)

        #expect(valid[0].type == .noOverlay)
        #expect(valid[0].timeRange.start.seconds == 0)
        #expect(valid[0].timeRange.duration.seconds == 10)

        #expect(valid[1].timeRange.start.seconds == 10)
        #expect(valid[1].timeRange.duration.seconds == 1)

        #expect(valid[2].timeRange.start.seconds == 11)
        #expect(valid[2].timeRange.duration.seconds == 9) // 20 - 11

        #expect(valid[3].timeRange.start.seconds == 20)
        #expect(valid[3].timeRange.duration.seconds == 1)

        #expect(valid[4].timeRange.start.seconds == 21)
        #expect(valid[4].timeRange.end.seconds == 120)

        // Verify reuse: [0-10] noOverlay and [10-11] transition should be reused
        let staleCount = chunks.filter { $0.isStale }.count
        #expect(staleCount == 0) // no stale chunks - all old regions were reused or trimmed

        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 5: Set timestamp for first element score
    // Adds element slide after intros
    // -----------------------------------------------------------------------

    @Test func step5_settingFirstElementTimestampAddsChunks() {
        // Previous state: intro1 at t=10, intro2 at t=20
        let intro1 = Slide(image: testImage1, startTime: CMTime(seconds: 10, preferredTimescale: 1))
        let intro2 = Slide(image: testImage2, startTime: CMTime(seconds: 20, preferredTimescale: 1))
        let prevRegions = generateRegions(
            slides: [intro1, intro2],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        var chunks = diffRegionsIntoChunks(newRegions: prevRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        // Set displayTime for first element at t=30
        let element1 = Slide(image: testImage3, startTime: CMTime(seconds: 30, preferredTimescale: 1))
        let newRegions = generateRegions(
            slides: [intro1, intro2, element1],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        // Expected:
        // [0-10] noOverlay, [10-11] trans(nil->intro1), [11-20] const(intro1),
        // [20-21] trans(intro1->intro2), [21-30] const(intro2),
        // [30-31] trans(intro2->element1), [31-120] const(element1)
        let valid = chunks.filter { !$0.isStale }
        #expect(valid.count == 7)

        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 6: Adjust a timestamp (shift earlier)
    // Tests partial invalidation: trim + reuse + new chunks
    // -----------------------------------------------------------------------

    @Test func step6_adjustingTimestampTrimsAndReusesChunks() {
        // Previous state: intro1 at t=10, intro2 at t=20
        let intro1 = Slide(image: testImage1, startTime: CMTime(seconds: 10, preferredTimescale: 1))
        let intro2Old = Slide(image: testImage2, startTime: CMTime(seconds: 20, preferredTimescale: 1))
        let prevRegions = generateRegions(
            slides: [intro1, intro2Old],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        var chunks = diffRegionsIntoChunks(newRegions: prevRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        // Move intro2 from t=20 to t=15
        let intro2New = Slide(image: testImage2, startTime: CMTime(seconds: 15, preferredTimescale: 1))
        let newRegions = generateRegions(
            slides: [intro1, intro2New],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        // Expected:
        // [0-10] noOverlay (reused), [10-11] trans(nil->intro1) (reused),
        // [11-15] const(intro1) (trimmed from 11-20),
        // [15-16] trans(intro1->intro2) (new),
        // [16-120] const(intro2) (new)
        let valid = chunks.filter { !$0.isStale }
        #expect(valid.count == 5)

        #expect(valid[0].timeRange.start.seconds == 0)
        #expect(valid[0].timeRange.duration.seconds == 10)

        #expect(valid[1].timeRange.start.seconds == 10)
        #expect(valid[1].timeRange.duration.seconds == 1)

        #expect(valid[2].timeRange.start.seconds == 11)
        #expect(valid[2].timeRange.duration.seconds == 4) // 15 - 11 (trimmed)

        #expect(valid[3].timeRange.start.seconds == 15)
        #expect(valid[3].timeRange.duration.seconds == 1)

        #expect(valid[4].timeRange.start.seconds == 16)
        #expect(valid[4].timeRange.end.seconds == 120)

        // Some old chunks should be stale (the old intro2 transition at 20-21,
        // the old intro2 constant at 21-120)
        let staleCount = chunks.filter { $0.isStale }.count
        #expect(staleCount > 0)

        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 7: Multiple element scores with timestamps
    // Progressive splitting with 3 elements
    // -----------------------------------------------------------------------

    @Test func step7_multipleElementScoresWithTimestamps() {
        // Start from empty
        let initialRegions = generateRegions(
            slides: [],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        var chunks = diffRegionsIntoChunks(newRegions: initialRegions, existingChunks: [])

        // Add element1 at t=30
        let element1 = Slide(image: testImage3, startTime: CMTime(seconds: 30, preferredTimescale: 1))
        let regions1 = generateRegions(
            slides: [element1],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        chunks = diffRegionsIntoChunks(newRegions: regions1, existingChunks: chunks)
        assertCoverage(chunks, videoDuration: videoDuration)

        // Add element2 at t=40
        let element2 = Slide(image: testImage4, startTime: CMTime(seconds: 40, preferredTimescale: 1))
        let regions2 = generateRegions(
            slides: [element1, element2],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        chunks = diffRegionsIntoChunks(newRegions: regions2, existingChunks: chunks)
        assertCoverage(chunks, videoDuration: videoDuration)

        // Add element3 at t=50
        let element3 = Slide(image: testImage5, startTime: CMTime(seconds: 50, preferredTimescale: 1))
        let regions3 = generateRegions(
            slides: [element1, element2, element3],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        chunks = diffRegionsIntoChunks(newRegions: regions3, existingChunks: chunks)

        // Final state:
        // [0-30] noOverlay, [30-31] trans(nil->e1), [31-40] const(e1),
        // [40-41] trans(e1->e2), [41-50] const(e2),
        // [50-51] trans(e2->e3), [51-120] const(e3)
        let valid = chunks.filter { !$0.isStale }
        #expect(valid.count == 7)

        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 8: Remove all timestamps (clear display times)
    // Reverts to single noOverlay. All previous chunks become stale.
    // -----------------------------------------------------------------------

    @Test func step8_clearingTimestampsRevertsToNoOverlay() {
        // Build up state with multiple slides
        let intro1 = Slide(image: testImage1, startTime: CMTime(seconds: 10, preferredTimescale: 1))
        let intro2 = Slide(image: testImage2, startTime: CMTime(seconds: 20, preferredTimescale: 1))
        let element1 = Slide(image: testImage3, startTime: CMTime(seconds: 30, preferredTimescale: 1))
        let regions = generateRegions(
            slides: [intro1, intro2, element1],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        var chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        let prevValidCount = chunks.filter { !$0.isStale }.count
        #expect(prevValidCount > 1)

        // Clear all timestamps -> no slides
        let clearedRegions = generateRegions(
            slides: [],
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        chunks = diffRegionsIntoChunks(newRegions: clearedRegions, existingChunks: chunks)

        // Result: single noOverlay
        let valid = chunks.filter { !$0.isStale }
        #expect(valid.count == 1)
        #expect(valid[0].type == .noOverlay)
        #expect(valid[0].timeRange.start == .zero)
        #expect(valid[0].timeRange.duration == videoDuration)

        // All previous chunks should be stale
        let staleCount = chunks.filter { $0.isStale }.count
        #expect(staleCount == prevValidCount - 1) // all except the reused noOverlay

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

        // Step 1: Add intro at t=10
        do {
            let slides = [Slide(image: testImage1, startTime: CMTime(seconds: 10, preferredTimescale: 1))]
            let regions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
            chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: chunks)
            assertCoverage(chunks, videoDuration: videoDuration)
        }

        // Step 2: Add second intro at t=20
        do {
            let slides = [
                Slide(image: testImage1, startTime: CMTime(seconds: 10, preferredTimescale: 1)),
                Slide(image: testImage2, startTime: CMTime(seconds: 20, preferredTimescale: 1)),
            ]
            let regions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
            chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: chunks)
            assertCoverage(chunks, videoDuration: videoDuration)
        }

        // Step 3: Add element at t=30
        do {
            let slides = [
                Slide(image: testImage1, startTime: CMTime(seconds: 10, preferredTimescale: 1)),
                Slide(image: testImage2, startTime: CMTime(seconds: 20, preferredTimescale: 1)),
                Slide(image: testImage3, startTime: CMTime(seconds: 30, preferredTimescale: 1)),
            ]
            let regions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
            chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: chunks)
            assertCoverage(chunks, videoDuration: videoDuration)
        }

        // Step 4: Shift second intro from t=20 to t=15
        do {
            let slides = [
                Slide(image: testImage1, startTime: CMTime(seconds: 10, preferredTimescale: 1)),
                Slide(image: testImage2, startTime: CMTime(seconds: 15, preferredTimescale: 1)),
                Slide(image: testImage3, startTime: CMTime(seconds: 30, preferredTimescale: 1)),
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
