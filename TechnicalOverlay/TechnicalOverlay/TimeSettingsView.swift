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

    enum Metrics {
        /// A row's height. The stamp control is the smallest thing on the row, so without this the
        /// row would be a 20 pt line of text; 44 pt is the minimum tap target.
        static let rowHeight: CGFloat = 44
    }

    var state: OverlayData
    var playhead: Playhead?
    var timeUpdated: () -> Void

    var body: some View {
        // No inter-row spacing: the divider is already the separator.
        VStack(spacing: 0) {
            ForEach(state.introductionTexts.enumerated(), id: \.0) { (index, row) in
                timelineRow(row.displayValue, time: row.displayTime) { time in
                    state.setIntroTime(index: index, time: time)
                    timeUpdated()
                    state.save()
                }
                Divider()
            }
            ForEach(state.elementScores.enumerated(), id: \.0) { (index, row) in
                timelineRow("\(index + 1): \(row.name)", time: row.displayTime) { time in
                    state.setElementTime(index: index, time: time)
                    timeUpdated()
                    state.save()
                }
                Divider()
            }
        }
    }

    /// One row, one line: the label takes the slack so the time and its stamp button keep their
    /// width at the trailing edge, and the row is held to `rowHeight` — a full tap target rather
    /// than a 20 pt line of text.
    @ViewBuilder
    func timelineRow(
        _ label: String,
        time: TimeInterval?,
        stamp: @escaping (TimeInterval) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            displayTime(time)
            startNowButton(stamp: stamp)
        }
        .frame(minHeight: Metrics.rowHeight)
    }

    /// A stopwatch glyph, not a play glyph: the control stamps the playhead's *current* time, it does
    /// not start playback. Icon-only, so the accessibility label has to carry the verb.
    ///
    /// With no playhead there is nothing to stamp, so a hidden button holds the row's height in its
    /// place.
    @ViewBuilder
    func startNowButton(stamp: @escaping (TimeInterval) -> Void) -> some View {
        let label = Label("Start now", systemImage: "stopwatch")
            .labelStyle(.iconOnly)

        if let playhead {
            Button {
                if let time = playhead.getTime() {
                    stamp(time)
                }
            } label: {
                label
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Start now")
            .accessibilityHint("Stamps the time under the playhead")
        } else {
            Button {} label: {
                label
            }
            .buttonStyle(.bordered)
            .hidden()
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

#Preview("With a playhead") {
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

#Preview("No video") {
    TimeSettingsView(
        state: unsetOverlayData,
        playhead: nil,
        timeUpdated: {}
    )
}
