//
//  ScoringListView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/19/25.
//

import SwiftUI

struct ScoringListView: View {
    @State private var state: OverlayData = overlayData
    
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
                GridRow {
                    Text("Age: 12")
                    Text("Coaches: Philip Deyesso, Renée Lauren-Roos")
                    Text("SC of Boston")
                }
                GridRow {
                    Text("")
                    Text("Music: The Mask of Zorro by James Horner")
                    Text("")
                }
            }
            Button("Add Slide") {
                
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
                ForEach(Array(state.elementScores.enumerated()), id: \.1) { (index, element) in
                    ElementRowView(index: index, state: element)
                }
            }
            Button("Add Element") {
                
            }
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
    ScoringListView()
}
