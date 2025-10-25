//
//  MainView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/19/25.
//

import SwiftUI
import AVFoundation
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
                let asset = AVURLAsset(url: url)
                let playerItem = AVPlayerItem(asset: asset)
                player = AVPlayer(playerItem: playerItem)

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
                HStack {
                    Button("Load Video") {
                        fileSelectShowing.toggle()
                    }
                    .fileImporter(
                        isPresented: $fileSelectShowing,
                        allowedContentTypes: [.video]) { result in
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
                if !state.scoring.isEmpty {
                    ScrollView {
                        TimeSettingsView(state: state.scoring, getTime: { 0.0 })
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
            .task {
                for await _ in state.scoring.changeStream {
                    guard let url = state.assetUrl else {
                        continue
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
                    state.player = AVPlayer(playerItem: playerItem)
                }
            }

        }
    }
}

#Preview {
    MainView()
}
