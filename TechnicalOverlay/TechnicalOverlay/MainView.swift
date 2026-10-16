//
//  MainView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/19/25.
//

import SwiftUI
import AVFoundation
import AVKit
import VideoProcessor

//enum State {
//    case waitingForVideo
//    case videoLoaded
//}

struct MainView: View {
    enum ExportPhase: Sendable, Equatable {
        case idle
        case rendering
        case stitching
        case done
        /// Export stopped short, with something to show the user (kept separate from `idle` so a
        /// failure can't be mistaken for "nothing happened").
        case failed(String)
    }

    /// State of the background chunk pipeline, shown as a dot in the button row.
    enum QueueStatus: Sendable, Equatable {
        /// Nothing loaded — nothing to render.
        case noVideo
        /// Work queued or rendering. **Yellow.**
        case processing
        /// Every renderable chunk is rendered and the queue is idle. **Green.**
        case idle
    }

    @Observable
    class ViewModel {
        internal init(player: AVPlayer? = nil, assetUrl: URL? = nil, scoring: OverlayData = OverlayData()) {
            self.player = player
            self.assetUrl = assetUrl
            self.scoring = scoring
            scoring.load()
        }

        var saveVideoDisabled: Bool {
            player == nil
        }

        var player: AVPlayer?
        var assetUrl: URL? {
            willSet {
                if let assetUrl {
                    assetUrl.stopAccessingSecurityScopedResource()
                }
                print("Invalidating cachedSize")
                cachedSize = nil
                chunkQueue = nil
                queueStatus = .noVideo
            }
            didSet {
                guard let assetUrl else {
                    player = nil
                    return
                }
                if !assetUrl.startAccessingSecurityScopedResource() {
                    print("Failed to get security scope")
                }
                generateSlides()
            }
        }
        var scoring: OverlayData

        @ObservationIgnored
        var videoComposer: VideoComposer?

        @ObservationIgnored
        var chunkQueue: ChunkQueue?

        // Progress tracking
        var renderingProgress: ChunkQueueProgress?
        var stitchingProgress: Progress?
        var exportPhase: ExportPhase = .idle

        /// What the background chunk queue is doing, for the status indicator.
        var queueStatus: QueueStatus = .noVideo

        @ObservationIgnored
        var cachedSize: CGSize?

        @ObservationIgnored
        var outputFilename: String {
            if let assetUrl {
                let baseName = assetUrl.deletingPathExtension().lastPathComponent
                return "\(baseName) Scored.mov"
            } else {
                return "Scored.mov"
            }
        }

        deinit {
            assetUrl = nil
        }

        func getSize(of asset: AVAsset) async -> CGSize? {
            if let cachedSize {
                print("Returned cached size \(cachedSize)")
                return cachedSize
            }
            guard let tracks = try? await asset.load(.tracks),
                  let videoTrack = tracks.first(where: { $0.mediaType == .video })
            else {
                print("Couldn't find video track")
                return nil
            }
            guard let naturalSize = try? await videoTrack.load(.naturalSize),
                  let transform = try? await videoTrack.load(.preferredTransform)
            else {
                print("Couldn't load size or transform for video track")
                return nil
            }
            
            let size = naturalSize.applying(transform)
            // transform could cause width or height to be negative.
            let fixedSize = CGSize(width: abs(size.width), height: abs(size.height))
            cachedSize = fixedSize
            print("Caching size \(fixedSize)")
            return fixedSize
        }

        func generateSlides() {
            Task {
                guard let url = assetUrl else {
                    return
                }
                let asset = AVURLAsset(url: url)
                guard let size = await getSize(of: asset)
                else {
                    print("Couldn't determine video size")
                    return
                }
                
                let slides = scoring.makeSlides(size: size)
                let videoComposer = VideoComposer(asset: asset, slides: slides)
                self.videoComposer = videoComposer
                let playerItem = AVPlayerItem(asset: asset)
                do {
                    playerItem.videoComposition = try await videoComposer
                        .setupComposition()
                } catch {
                    print("Video composer failed \(error)")
                }
                if let player {
                    let currentTime = player.currentTime()
                    player.replaceCurrentItem(with: playerItem)
                    await player.seek(to: currentTime)
                } else {
                    player = AVPlayer(playerItem: playerItem)
                }

                // Create chunk queue for incremental rendering pipeline
                let queue = chunkQueue ?? ChunkQueue(
                    renderer: DefaultChunkRenderer(
                        // A *second* AVURLAsset over the same file, deliberately: sharing one
                        // instance with the player item makes the preview and the chunk export
                        // contend for its decode/compositor state, which freezes the app mid-drag.
                        // Do not re-merge them — `docs/HISTORY.md` → *Playhead freeze*.
                        sourceAsset: AVURLAsset(url: url),
                        outputDirectory: FileManager.default.temporaryDirectory
                    ),
                    transitionTime: CMTime(seconds: Metrics.transitionTime, preferredTimescale: 1000)
                )
                await queue
                    .setProgressCallback { progress in
                    Task { @MainActor in
                        self.renderingProgress = progress
                        self.queueStatus = progress.isRendering ? .processing : .idle
                    }
                }
                self.chunkQueue = queue
                self.queueStatus = .idle

                // Pre-enqueue slides so the queue is ready for "Save Video"
                let videoDuration = try? await asset.load(.duration)
                if let videoDuration {
                    await queue
                        .enqueue(slides: slides, videoDuration: videoDuration)
                }
            }
        }

