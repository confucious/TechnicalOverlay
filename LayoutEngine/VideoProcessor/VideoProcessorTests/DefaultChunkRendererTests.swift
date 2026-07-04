//
//  DefaultChunkRendererTests.swift
//  VideoProcessorTests
//

import Testing
import AVFoundation
import CoreImage
import Foundation
@testable import VideoProcessor

// MARK: - Test Asset

/// Path to a real video file for integration tests.
private let testVideoURL = URL(
    fileURLWithPath: "/Users/jhsu/dev/TechnicalOverlay/TechnicalOverlay/TechnicalOverlay/Boston Open 2025.mov"
)

private func makeTestAsset() -> AVAsset? {
    guard FileManager.default.fileExists(atPath: testVideoURL.path) else { return nil }
    return AVURLAsset(url: testVideoURL)
}

// MARK: - Tests

@Suite
struct DefaultChunkRendererTests {

    // MARK: - Initialization

    @Test func initCreatesRenderer() {
        let asset = makeTestAsset() ?? AVAsset()
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        let renderer = DefaultChunkRenderer(
            sourceAsset: asset,
            outputDirectory: directory
        )
        #expect(renderer != nil)
    }

    // MARK: - Staleness Check

    @Test func renderStaleChunkReturnsNil() async {
        guard let asset = makeTestAsset() else {
            return
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        let renderer = DefaultChunkRenderer(
            sourceAsset: asset,
            outputDirectory: directory
        )

        var chunk = Chunk(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 30)),
            type: .constant(CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5)))
        )
        chunk.stitchingTimeRange = nil // stale

        let result = await renderer.render(chunk)
        #expect(result == nil)
    }

    // MARK: - noOverlay Returns Nil

    @Test func renderNoOverlayChunkReturnsNil() async {
        guard let asset = makeTestAsset() else {
            return
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        let renderer = DefaultChunkRenderer(
            sourceAsset: asset,
            outputDirectory: directory
        )

        let chunk = Chunk(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 30)),
            type: .noOverlay
        )

        let result = await renderer.render(chunk)
        #expect(result == nil)
    }

    // MARK: - Constant Chunk Rendering

    @Test func renderConstantChunkProducesOutputFile() async throws {
        guard let asset = makeTestAsset() else {
            return
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        let renderer = DefaultChunkRenderer(
            sourceAsset: asset,
            outputDirectory: directory
        )

        let chunk = Chunk(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 30)),
            type: .constant(CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5)))
        )

        let result = await renderer.render(chunk)
        #expect(result != nil, "Constant chunk should produce output file")
        #expect(FileManager.default.fileExists(atPath: result!.path))

        // Verify output is a valid MOV with video track
        let outputAsset = AVURLAsset(url: result!)
        let tracks = try await outputAsset.load(.tracks)
        let videoTracks = tracks.filter { $0.mediaType == .video }
        #expect(videoTracks.count > 0, "Output should have a video track")
    }

    // MARK: - Transition Chunk Rendering

    @Test func renderTransitionChunkProducesOutputFile() async throws {
        guard let asset = makeTestAsset() else {
            return
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        let renderer = DefaultChunkRenderer(
            sourceAsset: asset,
            outputDirectory: directory
        )

        let from = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        let to = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 0.5))

        let chunk = Chunk(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 30)),
            type: .transition(from: from, to: to)
        )

        let result = await renderer.render(chunk)
        #expect(result != nil, "Transition chunk should produce output file")
        #expect(FileManager.default.fileExists(atPath: result!.path))
    }

    // MARK: - Output File Validity

    @Test func renderedChunkHasCorrectDuration() async throws {
        guard let asset = makeTestAsset() else {
            return
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        let renderer = DefaultChunkRenderer(
            sourceAsset: asset,
            outputDirectory: directory
        )

        let duration = CMTime(seconds: 3, preferredTimescale: 1)
        let chunk = Chunk(
            timeRange: CMTimeRange(start: .zero, duration: duration),
            type: .constant(CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.3)))
        )

        let result = await renderer.render(chunk)
        #expect(result != nil)

        let outputAsset = AVURLAsset(url: result!)
        let actualDuration = try await outputAsset.load(.duration)
        // Duration should match the chunk's stitching range (within a small tolerance)
        let tolerance: Double = 0.2
        #expect(abs(actualDuration.seconds - duration.seconds) < tolerance,
                "Output duration \(actualDuration.seconds)s should match chunk duration \(duration.seconds)s")
    }

    @Test func renderedChunkHasAudioTrack() async throws {
        guard let asset = makeTestAsset() else {
            return
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        let renderer = DefaultChunkRenderer(
            sourceAsset: asset,
            outputDirectory: directory
        )

        let chunk = Chunk(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 30)),
            type: .constant(CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.3)))
        )

        let result = await renderer.render(chunk)
        #expect(result != nil)

        let outputAsset = AVURLAsset(url: result!)
        let tracks = try await outputAsset.load(.tracks)
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        #expect(audioTracks.count > 0, "Output should have an audio track (passthrough from source)")
    }
}
