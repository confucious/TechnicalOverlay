//
//  MainViewModel.swift
//  TechnicalOverlay
//
//  The main screen's state: the loaded video, the document being edited, and the two background jobs
//  that turn them into a scored video.
//

import AVFoundation
import Foundation
import LayoutEngine
import Observation
import VideoProcessor
import os

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
    /// Renders the overlay images a plan needs, keeping them for reuse.
    let slideFactory = SlideFactory()

    /// Counts `generateSlides()` passes; see the method for what it guards.
    private var generation = 0

    init(player: AVPlayer? = nil, assetUrl: URL? = nil, scoring: OverlayData = OverlayData()) {
        let pipeline = RenderPipeline()
        self.player = player
        self.scoring = scoring
        self.pipeline = pipeline
        self.export = ExportCoordinator(pipeline: pipeline)
        // The look is a device preference, so it is applied after the saved document state.
        scoring.load()
        scoring.showsElementBox = OverlayPreferences.showsElementBox
        scoring.technicalPaneStyle = OverlayPreferences.technicalPaneStyle
        // Assigned without observers firing (this is the initializer): the first pass is
        // `MainView.onAppear`'s `generateSlides()`.
        self.assetUrl = assetUrl
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
    ///
    /// Every call takes a new pass number, and each await is followed by a check that the pass is
    /// still the latest: `assetUrl`, a timestamp edit and the overlay-look toggle can all start one
    /// while an earlier pass is suspended, and a superseded pass must not install its preview or
    /// enqueue its plan over the newer one's.
    func generateSlides() {
        generation += 1
        let pass = generation

        Task {
            guard let assetUrl else {
                return
            }
            let asset = AVURLAsset(url: assetUrl)
            guard let size = await session.size(of: asset) else {
                Log.media.error("Couldn't determine video size")
                return
            }
            guard pass == generation else { return }

            let slides = slideFactory.slides(from: scoring.slidePlan(), size: size)
            let playerItem = await pipeline.makePreviewItem(asset: asset, slides: slides)
            guard pass == generation else { return }

            if let player {
                let currentTime = player.currentTime()
                player.replaceCurrentItem(with: playerItem)
                await player.seek(to: currentTime)
                guard pass == generation else { return }
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

    /// Regenerates the slides after the pane style changes. The style is part of the mode, so this
    /// takes the same path as the element-box toggle: new slides for the preview, and the chunk
    /// queue re-renders the chunks whose content changed.
    func setTechnicalPaneStyle(_ style: TechnicalPaneStyle) {
        guard scoring.technicalPaneStyle != style else {
            return
        }
        scoring.technicalPaneStyle = style
        OverlayPreferences.technicalPaneStyle = style
        generateSlides()
    }

    /// Resets the scoring data to an empty document. The existing `OverlayData` instance is
    /// updated in place, so every view already holding it sees the reset; the emptied state is
    /// saved, and the slides are regenerated so the preview and the chunk queue drop the
    /// overlays — an empty plan also drops every cached image.
    func clearSlides() {
        scoring.update(from: OverlayData())
        scoring.save()
        generateSlides()
    }

    /// Renders/stitches the scored video and writes it straight to `destinationURL`.
    func exportScoredVideo(to destinationURL: URL) async {
        await export.exportScoredVideo(videoURL: assetUrl, to: destinationURL)
    }
}
