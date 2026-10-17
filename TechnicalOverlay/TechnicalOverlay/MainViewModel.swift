//
//  MainViewModel.swift
//  TechnicalOverlay
//
//  The main screen's state: the loaded video, the document being edited, and the two background jobs
//  that turn them into a scored video.
//

import AVFoundation
import Foundation
import Observation
import VideoProcessor

/// What `MainView` holds: the player, the scoring document, and the pipeline and export jobs that
/// work from them.
///
/// The work itself lives in `AssetSession` (file access and video metadata), `RenderPipeline` (the
/// preview and the chunk queue) and `ExportCoordinator` (stitch and write); this type owns the
/// document, keeps them pointed at the same file, and is what the views observe.
@Observable
final class MainViewModel {

    var player: AVPlayer?
    var scoring: OverlayData

    /// The loaded video. Setting it releases the previous file's access, drops the render pipeline's
    /// plan and regenerates the slides from the new file.
    var assetUrl: URL? {
        didSet {
            load()
        }
    }

    let session = AssetSession()
    let pipeline: RenderPipeline
    let export: ExportCoordinator

    init(player: AVPlayer? = nil, assetUrl: URL? = nil, scoring: OverlayData = OverlayData()) {
        let pipeline = RenderPipeline()
        self.player = player
        self.scoring = scoring
        self.pipeline = pipeline
        self.export = ExportCoordinator(pipeline: pipeline)
        // The look is a device preference, so it is applied after the saved document state.
        scoring.load()
        scoring.showsElementBox = OverlayPreferences.showsElementBox
        // Assigned without observers firing (this is the initializer): the first pass is
        // `MainView.onAppear`'s `generateSlides()`.
        self.assetUrl = assetUrl
    }

    deinit {
        assetUrl = nil
    }

    var saveVideoDisabled: Bool {
        player == nil
    }

    var outputFilename: String {
        if let assetUrl {
            let baseName = assetUrl.deletingPathExtension().lastPathComponent
            return "\(baseName) Scored.mov"
        } else {
            return "Scored.mov"
        }
    }

    /// Adopts the file `assetUrl` now names, or clears the preview when there is none.
    private func load() {
        session.adopt(assetUrl)
        pipeline.reset()

        guard assetUrl != nil else {
            player = nil
            return
        }
        generateSlides()
    }

    /// Rebuilds the preview and re-plans the export for the current document.
    func generateSlides() {
        Task {
            guard let assetUrl else {
                return
            }
            let asset = AVURLAsset(url: assetUrl)
            guard let size = await session.size(of: asset) else {
                print("Couldn't determine video size")
                return
            }

            let slides = scoring.makeSlides(size: size)
            let playerItem = await pipeline.makePreviewItem(asset: asset, slides: slides)
            if let player {
                let currentTime = player.currentTime()
                player.replaceCurrentItem(with: playerItem)
                await player.seek(to: currentTime)
            } else {
                player = AVPlayer(playerItem: playerItem)
            }

            await pipeline.enqueue(slides: slides, asset: asset, videoURL: assetUrl)
        }
    }

    /// Regenerates the slides after an overlay configuration change. The new slides carry a
    /// different `TechnicalViewModel`, so the preview shows the new look and the chunk queue's
    /// diff re-renders the chunks whose content changed.
    func setShowsElementBox(_ showsElementBox: Bool) {
        guard scoring.showsElementBox != showsElementBox else {
            return
        }
        scoring.showsElementBox = showsElementBox
        OverlayPreferences.showsElementBox = showsElementBox
        generateSlides()
    }

    /// Resets the scoring data to an empty document. The existing `OverlayData` instance is
    /// updated in place, so every view already holding it sees the reset; the emptied state is
    /// saved, and the slides are regenerated so the preview and the chunk queue drop the
    /// overlays.
    func clearSlides() {
        scoring.update(from: OverlayData())
        scoring.clearCache()
        scoring.save()
        generateSlides()
    }

    /// Renders/stitches the scored video and writes it straight to `destinationURL`.
    func exportScoredVideo(to destinationURL: URL) async {
        await export.exportScoredVideo(videoURL: assetUrl, to: destinationURL)
    }
}
