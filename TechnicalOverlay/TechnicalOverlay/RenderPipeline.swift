//
//  RenderPipeline.swift
//  TechnicalOverlay
//
//  The background rendering side of the app: the preview composition and the chunk queue.
//

import AVFoundation
import CoreMedia
import Foundation
import Observation
import VideoProcessor

/// Draws the preview and renders the overlays for export.
///
/// Owns the queue and the preview composer, and reports what the queue is doing so the main screen can
/// show it. It does not own the player: `makePreviewItem(asset:slides:)` hands the item back for the
/// caller to install.
@Observable
final class RenderPipeline {

    /// What the background chunk queue is doing, shown as a dot over the video.
    enum Status: Sendable, Equatable {
        /// Nothing loaded — nothing to render.
        case noVideo
        /// Work queued or rendering. **Yellow.**
        case processing
        /// Every renderable chunk is rendered and the queue is idle. **Green.**
        case idle
    }

    var status: Status = .noVideo

    /// The queue's latest report — `nil` until its first pass reports.
    var progress: ChunkQueueProgress?

    @ObservationIgnored
    private(set) var queue: ChunkQueue?

    @ObservationIgnored
    private var videoComposer: VideoComposer?

    /// Drops the plan. A new video re-plans from scratch; nothing carries over.
    func reset() {
        queue = nil
        status = .noVideo
    }

    /// Builds the preview composition for `asset` and returns the item to put in the player.
    ///
    /// A composition that fails leaves the item without one — the video still plays, unwrapped.
    func makePreviewItem(asset: AVAsset, slides: [Slide]) async -> AVPlayerItem {
        let item = AVPlayerItem(asset: asset)
        let composer = VideoComposer(asset: asset, slides: slides)
        videoComposer = composer
        do {
            item.videoComposition = try await composer.setupComposition()
        } catch {
            print("Video composer failed \(error)")
        }
        return item
    }

    /// Plans `slides` into the queue and starts rendering them in the background.
    func enqueue(slides: [Slide], asset: AVAsset, videoURL: URL) async {
        let queue = self.queue ?? ChunkQueue(
            renderer: DefaultChunkRenderer(
                // A *second* AVURLAsset over the same file, deliberately: sharing one instance with
                // the player item makes the preview and the chunk export contend for its
                // decode/compositor state, which freezes the app mid-drag. Do not re-merge them —
                // `docs/HISTORY.md` → *Playhead freeze*.
                sourceAsset: AVURLAsset(url: videoURL),
                outputDirectory: FileManager.default.temporaryDirectory
            ),
            transitionTime: CMTime(seconds: Metrics.transitionTime, preferredTimescale: 1000)
        )
        await queue.setProgressCallback { [weak self] progress in
            Task { @MainActor in
                self?.progress = progress
                self?.status = progress.isRendering ? .processing : .idle
            }
        }
        self.queue = queue
        status = .idle

        guard let videoDuration = try? await asset.load(.duration) else { return }
        await queue.enqueue(slides: slides, videoDuration: videoDuration)
    }

    /// Waits for every chunk — including one a drain already has in flight.
    func waitForCompletion() async {
        await queue?.waitForCompletion()
    }

    /// The chunks that can be stitched, in plan order.
    func validChunks() async -> [Chunk] {
        await queue?.validChunks() ?? []
    }
}
