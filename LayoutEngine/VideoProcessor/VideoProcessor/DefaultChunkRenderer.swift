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
        guard let stitchingRange = chunk.stitchingTimeRange else { return nil }

        // 2. noOverlay check — dequeueNextRenderable() already filters these out,
        //    but the guard is defensive for callers that bypass the queue
        guard chunk.type != .noOverlay else { return nil }

        // 3. Build output URL
        let outputURL = outputDirectory.appendingPathComponent(
            "chunk_\(chunk.id.uuidString).mov"
        )

        // 4. Render on current actor context ( ChunkQueue serializes calls )
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
            print("Chunk render: asset compatibility check failed")
            return nil
        }

        // 2. Create export session
        guard let exportSession = AVAssetExportSession(
            asset: sourceAsset,
            presetName: settings.presetName
        ) else {
            print("Chunk render: cannot create export session")
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

            case .transition(let from, let to):
                exportSession.videoComposition = try await VideoComposer(
                    asset: sourceAsset,
                    slides: []
                ).setupComposition(from: from, to: to, transitionStart: stitchingRange.start)

            case .noOverlay:
                // Should not reach here due to guard in render()
                print("Chunk render: unexpected noOverlay chunk")
                return nil
            }
        } catch {
            print("Chunk render: composition failed: \(error)")
            return nil
        }

        // 4. Limit export to chunk's time range
        exportSession.timeRange = stitchingRange

        // 5. Export to file
        do {
            try await exportSession.export(to: outputURL, as: settings.outputFileType)
        } catch {
            print("Chunk render: export failed: \(error)")
            return nil
        }

        return outputURL
    }
}
