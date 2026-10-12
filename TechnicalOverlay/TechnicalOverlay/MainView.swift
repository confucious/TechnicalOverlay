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
    enum ExportPhase: Sendable {
        case idle
        case rendering
        case stitching
        case done
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
                        sourceAsset: asset,
                        outputDirectory: FileManager.default.temporaryDirectory
                    ),
                    transitionTime: CMTime(seconds: Metrics.transitionTime, preferredTimescale: 1000)
                )
                await queue
                    .setProgressCallback { progress in
                    Task { @MainActor in
                        self.renderingProgress = progress
                    }
                }
                self.chunkQueue = queue

                // Pre-enqueue slides so the queue is ready for "Save Video"
                let videoDuration = try? await asset.load(.duration)
                if let videoDuration {
                    await queue
                        .enqueue(slides: slides, videoDuration: videoDuration)
                }
            }
        }    }

    enum Destination {
        case editSlides
    }

    @State private var state = ViewModel()
    @State private var fileSelectShowing = false
    @State private var shareUrl: URL? = nil
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
                        Task {
                            guard let queue = state.chunkQueue,
                                  let videoComposer = state.videoComposer,
                                  let assetUrl = state.assetUrl else {
                                print("queue, videoComposer or assetUrl not set")
                                return
                            }

                            state.exportPhase = .rendering
                            state.renderingProgress = nil
                            state.stitchingProgress = nil

                            let asset = AVURLAsset(url: assetUrl)
                            guard let videoDuration = try? await asset.load(.duration) else {
                                print("Failed to load video duration")
                                state.exportPhase = .idle
                                return
                            }

//                            // Enqueue slides for incremental rendering
//                            queue.enqueue(slides: videoComposer.slides, videoDuration: videoDuration)
//
                            // Wait for all chunks to finish rendering
                            await queue.waitForCompletion()

                            // All chunks rendered — now stitch
                            state.exportPhase = .stitching
                            let filename = UUID().uuidString + ".mov"
                            let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

                            let stitcher = DefaultStitcher()
                            guard let exportSession = try await stitcher.stitch(
                                chunks: queue.validChunks(),
                                sourceAsset: asset,
                                videoDuration: videoDuration,
                                to: tempFileURL
                            ) else {
                                print("Stitching failed — last chunk didn't reach end of video")
                                state.exportPhase = .idle
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
                                        state.stitchingProgress = progress
                                    @unknown default:
                                        print("unknown stitch state")
                                    }
                                }
                            }
                            await exportSession.performExport()

                            shareUrl = tempFileURL
                            saveFileShowing = true
                            state.exportPhase = .done
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.saveVideoDisabled)
                    .fileExporter(
                        isPresented: $saveFileShowing,
                        document: MovieDocument(tempUrl: self.shareUrl),
                        contentType: .quickTimeMovie,
                        defaultFilename: state.outputFilename
                    ) { result in
                        print("Save: \(result)")
                    }
                    .sheet(isPresented: showProgressModal, content: {
                        VStack {
                            if let progress = state.renderingProgress, state.exportPhase == .rendering {
                                ProgressView(
                                    "Rendering overlay chunks (\(progress.completed)/\(progress.total))",
                                    value: Double(progress.completed),
                                    total: Double(max(progress.total, 1))
                                ).padding(20.0)
                            } else if let stitchProgress = state.stitchingProgress, state.exportPhase == .stitching {
                                ProgressView(
                                    "Stitching final video...",
                                    value: stitchProgress.fractionCompleted
                                ).padding(20.0)
                            } else if state.exportPhase == .done {
                                Text("Export complete")
                                Button("Close") {
                                    state.exportPhase = .idle
                                }
                            } else {
                                Text("Export error")
                                Button("Close") {
                                    state.exportPhase = .idle
                                }
                            }
                        }.interactiveDismissDisabled()
                    })

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

struct MovieDocument: FileDocument {
    enum DocError: Error {
        case tempUrlNotSet
    }
    static var readableContentTypes: [UTType] = [.movie]
    static var writableContentTypes: [UTType] = [.movie, .quickTimeMovie]

    var tempUrl: URL?
    
    init(tempUrl: URL?) {
        self.tempUrl = tempUrl
    }
    
    init(configuration: ReadConfiguration) throws {
        // Implement reading if needed
        fatalError("Reading not implemented for this example")
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let tempUrl else {
            throw DocError.tempUrlNotSet
        }
        let data = try Data(contentsOf: tempUrl)
        return FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    MainView()
}
