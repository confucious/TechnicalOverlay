//
//  ScoringListView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/19/25.
//

import SwiftUI

struct ScoringListView: View {
    enum Metrics {
        static let horizontalPadding: CGFloat = 10
    }

    @State var state: OverlayData
    @State private var importModel = ProtocolImportModel()
    @State private var isAskingForProtocolURL = false

    /// The failure message is the alert's presentation: clearing it dismisses the alert.
    private var importErrorIsPresented: Binding<Bool> {
        Binding(
            get: { importModel.errorMessage != nil },
            set: { if !$0 { importModel.errorMessage = nil } }
        )
    }
    
    var body: some View {
        ScrollView {
            VStack {
                Grid {
                    GridRow {
                        Text("Full Name:")
                            .gridColumnAlignment(.trailing)
                        TextField("Used for Introduction Slides", text: $state.skaterFullName)
                    }
                    GridRow {
                        Text("Abbreviated Name:")
                        TextField("Used for Technical Scores", text: $state.skaterAbbreviatedName)
                    }
                }
                Divider()
                Grid {
                    Text("Introduction Slides").bold()
                    GridRow {
                        Text("Left")
                            .gridColumnAlignment(.leading)
                        Text("Center")
                        Text("Right")
                            .gridColumnAlignment(.trailing)
                    }.bold()
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
                    .buttonStyle(.bordered)
                    Button("Remove Last Slide") {
                        state.introductionTexts = state.introductionTexts.dropLast()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                Divider()
                Grid {
                    GridRow {
                        Text("#")
                        Text("Element")
                        Text("Base")
                        Text("GOE")
                        Text("Bonus")
                    }.bold()
                    ForEach(Array(state.elementScores.enumerated()), id: \.0) { (index, element) in
                        ElementRowView(index: index, state: element)
                    }
                }
                HStack {
                    Button("Import Protocol") {
                        importModel.errorMessage = nil
                        isAskingForProtocolURL = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(importModel.isImporting)
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
                    .buttonStyle(.bordered)
                    Button("Delete Last Element") {
                        state.elementScores = state.elementScores.dropLast()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    if importModel.isImporting {
                        ProgressView()
                    }
                }
            }
            .padding(
                .init(
                    top: 0.0,
                    leading: Metrics.horizontalPadding,
                    bottom: 0.0,
                    trailing: Metrics.horizontalPadding
                )
            )
            .alert("Import Failed", isPresented: importErrorIsPresented, presenting: importModel.errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
        .onDisappear {
            state.save()
            state.clearCache()
        }
        .alert("Import Protocol", isPresented: $isAskingForProtocolURL) {
            TextField("Protocol page address", text: $importModel.urlString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Import") {
                Task { await importModel.importElements(into: state) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste this segment's results page address, or its judge detail scores page. The elements are merged into the list below, keeping the timings you have already set.")
        }
    }
}

struct IntroductionRowView: View {
    @State var state: IntroductionData

    var body: some View {
        GridRow {
            TextField("Left", text: $state.left)
            TextField("Center", text: $state.center, axis: .vertical)
                .multilineTextAlignment(.leading)
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
                "0.0",
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
