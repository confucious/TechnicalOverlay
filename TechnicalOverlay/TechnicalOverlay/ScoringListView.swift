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
//            Button("Import Scores") {
//                
//            }
            Grid {
                GridRow {
                    Text("#")
                    Text("Element")
                    Text("Base\n1Value")
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
        .onDisappear {
            state.save()
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
    @FocusState private var focusedField: Field?
    @State private var selection: [Field:TextSelection] = [:]
    enum Field: Int, Hashable {
        case element
        case baseValue
        case goeValue
        case bonusValue
    }

    var body: some View {
        GridRow {
            Text("\(index + 1)")
            TextField(
                "Element",
                text: $state.name
            )
                .focused($focusedField, equals: .element)
            TextField(
                "Base Value",
                text: $state.baseValueString,
                selection: $selection[.baseValue]
            )
                .focused($focusedField, equals: .baseValue)
                .frame(width: 50)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
            TextField(
                "GOE",
                text: $state.goeValueString,
                selection: $selection[.goeValue]
            )
                .focused($focusedField, equals: .goeValue)
                .frame(width: 50)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
            TextField(
                "Bonus",
                text: $state.bonusValueString,
                selection: $selection[.bonusValue]
            )
                .focused($focusedField, equals: .bonusValue)
                .frame(width: 50)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
        }
        .onChange(of: focusedField) {
            switch focusedField {
            case .element:
                break
            case .baseValue:
                selection[.baseValue] = .init(
                    range: state.baseValueString.startIndex..<state.baseValueString.endIndex
                )
            case .goeValue:
                selection[.goeValue] = .init(
                    range: state.goeValueString.startIndex..<state.goeValueString.endIndex
                )
            case .bonusValue:
                selection[.bonusValue] = .init(
                    range: state.bonusValueString.startIndex..<state.bonusValueString.endIndex
                )
            case nil:
                break
            }
        }
    }
}

#Preview {
    ScoringListView(state: overlayData)
}
