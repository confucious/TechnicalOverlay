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
            let url = Bundle.main.url(forResource: "Test", withExtension: "mov")
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

let slides: [Slide] = overlayData.makeSlides(size: CGSize(width: 1920, height: 1080))

let unsetOverlayData = OverlayData(
    skaterFullName: overlayData.skaterFullName,
    skaterAbbreviatedName: overlayData.skaterAbbreviatedName,
    introductionTexts: overlayData.introductionTexts.map {
        var item = $0
        item.displayTime = nil
        return item
    },
    elementScores: overlayData.elementScores.map {
        var item = $0
        item.displayTime = nil
        return item
    })
let overlayData = OverlayData(
    skaterFullName: "Scotty HSU",
    skaterAbbreviatedName: "S. HSU",
    introductionTexts: [
        IntroductionData(
            left: "Age 12",
            center: "Coaches: Philip Deyesso, Renée Laurin-Roos",
            right: "SC of Boston",
            displayTime: 8.5
        ),
        IntroductionData(
            left: "",
            center: "Music: The Mask of Zorro by James Horner",
            right: "",
            displayTime: 13.5
        )
    ],
    elementScores: [
        ElementData(
            name: "2 Lutz + 2 Toeloop",
            baseValue: 340,
            goeValue: 11,
            bonusValue: 0,
            displayTime: 50.46
        ),
        ElementData(
            name: "2 Axel + 1 Axel + 2 Toeloop + SEQ",
            baseValue: 570,
            goeValue: 17,
            bonusValue: 100,
            displayTime: 74.1
        ),
        ElementData(
            name: "Flying Sit Spin 4",
            baseValue: 300,
            goeValue: 45,
            bonusValue: 0,
            displayTime: 93.8
        ),
        ElementData(
            name: "2 Axel",
            baseValue: 290,
            goeValue: -119,
            bonusValue: 100,
            displayTime: 109
        ),
        ElementData(
            name: "2 Lutz",
            baseValue: 231,
            goeValue: -11,
            bonusValue: 0,
            displayTime: 119
        ),
        ElementData(
            name: "Step Sequence 1",
            baseValue: 180,
            goeValue: 18,
            bonusValue: 0,
            displayTime: 150
        ),
        ElementData(
            name: "2 Flip",
            baseValue: 198,
            goeValue: 14,
            bonusValue: 0,
            displayTime: 161
        ),
        ElementData(
            name: "Ch Combination Spin 4",
            baseValue: 350,
            goeValue: 26,
            bonusValue: 0,
            displayTime: 179
        )
    ])

//struct Overlay: UIViewRepresentable {
//
//    typealias UIViewType = VideoOverlay
//
//    func makeUIView(context: Context) -> LayoutEngine.VideoOverlay {
//        let view = VideoOverlay(mode: .none)
//        view.mode = elements[0]
//        return view
//    }
//
//    func updateUIView(_ uiView: LayoutEngine.VideoOverlay, context: Context) {
//    }
//}

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
