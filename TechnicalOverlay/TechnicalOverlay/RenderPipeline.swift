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
import os

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
        /// Every renderable chunk is rendered, so the queue has nothing left to do. **Green.**
        ///
        /// Not `idle`: the queue *is* idle in this state, but the label sits next to `noVideo`, where
        /// "idle" reads as "nothing to show" — the opposite of what it means.
        case rendered
    }

    var status: Status = .noVideo

    /// The queue's latest report — `nil` until its first pass reports.
    var progress: ChunkQueueProgress?

    @ObservationIgnored
    private(set) var queue: ChunkQueue?

    /// The directory this pipeline's renderer writes into, deleted with the queue.
    @ObservationIgnored
    private var chunkDirectory: URL?

    @ObservationIgnored
    private var videoComposer: VideoComposer?

    /// Drops the plan.
    ///
    /// The old queue may still be mid-drain, so its teardown is asynchronous: the drain is cancelled,
    /// the files it rendered are deleted, and the directory goes with them. A new plan starts in a
    /// directory of its own, so the two cannot collide.
    func reset() {
        let previousQueue = queue
        let previousDirectory = chunkDirectory
        queue = nil
        chunkDirectory = nil
        status = .noVideo
        progress = nil

        guard previousQueue != nil || previousDirectory != nil else { return }

        Task {
            await previousQueue?.shutdown()
            if let previousDirectory {
                try? FileManager.default.removeItem(at: previousDirectory)
            }
        }
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
            Log.media.error("Video composer failed: \(error.localizedDescription, privacy: .public)")
        }
        return item
    }

    /// Plans `slides` into the queue and starts rendering them in the background.
    func enqueue(slides: [Slide], asset: AVAsset, videoURL: URL) async {
        let queue: ChunkQueue
        if let existing = self.queue {
            queue = existing
        } else {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("chunks/\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            chunkDirectory = directory

            queue = ChunkQueue(
                renderer: DefaultChunkRenderer(
                    // A *second* AVURLAsset over the same file, deliberately: sharing one instance with
                    // the player item makes the preview and the chunk export contend for its
                    // decode/compositor state, which freezes the app mid-drag. Do not re-merge them —
                    // `docs/HISTORY.md` → *Playhead freeze*.
                    sourceAsset: AVURLAsset(url: videoURL),
                    outputDirectory: directory
                ),
                transitionTime: CMTime(seconds: Metrics.transitionTime, preferredTimescale: 1000)
            )
        }

        // A report from a queue this pipeline has already replaced must not move the indicator: the
        // old queue can still be finishing a render after a video swap.
        let queueID = ObjectIdentifier(queue)
        await queue.setProgressCallback { [weak self] progress in
            Task { @MainActor in
                guard let self,
                      let current = self.queue,
                      ObjectIdentifier(current) == queueID
                else { return }
                self.progress = progress
                self.status = progress.isRendering ? .processing : .rendered
            }
        }
        self.queue = queue
        status = .rendered

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
