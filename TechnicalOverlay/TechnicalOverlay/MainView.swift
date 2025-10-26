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
    struct ViewModel {
        var player: AVPlayer?
        var assetUrl: URL? {
            didSet {
                guard let url = assetUrl else {
                    player = nil
                    return
                }
//                let gotAccess = url.startAccessingSecurityScopedResource()
//                guard gotAccess else {
//                    print("Couldn't get security access for movie")
//                    return
//                }
                let asset = AVURLAsset(url: url)
                let playerItem = AVPlayerItem(asset: asset)
                player = AVPlayer(playerItem: playerItem)
//                url.stopAccessingSecurityScopedResource()
            }
        }
        var scoring: OverlayData = OverlayData()
    }

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
                    Button("Generate Slides") {
                        generateSlides()
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
                                generateSlides()
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
    
    func generateSlides() {
        Task {
            guard let url = state.assetUrl else {
                return
            }
            let asset = AVURLAsset(url: url)
            let videoComposer = VideoComposer(asset: asset, slides: state.scoring.makeSlides(size: CGSize(width: 1920, height: 1080)))
            let playerItem = AVPlayerItem(asset: asset)
            do {
                playerItem.videoComposition = try await videoComposer
                    .setupComposition()
            } catch {
                print("Video composer failed \(error)")
            }
            guard let player = state.player else { return }
            let currentTime = player.currentTime()
            player.replaceCurrentItem(with: playerItem)
            await player.seek(to: currentTime)
        }
    }
}

#Preview {
    MainView()
}
