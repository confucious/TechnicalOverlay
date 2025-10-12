//
//  ContentView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 9/21/25.
//

import SwiftUI
import LayoutEngine

struct ContentView: View {
    var body: some View {
//        TechnicalPaneView()
        Overlay()
    }
}

struct Overlay: UIViewRepresentable {

    typealias UIViewType = VideoOverlay

    func makeUIView(context: Context) -> LayoutEngine.VideoOverlay {
        let view = VideoOverlay(mode: .none)
        view.mode = .technicalPane(
            TechnicalViewModel(
                skaterName: "S.HSU",
                elementName: "1 Axel",
                baseValue: "1.10",
                goeValue: "0.11",
                totalValue: "88.88",
                boxModes: [.positive, .unscored, .negative, .unscored, .unscored, .unscored, .unscored, .unscored]
            )
        )
        return view
    }

    func updateUIView(_ uiView: LayoutEngine.VideoOverlay, context: Context) {
    }
}

struct TechnicalPaneView: UIViewRepresentable {

    typealias UIViewType = IsuTechnicalPaneView
    
    func makeUIView(context: Context) -> IsuTechnicalPaneView {
        let view = IsuTechnicalPaneView()
        view
            .update(
                from: TechnicalViewModel(
                    skaterName: "S.HSU",
                    elementName: "1 Axel",
                    baseValue: "1.10",
                    goeValue: "0.11",
                    totalValue: "88.88",
                    boxModes: [.positive, .unscored, .negative, .unscored, .unscored, .unscored, .unscored, .unscored]
                )
            )
        return view
    }
    
    func updateUIView(_ uiView: IsuTechnicalPaneView, context: Context) {
        // Updates the state of the specified view with new information from SwiftUI.
    }

}

#Preview {
    ContentView()
}
