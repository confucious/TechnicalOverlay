//
//  ExportCoordinator.swift
//  TechnicalOverlay
//
//  The "Save Video" job: wait for the chunks, stitch them, write the file.
//

import AVFoundation
import Foundation
import Observation
import VideoProcessor

/// Turns the render pipeline's chunks into the file the user asked for, and reports where it got to.
@Observable
final class ExportCoordinator {

    /// Where an export is. `.failed` is kept separate from `.idle` so a failure can't be mistaken for
    /// "nothing happened".
    enum Phase: Sendable, Equatable {
        case idle
        case rendering
        case stitching
        case done
        /// Export stopped short, with something to show the user.
        case failed(String)
    }

    var phase: Phase = .idle
    var stitchingProgress: Progress?

    private let pipeline: RenderPipeline

    init(pipeline: RenderPipeline) {
        self.pipeline = pipeline
    }

    /// Renders/stitches the scored video and writes it straight to `destinationURL`.
    ///
    /// The destination is chosen *before* any work happens (see the save panel in `MainView`), so
    /// nothing has to be copied out of a temp file afterwards — the passthrough export writes where
    /// the user asked for it.
    ///
    /// `videoURL` is `nil` only while `MainViewModel.generateSlides()` is still building the queue.
    func exportScoredVideo(videoURL: URL?, to destinationURL: URL) async {
        guard let videoURL, let queue = pipeline.queue else {
            fail("The video is still being prepared — try again in a moment.", at: destinationURL)
            return
        }

        let isScoped = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if isScoped { destinationURL.stopAccessingSecurityScopedResource() }
        }

        // The save panel has already written our zero-byte placeholder at the destination, and
        // AVAssetExportSession refuses to write over an existing file ("Cannot Save — the requested
        // file name is already in use"), so clear it first.
        try? FileManager.default.removeItem(at: destinationURL)

        phase = .rendering
        stitchingProgress = nil

        let asset = AVURLAsset(url: videoURL)
        guard let videoDuration = try? await asset.load(.duration) else {
            fail("Couldn't read the video's duration.", at: destinationURL)
            return
        }

        await pipeline.waitForCompletion()

        phase = .stitching
        let exportSession: VideoComposer.ExportSession
        do {
            guard let session = try await DefaultStitcher().stitch(
                chunks: await pipeline.validChunks(),
                sourceAsset: asset,
                videoDuration: videoDuration,
                to: destinationURL
            ) else {
                fail("The rendered chunks don't cover the whole video, so there was nothing to save.", at: destinationURL)
                return
            }
            exportSession = session
        } catch {
            fail("Stitching failed: \(error.localizedDescription)", at: destinationURL)
            return
        }

        monitorStitching(of: exportSession)

        do {
            try await exportSession.performExport()
            phase = .done
        } catch {
            fail("Export failed: \(error.localizedDescription)", at: destinationURL)
        }
    }

    /// Reports the passthrough export's progress to the sheet until the export finishes.
    private func monitorStitching(of exportSession: VideoComposer.ExportSession) {
        Task {
            for await stitchState in exportSession.exportState {
                switch stitchState {
                case .pending: print("pending stitch export")
                case .waiting: print("waiting stitch export")
                case let .exporting(progress: progress):
                    print("stitch exporting \(progress)")
                    stitchingProgress = progress
                @unknown default:
                    print("unknown stitch state")
                }
            }
        }
    }

    /// Leaves nothing half-written at the destination and reports what went wrong.
    private func fail(_ message: String, at destinationURL: URL) {
        try? FileManager.default.removeItem(at: destinationURL)
        print("Export failed: \(message)")
        phase = .failed(message)
    }
}
