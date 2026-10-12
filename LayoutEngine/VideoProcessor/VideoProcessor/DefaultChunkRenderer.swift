//
//  DefaultChunkRenderer.swift
//  VideoProcessor
//
// Renders individual chunks by exporting time-limited segments of the
// source video with overlay composited via AVVideoComposition.

import AVFoundation
import CoreImage
import Foundation

// MARK: - Settings

/// Configuration for chunk export encoding.
public struct VideoSettings: Sendable {
    let presetName: String
    let outputFileType: AVFileType

    public static let `default` = VideoSettings(
        presetName: AVAssetExportPresetHighestQuality,
        outputFileType: .mov
    )
}

// MARK: - Errors

enum ChunkRendererError: Error, LocalizedError {
    case cannotCreateExportSession
    case exportFailed
    case compositionFailed
    case assetCompatibilityFailed

    var errorDescription: String? {
        switch self {
        case .cannotCreateExportSession:
            return "Cannot create AVAssetExportSession"
        case .exportFailed:
            return "Export failed"
        case .compositionFailed:
            return "Video composition setup failed"
        case .assetCompatibilityFailed:
            return "Preset is not compatible with asset and output type"
        }
    }
}

// MARK: - Renderer

/// Renders individual chunks by exporting time-limited segments of the
/// source video with overlay composited via `AVVideoComposition`.
///
/// `ChunkQueue` (an actor) calls `render(chunk:)` sequentially, so no
/// additional queue or synchronization is needed.
public final class DefaultChunkRenderer: ChunkRendererProtocol {
    private let sourceAsset: AVAsset
    private let outputDirectory: URL
    private let settings: VideoSettings

    public init(
        sourceAsset: AVAsset,
        outputDirectory: URL,
        settings: VideoSettings = .default
    ) {
        self.sourceAsset = sourceAsset
        self.outputDirectory = outputDirectory
        self.settings = settings
    }

    public func render(_ chunk: Chunk) async -> URL? {
        // 1. Staleness check
        guard let stitchingRange = chunk.stitchingTimeRange else {
            Trace.log(.renderer, "skip \(chunk.traceID) \(chunk.type.traceName): not in the current plan (stale)")
            return nil
        }

        // 2. noOverlay check — dequeueNextRenderable() already filters these out,
        //    but the guard is defensive for callers that bypass the queue
        guard chunk.type != .noOverlay else {
            Trace.log(.renderer, "skip \(chunk.traceID): noOverlay has nothing to render")
            return nil
        }

        // 3. Build output URL
        let outputURL = outputDirectory.appendingPathComponent(
            "chunk_\(chunk.id.uuidString).mov"
        )

        // 4. Render on current actor context ( ChunkQueue serializes calls )
        Trace.log(.renderer, "\(chunk.traceLabel) stitch=\(stitchingRange.traceDescription) → \(outputURL.lastPathComponent)")
        return await renderChunk(chunk, stitchingRange: stitchingRange, to: outputURL)
    }

    private func renderChunk(
        _ chunk: Chunk,
        stitchingRange: CMTimeRange,
        to outputURL: URL
    ) async -> URL? {
        // 1. Check export compatibility
        guard await AVAssetExportSession.compatibility(
            ofExportPreset: settings.presetName,
            with: sourceAsset,
            outputFileType: settings.outputFileType
        ) else {
            Trace.log(.renderer, "\(chunk.traceID) preset \(settings.presetName) is not compatible with the source asset")
            return nil
        }

        // 2. Create export session
        guard let exportSession = AVAssetExportSession(
            asset: sourceAsset,
            presetName: settings.presetName
        ) else {
            Trace.log(.renderer, "\(chunk.traceID) could not create an export session")
            return nil
        }

        // 3. Apply composition based on chunk type (direct CIImage, no slide conversion)
        do {
            switch chunk.type {
            case .constant(let ciImage):
                exportSession.videoComposition = try await VideoComposer(
                    asset: sourceAsset,
                    slides: []
                ).setupComposition(overlay: ciImage)
                Trace.log(.renderer, "\(chunk.traceID) composition: constant overlay \(Optional(ciImage).traceName)")

            case .transition(let from, let to):
                exportSession.videoComposition = try await VideoComposer(
                    asset: sourceAsset,
                    slides: []
                ).setupComposition(from: from, to: to, transitionStart: stitchingRange.start)
                Trace.log(.renderer, "\(chunk.traceID) composition: transition \(from.traceName) → \(to.traceName) starting \(stitchingRange.start.traceDescription)")

            case .noOverlay:
                // Should not reach here due to guard in render()
                Trace.log(.renderer, "\(chunk.traceID) unexpected noOverlay chunk, skipping")
                return nil
            }
        } catch {
            Trace.log(.renderer, "\(chunk.traceID) composition failed: \(error)")
            return nil
        }

        // 4. Limit export to chunk's time range
        exportSession.timeRange = stitchingRange

        // 5. Export to file
        let exportTimer = TraceTimer()
        do {
            try await exportSession.export(to: outputURL, as: settings.outputFileType)
        } catch {
            Trace.log(.renderer, "\(chunk.traceID) export failed after \(exportTimer.elapsedDescription): \(error)")
            return nil
        }

        Trace.log(.renderer, "\(chunk.traceID) exported in \(exportTimer.elapsedDescription)\(traceFileSize(at: outputURL))")
        return outputURL
    }
}
