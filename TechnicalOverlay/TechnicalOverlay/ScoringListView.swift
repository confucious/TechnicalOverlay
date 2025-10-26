//
//  ScoringListView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/19/25.
//

import SwiftUI

struct ScoringListView: View {
    @State var state: OverlayData
    
    var body: some View {
        ScrollView {
            Grid {
                GridRow {
                    Text("Full Name")
                    TextField("Used for Introduction Slides", text: $state.skaterFullName)
                }
                GridRow {
                    Text("Abbreviated Name")
                    TextField("Used for Technical Scores", text: $state.skaterAbbreviatedName)
                }
            }
            Divider()
            Grid {
                Text("Introduction Slides")
                GridRow {
                    Text("Left")
                    Text("Center")
                    Text("Right")
                }
                ForEach(Array(state.introductionTexts.enumerated()), id: \.0) { (_, row) in
                    IntroductionRowView(state: row)
                }
            }
            HStack {
                Button("Add Slide") {
                    state.introductionTexts.append(
                        IntroductionData(left: "", center: "", right: "")
                    )
                }
                Button("Remove Last Slide") {
                    state.introductionTexts = state.introductionTexts.dropLast()
                }
            }
            Divider()
            Button("Import Scores") {
                
            }
            Grid {
                GridRow {
                    Text("#")
                    Text("Element")
                    Text("Base Value")
                    Text("GOE")
                    Text("Bonus")
                }
                ForEach(Array(state.elementScores.enumerated()), id: \.0) { (index, element) in
                    ElementRowView(index: index, state: element)
                }
            }
            HStack {
                Button("Add Element") {
                    state.elementScores
                        .append(
                            ElementData(
                                name: "",
                                baseValue: 0,
                                goeValue: 0,
                                bonusValue: 0
                            )
                        )
                }
                Button("Remove Last Slide") {
                    state.elementScores = state.elementScores.dropLast()
                }
            }
        }
    }
}

struct IntroductionRowView: View {
    @State var state: IntroductionData

    var body: some View {
        GridRow {
            TextField("Left", text: $state.left)
            TextField("Center", text: $state.center, axis: .vertical)
                .multilineTextAlignment(.center)
            TextField("Right", text: $state.right)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ElementRowView: View {
    var index: Int
    @State var state: ElementData

    var body: some View {
        GridRow {
            Text("\(index + 1)")
            TextField("Element", text: $state.name)
            TextField("Base Value", text: $state.baseValueString).frame(width: 100).multilineTextAlignment(.trailing)
            TextField("GOE", text: $state.goeValueString).frame(width: 75).multilineTextAlignment(.trailing)
            TextField("Bonus", text: $state.bonusValueString).frame(width: 75).multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    ScoringListView(state: overlayData)
}
