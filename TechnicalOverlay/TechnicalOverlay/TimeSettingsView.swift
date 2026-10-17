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
    var seekTo: (TimeInterval) -> Void
    var timeUpdated: () -> Void

    var body: some View {
        Grid {
            ForEach(state.introductionTexts.enumerated(), id: \.0) { (index, row) in
                GridRow(alignment: .top) {
                    Text(row.displayValue
                    )
                        .gridColumnAlignment(.leading)
                    VStack {
                        displayTime(row.displayTime)
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
                        displayTime(row.displayTime)
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

    /// A set time is a button that jumps the playhead there; an unset one is plain text, since there
    /// is nowhere to jump to.
    @ViewBuilder
    func displayTime(_ time: TimeInterval?) -> some View {
        if let time {
            Button(formatDisplayTime(time)) {
                seekTo(time)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityHint("Jumps the video to this time")
        } else {
            Text(formatDisplayTime(nil))
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
        seekTo: { _ in },
        timeUpdated: {}
    )
}