        /// Renders/stitches the scored video and writes it straight to `destinationURL`.
        ///
        /// The destination is chosen *before* any work happens (see the save panel in `body`), so
        /// nothing has to be copied out of a temp file afterwards — the passthrough export writes
        /// where the user asked for it.
        func exportScoredVideo(to destinationURL: URL) async {
            guard let queue = chunkQueue, let assetUrl else {
                // The button is only enabled with a video loaded, so this is usually the window
                // while generateSlides() is still building the queue.
                failExport("The video is still being prepared — try again in a moment.", at: destinationURL)
                return
            }

            let isScoped = destinationURL.startAccessingSecurityScopedResource()
            defer {
                if isScoped { destinationURL.stopAccessingSecurityScopedResource() }
            }

            // The save panel has already written our zero-byte placeholder at the destination, and
            // AVAssetExportSession refuses to write over an existing file ("Cannot Save — the
            // requested file name is already in use"), so clear it first.
            try? FileManager.default.removeItem(at: destinationURL)

            exportPhase = .rendering
            renderingProgress = nil
            stitchingProgress = nil

            let asset = AVURLAsset(url: assetUrl)
            guard let videoDuration = try? await asset.load(.duration) else {
                failExport("Couldn't read the video's duration.", at: destinationURL)
                return
            }

            // Wait for every chunk — including one a drain already has in flight.
            await queue.waitForCompletion()

            exportPhase = .stitching
            let exportSession: VideoComposer.ExportSession
            do {
                guard let session = try await DefaultStitcher().stitch(
                    chunks: queue.validChunks(),
                    sourceAsset: asset,
                    videoDuration: videoDuration,
                    to: destinationURL
                ) else {
                    failExport("The rendered chunks don't cover the whole video, so there was nothing to save.", at: destinationURL)
                    return
                }
                exportSession = session
            } catch {
                failExport("Stitching failed: \(error.localizedDescription)", at: destinationURL)
                return
            }

            // Monitor stitching progress
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

            do {
                try await exportSession.performExport()
                exportPhase = .done
            } catch {
                failExport("Export failed: \(error.localizedDescription)", at: destinationURL)
            }
        }

        /// Leaves nothing half-written at the destination and reports what went wrong.
        private func failExport(_ message: String, at destinationURL: URL) {
            try? FileManager.default.removeItem(at: destinationURL)
            print("Export failed: \(message)")
            exportPhase = .failed(message)
        }
    }

    enum Destination {
        case editSlides
    }

    @State private var state = ViewModel()
    @State private var fileSelectShowing = false
    @State private var saveFileShowing = false
    @State private var loadOverlayDataShowing = false
    @State private var saveOverlayDataShowing = false
    private var showProgressModal: Binding<Bool> {
        Binding(
            get: {
                state.exportPhase != .idle
            },
            set: {
                if !$0 {
                    state.exportPhase = .idle
                }
            }
        )
    }

