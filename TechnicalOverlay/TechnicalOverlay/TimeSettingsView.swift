//
//  TimeSettingsView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/25/25.
//

import SwiftUI

struct Playhead {
    var getTime: () -> TimeInterval?
    var seekTo: (TimeInterval) -> Void
}
struct TimeSettingsView: View {
    @State var state: OverlayData
    var playhead: Playhead?
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
                            if let playheadTime = playhead?.getTime() {
                                state
                                    .setIntroTime(
                                        index: index,
                                        time: playheadTime
                                    )
                                timeUpdated()
                                state.save()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(playhead == nil)
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
                            if let playheadTime = playhead?.getTime() {
                                state
                                    .setElementTime(
                                        index: index,
                                        time: playheadTime
                                    )
                                timeUpdated()
                                state.save()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(playhead == nil)
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
            if let playhead {
                Button(formatDisplayTime(time)) {
                    playhead.seekTo(time)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityHint("Jumps the video to this time")
            } else {
                Text(formatDisplayTime(time))
            }
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
        playhead: Playhead(
            getTime: { -now.timeIntervalSinceNow },
            seekTo: { _ in }
        ),
        timeUpdated: {}
    )
}
