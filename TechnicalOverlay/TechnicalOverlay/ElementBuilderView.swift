//
//  ElementBuilderView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/28/25.
//

import SwiftUI

struct ElementBuilderView: View {
    @State var selectedDiscipline: Int = 3
    @State var elementType: Int = 0
    var body: some View {
        Picker(
            "Discipline",
            selection: $selectedDiscipline) {
                Text("Singles").tag(0)
                Text("Pairs").tag(1)
                Text("Ice Dance").tag(2)
                Text("Synchronized Skating").tag(3)
            }
            .pickerStyle(.segmented)
        switch selectedDiscipline {
        case 0:
            Picker(
                "Type",
                selection: $elementType) {
                    Text("Jumps").tag(0)
                    Text("Spins").tag(1)
                    Text("Steps & Spirals").tag(2)
                }
                .pickerStyle(.segmented)
        default:
            Text("")
        }
    }
}

#Preview {
    ElementBuilderView()
}