    /// Dot + label for the background chunk queue.
    private var queueStatusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.queueStatus.indicatorColor)
                .frame(width: 10, height: 10)
            Text(state.queueStatus.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.queueStatus.accessibilityDescription)
    }

    var body: some View {
        NavigationStack {
            VStack {
                if let player = state.player {
                    VideoPlayer(player: player)
                }
                HStack {
                    Button("Load Video") {
                        fileSelectShowing.toggle()
                    }
                    .buttonStyle(.bordered)
                    .fileImporter(
                        isPresented: $fileSelectShowing,
                        allowedContentTypes: [.movie]) { result in
                            switch result {
                            case let .success(fileUrl):
                                state.assetUrl = fileUrl
                            case let .failure(error):
                                print(error)
                            }
                        }
                    Button("Save Video") {
                        // Ask for the destination FIRST: nothing else is presented yet, so the save
                        // panel can't collide with the progress sheet, and the export can write
                        // straight to the chosen URL — no temp file, and no copying a multi-GB
                        // video through memory in a FileWrapper afterwards.
                        saveFileShowing = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.saveVideoDisabled)
                    .fileExporter(
                        isPresented: $saveFileShowing,
                        document: SaveDestinationPlaceholder(),
                        contentType: .quickTimeMovie,
                        defaultFilename: state.outputFilename
                    ) { result in
                        switch result {
                        case let .success(destinationURL):
                            Task { await state.exportScoredVideo(to: destinationURL) }
                        case let .failure(error):
                            print("Save panel dismissed without a destination: \(error)")
                        }
                    }
                    .sheet(isPresented: showProgressModal, content: {
                        VStack {
                            switch state.exportPhase {
                            case .idle:
                                // The sheet is only up when the phase isn't idle.
                                EmptyView()

                            case .rendering:
                                if let progress = state.renderingProgress {
                                    ProgressView(
                                        "Rendering overlay chunks (\(progress.completed)/\(progress.total))",
                                        value: Double(progress.completed),
                                        total: Double(max(progress.total, 1))
                                    ).padding(20.0)
                                } else {
                                    ProgressView("Rendering overlay chunks…").padding(20.0)
                                }

                            case .stitching:
                                if let stitchProgress = state.stitchingProgress {
                                    ProgressView(
                                        "Stitching final video...",
                                        value: stitchProgress.fractionCompleted
                                    ).padding(20.0)
                                } else {
                                    // No progress tick yet — don't call that an error.
                                    ProgressView("Stitching final video...").padding(20.0)
                                }

                            case .done:
                                Text("Export complete")
                                Button("Close") {
                                    state.exportPhase = .idle
                                }

                            case let .failed(message):
                                Text(message)
                                Button("Close") {
                                    state.exportPhase = .idle
                                }
                            }
                        }.interactiveDismissDisabled()
                    })

                    // Background render state: yellow while the chunk queue has work, green once
                    // everything is rendered and the queue is idle.
                    Spacer()
                    queueStatusIndicator

                }
                if !state.scoring.isEmpty,
                   let player = state.player {
                    ScrollView {
                        TimeSettingsView(
                            state: state.scoring,
                            getTime: {
                                player.currentTime().seconds
                            },
                            timeUpdated: {
                                state.generateSlides()
                            }
                        ).padding(
                            .init(
                                top: 0.0,
                                leading: 10.0,
                                bottom: 0.0,
                                trailing: 10.0
                            )
                        )
                    }
                }
                HStack {
                    Button("Load Slides") {
                        loadOverlayDataShowing.toggle()
                    }
                    .buttonStyle(.bordered)
                    .fileImporter(
                        isPresented: $loadOverlayDataShowing,
                        allowedContentTypes: [OverlayDataDocument.fileType]) { result in
                            switch result {
                            case let .success(url):
                                do {
                                    let newData = try OverlayDataDocument.read(url: url)
                                    state.scoring.update(from: newData)
                                    state.scoring.save()
                                } catch {
                                    print("data load error: \(error)")
                                }
                            case let .failure(error):
                                print("data load error: \(error)")
                            }
                        }
                    Button("Save Slides") {
                        saveOverlayDataShowing.toggle()
                    }
                    .buttonStyle(.bordered)
                    .fileExporter(
                        isPresented: $saveOverlayDataShowing,
                        document: OverlayDataDocument(overlayDataForSave: state.scoring),
                        contentType: OverlayDataDocument.fileType,
                        defaultFilename: state.scoring.skaterFullName) { result in
                            print("overlay data save: \(result)")
                        }
                    NavigationLink("Edit Slides", value: Destination.editSlides)
                        .buttonStyle(.bordered)
                        .navigationDestination(for: Destination.self) { destination in
                            switch destination {
                            case .editSlides:
                                ScoringListView(state: state.scoring)
                            }
                        }
                }
            }
        }
        .onAppear {
            state.generateSlides()
        }
    }
}

/// A zero-byte stand-in used only to obtain a destination URL from the save panel.
///
/// SwiftUI's `fileExporter` is document-based: it writes the document you hand it to wherever the
/// user chooses and reports that URL back. Handing it an empty document lets the app ask for the
/// destination *before* rendering, then write the real exported video over it — no temp file, and
/// no reading a multi-GB video into memory just to copy it.
///
/// The export must delete that placeholder first: `AVAssetExportSession` refuses to write over an
/// existing file ("Cannot Save — the requested file name is already in use").
struct SaveDestinationPlaceholder: FileDocument {

    static var readableContentTypes: [UTType] = [.movie]
    static var writableContentTypes: [UTType] = [.movie, .quickTimeMovie]

    init() {}

    init(configuration: ReadConfiguration) throws {
        // Never opened for reading — this document exists to name a destination.
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data())
    }
}

#Preview {
    MainView()
}

// MARK: - Queue status presentation

extension MainView.QueueStatus {

    /// Yellow while the queue has work, green once it is fully rendered and idle. Grey when
    /// there's no video to render at all (nothing is "fully rendered" yet).
    var indicatorColor: Color {
        switch self {
        case .noVideo: return .gray
        case .processing: return .yellow
        case .idle: return .green
        }
    }

    var label: String {
        switch self {
        case .noVideo: return "No video"
        case .processing: return "Rendering"
        case .idle: return "Rendered"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .noVideo: return "No video loaded, nothing to render"
        case .processing: return "Rendering overlay chunks in the background"
        case .idle: return "All overlay chunks are rendered"
        }
    }
}
