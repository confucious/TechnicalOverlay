//
//  DefaultStitcherTests.swift
//  VideoProcessorTests
//

import Testing
import AVFoundation
import CoreImage
import Foundation
@testable import VideoProcessor

// MARK: - Test Helpers

/// Path to a real video file for integration tests.
private let testVideoURL = URL(
    fileURLWithPath: "/Users/jhsu/dev/TechnicalOverlay/TechnicalOverlay/TechnicalOverlay/Boston Open 2025.mov"
)

private func makeTestAsset() -> AVAsset? {
    guard FileManager.default.fileExists(atPath: testVideoURL.path) else { return nil }
    return AVURLAsset(url: testVideoURL)
}

/// Renders a constant chunk to a real file for use in stitching tests.
private func renderConstantChunk(
    asset: AVAsset,
    timeRange: CMTimeRange,
    image: CIImage
) async throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    let renderer = DefaultChunkRenderer(
        sourceAsset: asset,
        outputDirectory: directory
    )

    var chunk = Chunk(
        timeRange: timeRange,
        type: .constant(image)
    )
    chunk.stitchingTimeRange = timeRange

    guard let url = await renderer.render(chunk) else {
        throw NSError(domain: "RenderFailed", code: 1, userInfo: nil)
    }
    return url
}

/// Renders a transition chunk to a real file for use in stitching tests.
private func renderTransitionChunk(
    asset: AVAsset,
    timeRange: CMTimeRange,
    from: CIImage,
    to: CIImage
) async throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    let renderer = DefaultChunkRenderer(
        sourceAsset: asset,
        outputDirectory: directory
    )

    var chunk = Chunk(
        timeRange: timeRange,
        type: .transition(from: from, to: to)
    )
    chunk.stitchingTimeRange = timeRange

    guard let url = await renderer.render(chunk) else {
        throw NSError(domain: "RenderFailed", code: 1, userInfo: nil)
    }
    return url
}

// MARK: - Tests

@Suite
struct DefaultStitcherTests {

    private let stitcher = DefaultStitcher()

    // MARK: - Empty/Stale

