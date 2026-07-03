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

        #expect(valid.first?.stitchingTimeRange?.start == .zero, "first chunk starts at 0")
        #expect(valid.last?.stitchingTimeRange?.end == videoDuration, "last chunk ends at videoDuration")

        for i in 1..<valid.count {
            #expect(
                valid[i - 1].stitchingTimeRange?.end == valid[i].stitchingTimeRange?.start,
                "gap or overlap between chunk \(i - 1) and \(i)"
            )
        }

        let total = valid.reduce(CMTime.zero) {
            $0 + ($1.stitchingTimeRange?.duration ?? CMTime(
                seconds: 0,
                preferredTimescale: 1
            ))
        }
        #expect(total == videoDuration, "total duration mismatch")
    }
    
    private func assertExpectedChunks(
        _ expectedChunks: [(ChunkType, Double)],
        chunks: [Chunk],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let valid = chunks.filter { !$0.isStale }
        
        #expect(
            valid.count == expectedChunks.count,
            sourceLocation: sourceLocation
        )
        
        zip(valid, expectedChunks).forEach { (chunk, expected) in
            #expect(chunk.type == expected.0, sourceLocation: sourceLocation)
            #expect(
                chunk.stitchingTimeRange?.start.seconds == expected.1,
                sourceLocation: sourceLocation
            )
        }
    }

    // -----------------------------------------------------------------------
    // Step 0: Empty OverlayData
    // -----------------------------------------------------------------------

    @Test func step0_emptyOverlayDataProducesSingleNoOverlay() {
        let regions = generateRegions(slides: [], videoDuration: videoDuration, transitionTime: transitionTime)
        let chunks = diffRegionsIntoChunks(newRegions: regions, existingChunks: [])

        assertExpectedChunks([(.noOverlay, 0)], chunks: chunks)
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

        assertExpectedChunks([(.noOverlay, 0)], chunks: chunks)
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

        assertExpectedChunks([(.noOverlay, 0)], chunks: chunks)
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

        assertExpectedChunks([
            (.noOverlay, 0),
            (.transition(from: nil, to: slides[0].image), 10),
            (.constant(slides[0].image!), 11),
            (.transition(from: slides[0].image, to: nil), 15),
            (.noOverlay, 16)
        ], chunks: chunks)

        assertCoverage(chunks, videoDuration: videoDuration)
    }

    // -----------------------------------------------------------------------
    // Step 4: Set timestamp for second introduction slide
    // makeSlides: [intro1@10, intro2@20, fadeout@25]
    // Reuse: [0-10] noOverlay is new (never reused),
    //   [10-11] transition exact match → reused,
    //   [11-20] constant(intro1) overlaps old [11-15] → reuse [11-15], new [15-20]
    // -----------------------------------------------------------------------

    @Test func step4_settingSecondIntroductionTimestampSplitsChunks() {
        // Previous: intro1@10, fadeout@15
        let prevSlides = [
            slide(imgIntro1, 10),
            slide(nil, 15),
        ]
        let prevRegions = generateRegions(slides: prevSlides, videoDuration: videoDuration, transitionTime: transitionTime)
        var chunks = diffRegionsIntoChunks(newRegions: prevRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        // Simulate: setIntroTime(index: 1, time: 20)
        // makeSlides produces: [intro1@10, intro2@20, nil@25]
        let slides = [
            slide(imgIntro1, 10),
            slide(imgIntro2, 20),
            slide(nil, 25),
        ]
        let newRegions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        assertExpectedChunks([
            (.noOverlay, 0),
            (.transition(from: nil, to: slides[0].image), 10),
            (.constant(slides[0].image!), 11),
            (.constant(slides[0].image!), 15),
            (.transition(from: slides[0].image, to: slides[1].image), 20),
            (.constant(slides[1].image!), 21),
            (.transition(from: slides[1].image, to: nil), 25),
            (.noOverlay, 26)
        ], chunks: chunks)

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
            slide(nil, 25),
        ]
        let prevRegions = generateRegions(slides: prevSlides, videoDuration: videoDuration, transitionTime: transitionTime)
        var chunks = diffRegionsIntoChunks(newRegions: prevRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        // Simulate: setElementTime(index: 0, time: 30)
        // makeSlides produces: [intro1@10, intro2@20, fadeout@25, elem1@30, fadeout@35]
        let slides = [
            slide(imgIntro1, 10),
            slide(imgIntro2, 20),
            slide(nil, 25),
            slide(imgElem1, 30),
            slide(nil, 35),
        ]
        let newRegions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        assertExpectedChunks([
            (.noOverlay, 0),
            (.transition(from: nil, to: slides[0].image), 10),
            (.constant(slides[0].image!), 11),
            (.transition(from: slides[0].image, to: slides[1].image), 20),
            (.constant(slides[1].image!), 21),
            (.transition(from: slides[1].image, to: nil), 25),
            (.noOverlay, 26),
            (.transition(from: nil, to: slides[3].image), 30),
            (.constant(slides[3].image!), 31),
            (.transition(from: slides[3].image, to: nil), 35),
            (.noOverlay, 36)
        ], chunks: chunks)

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
            slide(nil, 25),
            slide(imgElem1, 30),
            slide(nil, 35),
        ]
        let prevRegions = generateRegions(slides: prevSlides, videoDuration: videoDuration, transitionTime: transitionTime)
        var chunks = diffRegionsIntoChunks(newRegions: prevRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        // Move intro2 from t=20 to t=15
        let slides = [
            slide(imgIntro1, 10),
            slide(imgIntro2, 15),
            slide(nil, 20),
            slide(imgElem1, 30),
            slide(nil, 35),
        ]
        let newRegions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        assertExpectedChunks([
            (.noOverlay, 0),
            (.transition(from: nil, to: slides[0].image), 10),
            (.constant(slides[0].image!), 11),
            (.transition(from: slides[0].image, to: slides[1].image), 15),
            (.constant(slides[1].image!), 16),
            (.transition(from: slides[1].image, to: nil), 20),
            (.noOverlay, 21),
            (.transition(from: nil, to: slides[3].image), 30),
            (.constant(slides[3].image!), 31),
            (.transition(from: slides[3].image, to: nil), 35),
            (.noOverlay, 36)
        ], chunks: chunks)

        // Some old chunks should be stale
        let staleCount = chunks.filter { $0.isStale }.count
        #expect(staleCount > 0)

        assertCoverage(chunks, videoDuration: videoDuration)
    }

    @Test func step6b_adjustingTimestampTrimsAndReusesChunks() {
        // Previous: intro1@10, intro2@20, elem1@30, fadeout@35
        let prevSlides = [
            slide(imgIntro1, 10),
            slide(imgIntro2, 20),
            slide(nil, 25),
            slide(imgElem1, 30),
            slide(nil, 35),
        ]
        let prevRegions = generateRegions(slides: prevSlides, videoDuration: videoDuration, transitionTime: transitionTime)
        var chunks = diffRegionsIntoChunks(newRegions: prevRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        // Move intro1 from t=10 to t=5
        let slides = [
            slide(imgIntro1, 5),
            slide(imgIntro2, 20),
            slide(nil, 25),
            slide(imgElem1, 30),
            slide(nil, 35),
        ]
        let newRegions = generateRegions(slides: slides, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        assertExpectedChunks([
            (.noOverlay, 0),
            (.transition(from: nil, to: imgIntro1), 5),
            (.constant(imgIntro1), 6), // [6-11] new constant
            (.constant(imgIntro1), 11), // [11-20] reused constant
            (.transition(from: imgIntro1, to: imgIntro2), 20),
            (.constant(imgIntro2), 21),
            (.transition(from: imgIntro2, to: nil), 25),
            (.noOverlay, 26),
            (.transition(from: nil, to: imgElem1), 30),
            (.constant(imgElem1), 31),
            (.transition(from: imgElem1, to: nil), 35),
            (.noOverlay, 36)
        ], chunks: chunks)

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
        
        assertExpectedChunks([(.noOverlay, 0)], chunks: chunks)
        assertCoverage(chunks, videoDuration: videoDuration)

        // Add element1 at t=30
        let slides1 = [
            slide(imgElem1, 30),
            slide(nil, 35),
        ]
        let regions1 = generateRegions(slides: slides1, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: regions1, existingChunks: chunks)

        assertExpectedChunks([
            (.noOverlay, 0),
            (.transition(from: nil, to: imgElem1), 30),
            (.constant(imgElem1), 31),
            (.transition(from: imgElem1, to: nil), 35),
            (.noOverlay, 36)
        ], chunks: chunks)
        assertCoverage(chunks, videoDuration: videoDuration)

        // Add element2 at t=40
        let slides2 = [
            slide(imgElem1, 30),
            slide(imgElem2, 40),
            slide(nil, 45),
        ]
        let regions2 = generateRegions(slides: slides2, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: regions2, existingChunks: chunks)

        assertExpectedChunks([
            (.noOverlay, 0),
            (.transition(from: nil, to: imgElem1), 30),
            (.constant(imgElem1), 31),
            (.constant(imgElem1), 35),
            (.transition(from: imgElem1, to: imgElem2), 40),
            (.constant(imgElem2), 41),
            (.transition(from: imgElem2, to: nil), 45),
            (.noOverlay, 46)
        ], chunks: chunks)
        assertCoverage(chunks, videoDuration: videoDuration)

        // Add element3 at t=50
        let slides3 = [
            slide(imgElem1, 30),
            slide(imgElem2, 40),
            slide(imgElem3, 50),
            slide(nil, 55),
        ]
        let regions3 = generateRegions(slides: slides3, videoDuration: videoDuration, transitionTime: transitionTime)
        chunks = diffRegionsIntoChunks(newRegions: regions3, existingChunks: chunks)

        assertExpectedChunks([
            (.noOverlay, 0),
            (.transition(from: nil, to: imgElem1), 30),
            (.constant(imgElem1), 31),
            (.constant(imgElem1), 35),
            (.transition(from: imgElem1, to: imgElem2), 40),
            (.constant(imgElem2), 41),
            (.constant(imgElem2), 45),
            (.transition(from: imgElem2, to: imgElem3), 50),
            (.constant(imgElem3), 51),
            (.transition(from: imgElem3, to: nil), 55),
            (.noOverlay, 56)
        ], chunks: chunks)
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
            slide(nil, 35),
        ]
        let prevRegions = generateRegions(slides: prevSlides, videoDuration: videoDuration, transitionTime: transitionTime)
        var chunks = diffRegionsIntoChunks(newRegions: prevRegions, existingChunks: [])
        assertCoverage(chunks, videoDuration: videoDuration)

        let prevValidCount = chunks.filter {
            !$0.isStale && $0.type != .noOverlay
        }.count
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
        #expect(staleCount == prevValidCount) // all previous valid non-noOverlay chunks become stale.

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
                slide(nil, 15),
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
                slide(nil, 25),
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
                slide(nil, 35),
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
                slide(nil, 35),
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
