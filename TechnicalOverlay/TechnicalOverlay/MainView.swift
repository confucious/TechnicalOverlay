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
    @Observable
    class ViewModel {
        internal init(player: AVPlayer? = nil, assetUrl: URL? = nil, scoring: OverlayData = OverlayData()) {
            self.player = player
            self.assetUrl = assetUrl
            self.scoring = scoring
            scoring.load()
//            self.scoring = overlayData
        }
        
        var player: AVPlayer?
        var assetUrl: URL? {
            willSet {
                if let assetUrl {
                    assetUrl.stopAccessingSecurityScopedResource()
                }
                print("Invalidating cachedSize")
                cachedSize = nil
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
            cachedSize = size
            print("Caching size \(size)")
            return size
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
                
                let videoComposer = VideoComposer(asset: asset, slides: scoring.makeSlides(size: size))
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
            }
        }    }

    enum Destination {
        case editSlides
    }

    @State private var state = ViewModel()
    @State private var fileSelectShowing = false
    @State private var shareUrl: URL? = nil
    @State private var saveFileShowing = false

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
                            guard let videoComposer = state.videoComposer
                            else {
                                return
                            }
                            let filename = UUID().uuidString + ".mov"
                            let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                            await videoComposer.export(atURL: tempFileURL)
                            shareUrl = tempFileURL
                            saveFileShowing = true
                        }
                    }
                    .fileExporter(
                        isPresented: $saveFileShowing,
                        document: MovieDocument(tempUrl: self.shareUrl),
                        contentType: .quickTimeMovie,
                        defaultFilename: state.outputFilename
                    ) { result in
                        print("Save: \(result)")
                    }
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
                        )
                    }
                }
                NavigationLink("Edit Slides", value: Destination.editSlides)
            }
            .onAppear {
                state.generateSlides()
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .editSlides:
                    ScoringListView(state: state.scoring)
                }
            }
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