    @Test func stitchEmptyChunksReturnsNil() async {
        guard let asset = makeTestAsset() else {
            return
        }
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "empty.mov")
        let result = await stitcher.stitch(
            chunks: [],
            sourceAsset: asset,
            videoDuration: CMTime(seconds: 10, preferredTimescale: 1),
            to: outputURL
        )
        #expect(result != nil)
        let outputAsset = AVURLAsset(url: result!)
        let duration = try await outputAsset.load(.duration)
        #expect(duration.seconds == 0.0)
    }

    @Test func stitchAllStaleChunksProducesEmptyOutput() async {
        guard let asset = makeTestAsset() else {
            return
        }
        let chunk = Chunk(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 5, preferredTimescale: 1)),
            type: .noOverlay
        )
        let result = await stitcher.stitch(
            chunks: [chunk],
            sourceAsset: asset,
            videoDuration: CMTime(seconds: 10, preferredTimescale: 1),
            to: URL(fileURLWithPath: NSTemporaryDirectory() + "stale.mov")
        )
        #expect(result != nil)
    }

    // MARK: - noOverlay Chunks

    @Test func stitchNoOverlayChunksCopiesFromSource() async throws {
        guard let asset = makeTestAsset() else {
            return
        }

        let timeRange = CMTimeRange(start: CMTime(seconds: 2, preferredTimescale: 1), duration: CMTime(seconds: 3, preferredTimescale: 1))
        var chunk = Chunk(
            timeRange: timeRange,
            type: .noOverlay
        )
        chunk.stitchingTimeRange = timeRange

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "nooverlay.mov")
        let result = await stitcher.stitch(
            chunks: [chunk],
            sourceAsset: asset,
            videoDuration: CMTime(seconds: 10, preferredTimescale: 1),
            to: outputURL
        )

        #expect(result != nil, "Stitching should produce output")
        let outputAsset = AVURLAsset(url: result!)
        let duration = try await outputAsset.load(.duration)
        #expect(abs(duration.seconds - 3.0) < 0.3, "Output duration \(duration.seconds) should be ~3s")
    }

    // MARK: - Constant Chunk — Full Range

    @Test func stitchConstantChunkFullRange() async throws {
        guard let asset = makeTestAsset() else {
            return
        }

        let timeRange = CMTimeRange(start: CMTime(seconds: 10, preferredTimescale: 1), duration: CMTime(seconds: 5, preferredTimescale: 1))
        let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        let renderedURL = try await renderConstantChunk(
            asset: asset,
            timeRange: timeRange,
            image: image
        )

        var chunk = Chunk(
            id: UUID(),
            timeRange: timeRange,
            type: .constant(image),
            renderState: .rendered(renderedURL)
        )
        chunk.stitchingTimeRange = timeRange

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "constant_full.mov")
        let result = await stitcher.stitch(
            chunks: [chunk],
            sourceAsset: asset,
            videoDuration: CMTime(seconds: 20, preferredTimescale: 1),
            to: outputURL
        )

        #expect(result != nil, "Stitching should produce output")
        let outputAsset = AVURLAsset(url: result!)
        let duration = try await outputAsset.load(.duration)
        #expect(abs(duration.seconds - 5.0) < 0.3, "Output duration \(duration.seconds) should be ~5s")
    }

    // MARK: - Constant Chunk — Partial End Range

    @Test func stitchConstantChunkPartialEndRange() async throws {
        guard let asset = makeTestAsset() else {
            return
        }

        let timeRange = CMTimeRange(start: CMTime(seconds: 10, preferredTimescale: 1), duration: CMTime(seconds: 10, preferredTimescale: 1))
        let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        let renderedURL = try await renderConstantChunk(
            asset: asset,
            timeRange: timeRange,
            image: image
        )

        // stitchingTimeRange is the last 5 seconds of the 10s rendered chunk
        var chunk = Chunk(
            id: UUID(),
            timeRange: timeRange,
            type: .constant(image),
            renderState: .rendered(renderedURL)
        )
        chunk.stitchingTimeRange = CMTimeRange(
            start: CMTime(seconds: 15, preferredTimescale: 1),
            duration: CMTime(seconds: 5, preferredTimescale: 1)
        )

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "constant_end.mov")
        let result = await stitcher.stitch(
            chunks: [chunk],
            sourceAsset: asset,
            videoDuration: CMTime(seconds: 20, preferredTimescale: 1),
            to: outputURL
        )

        #expect(result != nil, "Stitching should produce output")
        let outputAsset = AVURLAsset(url: result!)
        let duration = try await outputAsset.load(.duration)
        #expect(abs(duration.seconds - 5.0) < 0.3, "Output duration \(duration.seconds) should be ~5s (last half of rendered chunk)")
    }

    // MARK: - Constant Chunk — Partial Start Range

    @Test func stitchConstantChunkPartialStartRange() async throws {
        guard let asset = makeTestAsset() else {
            return
        }

        let timeRange = CMTimeRange(start: CMTime(seconds: 10, preferredTimescale: 1), duration: CMTime(seconds: 10, preferredTimescale: 1))
        let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        let renderedURL = try await renderConstantChunk(
            asset: asset,
            timeRange: timeRange,
            image: image
        )

        // stitchingTimeRange is the first 5 seconds of the 10s rendered chunk
        var chunk = Chunk(
            id: UUID(),
            timeRange: timeRange,
            type: .constant(image),
            renderState: .rendered(renderedURL)
        )
        chunk.stitchingTimeRange = CMTimeRange(
            start: CMTime(seconds: 10, preferredTimescale: 1),
            duration: CMTime(seconds: 5, preferredTimescale: 1)
        )

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "constant_start.mov")
        let result = await stitcher.stitch(
            chunks: [chunk],
            sourceAsset: asset,
            videoDuration: CMTime(seconds: 20, preferredTimescale: 1),
            to: outputURL
        )

        #expect(result != nil, "Stitching should produce output")
        let outputAsset = AVURLAsset(url: result!)
        let duration = try await outputAsset.load(.duration)
        #expect(abs(duration.seconds - 5.0) < 0.3, "Output duration \(duration.seconds) should be ~5s (first half of rendered chunk)")
    }

    // MARK: - Transition Chunk

    @Test func stitchTransitionChunksCopiesFromRendered() async throws {
        guard let asset = makeTestAsset() else {
            return
        }

        let timeRange = CMTimeRange(start: CMTime(seconds: 10, preferredTimescale: 1), duration: CMTime(seconds: 1, preferredTimescale: 1))
        let from = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        let to = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 0.5))
        let renderedURL = try await renderTransitionChunk(
            asset: asset,
            timeRange: timeRange,
            from: from,
            to: to
        )

        var chunk = Chunk(
            id: UUID(),
            timeRange: timeRange,
            type: .transition(from: from, to: to),
            renderState: .rendered(renderedURL)
        )
        chunk.stitchingTimeRange = timeRange

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "transition.mov")
        let result = await stitcher.stitch(
            chunks: [chunk],
            sourceAsset: asset,
            videoDuration: CMTime(seconds: 20, preferredTimescale: 1),
            to: outputURL
        )

        #expect(result != nil, "Stitching should produce output")
        let outputAsset = AVURLAsset(url: result!)
        let duration = try await outputAsset.load(.duration)
        #expect(abs(duration.seconds - 1.0) < 0.3, "Output duration \(duration.seconds) should be ~1s")
    }

    @Test func stitchTransitionChunkPartialRange() async throws {
        guard let asset = makeTestAsset() else {
            return
        }

        let timeRange = CMTimeRange(start: CMTime(seconds: 10, preferredTimescale: 1), duration: CMTime(seconds: 2, preferredTimescale: 1))
        let from = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        let to = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 0.5))
        let renderedURL = try await renderTransitionChunk(
            asset: asset,
            timeRange: timeRange,
            from: from,
            to: to
        )

        // stitchingTimeRange is the first 1 second of the 2s rendered chunk
        var chunk = Chunk(
            id: UUID(),
            timeRange: timeRange,
            type: .transition(from: from, to: to),
            renderState: .rendered(renderedURL)
        )
        chunk.stitchingTimeRange = CMTimeRange(
            start: CMTime(seconds: 10, preferredTimescale: 1),
            duration: CMTime(seconds: 1, preferredTimescale: 1)
        )

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "transition_partial.mov")
        let result = await stitcher.stitch(
            chunks: [chunk],
            sourceAsset: asset,
            videoDuration: CMTime(seconds: 20, preferredTimescale: 1),
            to: outputURL
        )

        #expect(result != nil, "Stitching should produce output")
        let outputAsset = AVURLAsset(url: result!)
        let duration = try await outputAsset.load(.duration)
        #expect(abs(duration.seconds - 1.0) < 0.3, "Output duration \(duration.seconds) should be ~1s (first half of rendered chunk)")
    }

    // MARK: - Mixed Chunk Types

    @Test func stitchMixedChunkTypes() async throws {
        guard let asset = makeTestAsset() else {
            return
        }

        let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        let from = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        let to = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 0.5))

        // noOverlay: 0-2s
        var noOverlayChunk = Chunk(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 1)),
            type: .noOverlay
        )
        noOverlayChunk.stitchingTimeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 1))

        // constant: 2-7s
        let constTimeRange = CMTimeRange(start: CMTime(seconds: 2, preferredTimescale: 1), duration: CMTime(seconds: 5, preferredTimescale: 1))
        let renderedURL = try await renderConstantChunk(
            asset: asset,
            timeRange: constTimeRange,
            image: image
        )
        var constChunk = Chunk(
            id: UUID(),
            timeRange: constTimeRange,
            type: .constant(image),
            renderState: .rendered(renderedURL)
        )
        constChunk.stitchingTimeRange = constTimeRange

        // transition: 7-8s
        let transTimeRange = CMTimeRange(start: CMTime(seconds: 7, preferredTimescale: 1), duration: CMTime(seconds: 1, preferredTimescale: 1))
        let renderedTransURL = try await renderTransitionChunk(
            asset: asset,
            timeRange: transTimeRange,
            from: from,
            to: to
        )
        var transChunk = Chunk(
            id: UUID(),
            timeRange: transTimeRange,
            type: .transition(from: from, to: to),
            renderState: .rendered(renderedTransURL)
        )
        transChunk.stitchingTimeRange = transTimeRange

        let chunks = [noOverlayChunk, constChunk, transChunk]
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "mixed.mov")
        let result = await stitcher.stitch(
            chunks: chunks,
            sourceAsset: asset,
            videoDuration: CMTime(seconds: 20, preferredTimescale: 1),
            to: outputURL
        )

        #expect(result != nil, "Stitching should produce output")
        let outputAsset = AVURLAsset(url: result!)
        let duration = try await outputAsset.load(.duration)
        // Expected: 2s (noOverlay) + 5s (constant) + 1s (transition) = 8s
        #expect(abs(duration.seconds - 8.0) < 0.5, "Output duration \(duration.seconds) should be ~8s")
    }

    // MARK: - Output Validity

    @Test func stitchOutputHasVideoAndAudio() async throws {
        guard let asset = makeTestAsset() else {
            return
        }

        let timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 1))
        var chunk = Chunk(
            timeRange: timeRange,
            type: .noOverlay
        )
        chunk.stitchingTimeRange = timeRange

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "tracks.mov")
        let result = await stitcher.stitch(
            chunks: [chunk],
            sourceAsset: asset,
            videoDuration: CMTime(seconds: 10, preferredTimescale: 1),
            to: outputURL
        )

        #expect(result != nil)
        let outputAsset = AVURLAsset(url: result!)
        let tracks = try await outputAsset.load(.tracks)
        let videoTracks = tracks.filter { $0.mediaType == .video }
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        #expect(videoTracks.count > 0, "Output should have a video track")
        #expect(audioTracks.count > 0, "Output should have an audio track")
    }

    @Test func stitchOutputDurationMatchesChunks() async throws {
        guard let asset = makeTestAsset() else {
            return
        }

        // Create two noOverlay chunks: 0-3s and 5-8s
        var chunk1 = Chunk(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 1)),
            type: .noOverlay
        )
        chunk1.stitchingTimeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 1))

        var chunk2 = Chunk(
            timeRange: CMTimeRange(start: CMTime(seconds: 5, preferredTimescale: 1), duration: CMTime(seconds: 3, preferredTimescale: 1)),
            type: .noOverlay
        )
        chunk2.stitchingTimeRange = CMTimeRange(start: CMTime(seconds: 5, preferredTimescale: 1), duration: CMTime(seconds: 3, preferredTimescale: 1))

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "duration.mov")
        let result = await stitcher.stitch(
            chunks: [chunk1, chunk2],
            sourceAsset: asset,
            videoDuration: CMTime(seconds: 10, preferredTimescale: 1),
            to: outputURL
        )

        #expect(result != nil)
        let outputAsset = AVURLAsset(url: result!)
        let duration = try await outputAsset.load(.duration)
        // Expected: 3s + 3s = 6s
        #expect(abs(duration.seconds - 6.0) < 0.3, "Output duration \(duration.seconds) should be ~6s")
    }
}
