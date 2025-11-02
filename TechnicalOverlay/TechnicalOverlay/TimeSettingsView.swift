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
    var timeUpdated: () -> Void

    var body: some View {
        Grid {
            ForEach(state.introductionTexts.enumerated(), id: \.0) { (index, row) in
                GridRow(alignment: .top) {
                    Text(row.displayValue
                    )
                        .gridColumnAlignment(.leading)
                    VStack {
                        Text(formatDisplayTime(row.displayTime))
                        Button("Start Now") {
                            state.setIntroTime(index: index, time: getTime())
                            timeUpdated()
                            state.save()
                        }.buttonStyle(.bordered)
                    }
                }
                Divider()
            }
            ForEach(state.elementScores.enumerated(), id: \.0) { (index, row) in
                GridRow(alignment: .top) {
                    Text("\(index + 1): \(row.name)")
                        .gridColumnAlignment(.leading)
                    VStack {
                        Text(formatDisplayTime(row.displayTime))
                        Button("Start Now") {
                            state.setElementTime(index: index, time: getTime())
                            timeUpdated()
                            state.save()
                        }.buttonStyle(.bordered)
                    }
                }
                Divider()
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
        state: unsetOverlayData,
        getTime: { -now.timeIntervalSinceNow },
        timeUpdated: {}
    )
}
