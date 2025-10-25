//
//  TimeSettingsView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/25/25.
//

import SwiftUI

struct TimeSettingsView: View {
    @State var state: OverlayData
    var getTime: () -> TimeInterval

    var body: some View {
        Grid {
            ForEach(state.introductionTexts.enumerated(), id: \.0) { (index, row) in
                GridRow {
                    Text(row.center)
                    VStack {
                        Button("Start Now") {
                            state.setIntroTime(index: index, time: getTime())
                        }
                        Text(formatDisplayTime(row.displayTime))
                    }
                }
            }
            ForEach(state.elementScores.enumerated(), id: \.0) { (index, row) in
                GridRow {
                    Text("Element \(index + 1): \(row.name)")
                    VStack {
                        Button("Start Now") {
                            state.setElementTime(index: index, time: getTime())
                        }
                        Text(formatDisplayTime(row.displayTime))
                    }
                }
            }
        }
    }

    func formatDisplayTime(_ time: TimeInterval?) -> String {
        guard let time else { return "--" }
        let wholeSeconds = Int(floor(time))
        let minutes = wholeSeconds / 60
        let seconds = time - Double(minutes * 60)
        return String(format: "%dm %.1fs", minutes, seconds)
    }
}

#Preview {
    let now = Date.now
    TimeSettingsView(
        state: overlayData,
        getTime: { -now.timeIntervalSinceNow }
    )
}
