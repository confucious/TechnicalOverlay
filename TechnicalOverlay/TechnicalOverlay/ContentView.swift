//
//  ContentView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 9/21/25.
//

import SwiftUI
import AVFoundation
import LayoutEngine
import VideoProcessor

struct ContentView: View {
    var body: some View {
        ScrollView {
            VStack {
                Image(uiImage: overlays[0]).border(.black)
                Image(uiImage: overlays[1]).border(.black)
                Image(uiImage: overlays[2]).border(.black)
                Image(uiImage: overlays[3]).border(.black)
                Image(uiImage: overlays[4]).border(.black)
                Image(uiImage: overlays[5]).border(.black)
                Image(uiImage: overlays[6]).border(.black)
                Image(uiImage: overlays[7]).border(.black)
            }
        }
    }
}

let slides: [Slide] = [
    Slide(
        image: CIImage(image: overlays[0])!,
        startTime: CMTime(seconds: 1000, preferredTimescale: 1000),
        endTime: nil
    ),
    Slide(
        image: CIImage(image: overlays[1])!,
        startTime: CMTime(seconds: 2000, preferredTimescale: 1000),
        endTime: nil
    ),
    Slide(
        image: CIImage(image: overlays[2])!,
        startTime: CMTime(seconds: 3000, preferredTimescale: 1000),
        endTime: nil
    ),
    Slide(
        image: CIImage(image: overlays[3])!,
        startTime: CMTime(seconds: 4000, preferredTimescale: 1000),
        endTime: nil
    ),
    Slide(
        image: CIImage(image: overlays[4])!,
        startTime: CMTime(seconds: 5000, preferredTimescale: 1000),
        endTime: nil
    ),
    Slide(
        image: CIImage(image: overlays[5])!,
        startTime: CMTime(seconds: 6000, preferredTimescale: 1000),
        endTime: nil
    ),
    Slide(
        image: CIImage(image: overlays[6])!,
        startTime: CMTime(seconds: 7000, preferredTimescale: 1000),
        endTime: nil
    ),
    Slide(
        image: CIImage(image: overlays[7])!,
        startTime: CMTime(seconds: 8000, preferredTimescale: 1000),
        endTime: nil
    ),
]

let overlays = elements.map {
    VideoOverlay(mode: .technicalPane($0))
        .render(size: CGSize(width: 1280, height: 720))
}

let elements: [TechnicalViewModel] = [
    TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "2 Lutz + 2 Toeloop",
        baseValue: "3.40",
        goeValue: "0.11",
        totalValue: "3.51",
        boxModes: [.positive, .unscored, .unscored, .unscored, .unscored, .unscored, .unscored, .unscored]
    ),
    TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "2 Axel + 1 Axel + 2 Toeloop + SEQ",
        baseValue: "5.70 + 1",
        goeValue: "0.17",
        totalValue: "10.38",
        boxModes: [.positive, .positive, .unscored, .unscored, .unscored, .unscored, .unscored, .unscored]
    ),
    TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "Flying Sit Spin 4",
        baseValue: "3.00",
        goeValue: "0.45",
        totalValue: "13.83",
        boxModes: [.positive, .positive, .positive, .unscored, .unscored, .unscored, .unscored, .unscored]
    ),
    TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "2 Axel",
        baseValue: "2.90 + 1",
        goeValue: "-1.19",
        totalValue: "16.54",
        boxModes: [.positive, .positive, .positive, .negative, .unscored, .unscored, .unscored, .unscored]
    ),
    TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "2 Lutz",
        baseValue: "2.31",
        goeValue: "-0.11",
        totalValue: "18.74",
        boxModes: [.positive, .positive, .positive, .negative, .negative, .unscored, .unscored, .unscored]
    ),
    TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "Step Sequence 1",
        baseValue: "1.80",
        goeValue: "0.18",
        totalValue: "20.72",
        boxModes: [.positive, .positive, .positive, .negative, .negative, .positive, .unscored, .unscored]
    ),
    TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "2 Flip",
        baseValue: "1.98",
        goeValue: "0.14",
        totalValue: "22.84",
        boxModes: [.positive, .positive, .positive, .negative, .negative, .positive, .positive, .unscored]
    ),
    TechnicalViewModel(
        skaterName: "S.HSU",
        elementName: "Ch Combination Spin 4",
        baseValue: "3.50",
        goeValue: "0.26",
        totalValue: "26.60",
        boxModes: [.positive, .positive, .positive, .negative, .negative, .positive, .positive, .positive]
    )
]

struct Overlay: UIViewRepresentable {

    typealias UIViewType = VideoOverlay

    func makeUIView(context: Context) -> LayoutEngine.VideoOverlay {
        let view = VideoOverlay(mode: .none)
        view.mode = .technicalPane(elements[0])
        return view
    }

    func updateUIView(_ uiView: LayoutEngine.VideoOverlay, context: Context) {
    }
}

struct TechnicalPaneView: UIViewRepresentable {

    typealias UIViewType = IsuTechnicalPaneView
    
    func makeUIView(context: Context) -> IsuTechnicalPaneView {
        let view = IsuTechnicalPaneView()
        view.update(from: elements[0])
        return view
    }
    
    func updateUIView(_ uiView: IsuTechnicalPaneView, context: Context) {
        // Updates the state of the specified view with new information from SwiftUI.
    }

}

#Preview {
    ContentView()
}
