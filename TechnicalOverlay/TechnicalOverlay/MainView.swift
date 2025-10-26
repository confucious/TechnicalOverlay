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
        }
        
        var player: AVPlayer?
        var assetUrl: URL? {
            didSet {
                guard assetUrl != nil else {
                    player = nil
                    return
                }
                generateSlides()
            }
        }
        var scoring: OverlayData = OverlayData()

        func generateSlides() {
            Task { [self] in
                guard let url = assetUrl else {
                    return
                }
                let asset = AVURLAsset(url: url)
                guard let videoTrack = (try? await asset.loadTracks(withMediaType: .video))?.first else {
                    print("Couldn't find video track")
                    return
                }
                guard let naturalSize = try? await videoTrack.load(.naturalSize),
                      let transform = try? await videoTrack.load(.preferredTransform)
                else {
                    print("Couldn't load size or transform for video track")
                    return
                }
                
                let size = naturalSize.applying(transform)
                
                let videoComposer = VideoComposer(asset: asset, slides: scoring.makeSlides(size: size))
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
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .editSlides:
                    ScoringListView(state: state.scoring)
                }
            }
        }
    }
}

#Preview {
    MainView()
}
