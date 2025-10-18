//
//  ContentView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 9/21/25.
//

import SwiftUI
import AVFoundation
import AVKit
import LayoutEngine
import VideoProcessor

struct ContentView: View {
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
//        Overlay()
        VStack {
            if let player {
                VideoPlayer(player: player)
//                    .frame(width: 1280, height: 720, alignment: .center)

                Button {
                    isPlaying ? player.pause() : player.play()
                    isPlaying.toggle()
                    player.seek(to: .zero)
                } label: {
                    Image(systemName: isPlaying ? "stop" : "play")
                        .padding()
                }
            }
        }
        .task {
            // Use the task modifier to defer creating the player to ensure
            // SwiftUI creates it only once when it first presents the view.
            let url = Bundle.main.url(forResource: "Boston Open 2025", withExtension: "mov")
            let asset = AVURLAsset(url: url!)
            let videoComposer = VideoComposer(asset: asset, slides: slides)
            let playerItem = AVPlayerItem(asset: asset)
            do {
                playerItem.videoComposition = try await videoComposer
                    .setupComposition()
            } catch {
                print("Video composer failed \(error)")
            }
            player = AVPlayer(playerItem: playerItem)
        }

    }
}

let slides: [Slide] = [
    Slide(
        image: CIImage(image: overlays[0])!,
        startTime: CMTime(seconds: 8.5, preferredTimescale: 1000)
    ),
    Slide(
        image: CIImage(image: overlays[1])!,
        startTime: CMTime(seconds: 13.5, preferredTimescale: 1000)
    ),
    Slide(
        image: CIImage(image: overlays[2])!,
        startTime: CMTime(seconds: 18.5, preferredTimescale: 1000)
    ),
    Slide(
        image: CIImage(image: overlays[3])!,
        startTime: CMTime(seconds: 50.46, preferredTimescale: 1000)
    ),
    Slide(
        image: CIImage(image: overlays[4])!,
        startTime: CMTime(seconds: 74.1, preferredTimescale: 1000)
    ),
    Slide(
        image: CIImage(image: overlays[5])!,
        startTime: CMTime(seconds: 93.8, preferredTimescale: 1000)
    ),
    Slide(
        image: CIImage(image: overlays[6])!,
        startTime: CMTime(seconds: 109, preferredTimescale: 1000)
    ),
    Slide(
        image: CIImage(image: overlays[7])!,
        startTime: CMTime(seconds: 119, preferredTimescale: 1000)
    ),
    Slide(
        image: CIImage(image: overlays[8])!,
        startTime: CMTime(seconds: 150, preferredTimescale: 1000)
    ),
    Slide(
        image: CIImage(image: overlays[9])!,
        startTime: CMTime(seconds: 161, preferredTimescale: 1000)
    ),
    Slide(
        image: CIImage(image: overlays[10])!,
        startTime: CMTime(seconds: 179, preferredTimescale: 1000)
    ),
    Slide(
        image: CIImage(image: overlays[11])!,
        startTime: CMTime(seconds: 184, preferredTimescale: 1000)
    )
]

let overlays = elements.map {
    VideoOverlay(mode: $0)
        .render(size: CGSize(width: 1920, height: 1080))
}

let elements: [VideoOverlay.Mode] = [
    .lowerThirdPane(LowerThirdViewModel(
        skaterName: "Scotty HSU",
        secondaryText: ("Coaches: Philip Deyesso, Renée Laurin-Roos", "Age: 12", "SC of Boston")
    )),
    .lowerThirdPane(LowerThirdViewModel(
        skaterName: "Scotty HSU",
        secondaryText: ("Music: The Mask of Zorro by James Horner", "", "")
    )),
    .none,
    .technicalPane(TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "2 Lutz + 2 Toeloop",
        baseValue: "3.40",
        goeValue: "0.11",
        totalValue: "3.51",
        boxModes: [.positive, .unscored, .unscored, .unscored, .unscored, .unscored, .unscored, .unscored]
    )),
    .technicalPane(TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "2 Axel + 1 Axel + 2 Toeloop + SEQ",
        baseValue: "5.70 + 1",
        goeValue: "0.17",
        totalValue: "10.38",
        boxModes: [.positive, .positive, .unscored, .unscored, .unscored, .unscored, .unscored, .unscored]
    )),
    .technicalPane(TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "Flying Sit Spin 4",
        baseValue: "3.00",
        goeValue: "0.45",
        totalValue: "13.83",
        boxModes: [.positive, .positive, .positive, .unscored, .unscored, .unscored, .unscored, .unscored]
    )),
    .technicalPane(TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "2 Axel",
        baseValue: "2.90 + 1",
        goeValue: "-1.19",
        totalValue: "16.54",
        boxModes: [.positive, .positive, .positive, .negative, .unscored, .unscored, .unscored, .unscored]
    )),
    .technicalPane(TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "2 Lutz",
        baseValue: "2.31",
        goeValue: "-0.11",
        totalValue: "18.74",
        boxModes: [.positive, .positive, .positive, .negative, .negative, .unscored, .unscored, .unscored]
    )),
    .technicalPane(TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "Step Sequence 1",
        baseValue: "1.80",
        goeValue: "0.18",
        totalValue: "20.72",
        boxModes: [.positive, .positive, .positive, .negative, .negative, .positive, .unscored, .unscored]
    )),
    .technicalPane(TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "2 Flip",
        baseValue: "1.98",
        goeValue: "0.14",
        totalValue: "22.84",
        boxModes: [.positive, .positive, .positive, .negative, .negative, .positive, .positive, .unscored]
    )),
    .technicalPane(TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "Ch Combination Spin 4",
        baseValue: "3.50",
        goeValue: "0.26",
        totalValue: "26.60",
        boxModes: [.positive, .positive, .positive, .negative, .negative, .positive, .positive, .positive]
    )),
    .none
]

struct Overlay: UIViewRepresentable {

    typealias UIViewType = VideoOverlay

    func makeUIView(context: Context) -> LayoutEngine.VideoOverlay {
        let view = VideoOverlay(mode: .none)
        view.mode = elements[0]
        return view
    }

    func updateUIView(_ uiView: LayoutEngine.VideoOverlay, context: Context) {
    }
}

struct TechnicalPaneView: UIViewRepresentable {

    typealias UIViewType = IsuTechnicalPaneView
    
    func makeUIView(context: Context) -> IsuTechnicalPaneView {
        let view = IsuTechnicalPaneView()
//        view.update(from: elements[0])
        return view
    }
    
    func updateUIView(_ uiView: IsuTechnicalPaneView, context: Context) {
        // Updates the state of the specified view with new information from SwiftUI.
    }

}

struct LowerThirdView: UIViewRepresentable {

    typealias UIViewType = IsuLowerThirdView
    
    func makeUIView(context: Context) -> IsuLowerThirdView {
        let view = IsuLowerThirdView()
//        view.update(from: elements[0])
        return view
    }
    
    func updateUIView(_ uiView: IsuLowerThirdView, context: Context) {
        // Updates the state of the specified view with new information from SwiftUI.
    }

}

#Preview {
    ContentView()
}
