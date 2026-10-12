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

    // MARK: - noOverlay ↔ overlay transition

    /// Regression: a `.transition(from: nil, to: image)` chunk — the chunk that carries a slide
    /// fading in from noOverlay — used to render as bare source, so the slide popped into view at
    /// the next constant chunk instead of fading in. The chunk returns a bare source frame when
    /// either side of the transition is nil; both sides must be treated as "no overlay", with the
    /// dissolve running into/out of the plain source frame.
    @Test func transitionFromNoOverlayFadesTheOverlayIn() async throws {
        guard let asset = makeTestAsset() else {
            return
        }

        // 1s chunk with the standard 0.75s dissolve, so its final frame holds the overlay.
        let timeRange = CMTimeRange(
            start: CMTime(seconds: 2, preferredTimescale: 600),
            duration: CMTime(seconds: 1, preferredTimescale: 600)
        )
        var chunk = Chunk(timeRange: timeRange, type: .transition(from: nil, to: solidRed))
        chunk.stitchingTimeRange = timeRange

        let renderer = DefaultChunkRenderer(
            sourceAsset: asset,
            outputDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let renderedURL = try #require(await renderer.render(chunk))

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: renderedURL))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let first = try await generator.image(
            at: CMTime(seconds: 0.05, preferredTimescale: 600)
        ).image
        let last = try await generator.image(
            at: CMTime(seconds: 0.9, preferredTimescale: 600)
        ).image

        let firstPixel = try centrePixel(of: first)
        let lastPixel = try centrePixel(of: last)

        // End of the chunk: past the dissolve, the opaque overlay is held.
        #expect(lastPixel.isOpaqueRed, "overlay should be held at the end of the chunk, got \(lastPixel)")
        // Start of the chunk: still the plain source frame — i.e. it faded rather than appeared.
        #expect(!firstPixel.isOpaqueRed, "chunk should start on the source frame, got \(firstPixel)")
    }
}

// MARK: - Frame sampling helpers

private let solidRed = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
    .cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))

private struct Pixel: CustomStringConvertible {
    let red: Int
    let green: Int
    let blue: Int

    /// The overlay colour above, fully applied.
    var isOpaqueRed: Bool { red > 200 && green < 60 && blue < 60 }

    var description: String { "rgb(\(red),\(green),\(blue))" }
}

/// Reads the centre pixel of a frame — the overlay covers the middle of the frame, and sampling
/// one pixel avoids averaging the overlay with the surrounding source.
private func centrePixel(of image: CGImage) throws -> Pixel {
    let centre = CGRect(x: image.width / 2, y: image.height / 2, width: 1, height: 1)
    let cropped = try #require(image.cropping(to: centre))

    var bytes = [UInt8](repeating: 0, count: 4)
    let context = try #require(
        CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))

    return Pixel(red: Int(bytes[0]), green: Int(bytes[1]), blue: Int(bytes[2]))
}
