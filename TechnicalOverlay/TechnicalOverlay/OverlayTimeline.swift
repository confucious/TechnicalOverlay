//
//  OverlayTimeline.swift
//  TechnicalOverlay
//
//  Editing the timeline: moving one item's display time and carrying the change to the items after
//  it.
//

import Foundation

extension OverlayData {

    /// Moves an introduction slide to `time`, carrying the delta to the slides after it.
    ///
    /// A trailing run of unscheduled slides is stamped five seconds apart, so adding a slide and
    /// setting its time lays the rest of the introduction out in one gesture.
    func setIntroTime(index: Int, time: TimeInterval) {
        shiftTimes(
            in: introductionTexts,
            from: index,
            to: time,
            defaultUnsetSpacing: 5,
            displayTime: { $0.displayTime },
            setDisplayTime: { $0.displayTime = $1 }
        )
    }

    /// Moves a scored element to `time`, carrying the delta to the elements after it. An element
    /// with no time is left unscheduled — the timeline is the user's to fill in.
    func setElementTime(index: Int, time: TimeInterval) {
        shiftTimes(
            in: elementScores,
            from: index,
            to: time,
            displayTime: { $0.displayTime },
            setDisplayTime: { $0.displayTime = $1 }
        )
    }

    /// The cascade both setters share: the item at `index` takes `time`, and every item after it
    /// moves by the same delta, so relative spacing survives.
    ///
    /// With `defaultUnsetSpacing`, the unscheduled run that follows is filled in as
    /// `previous + spacing` — introductions use it to lay out slides the user has not timed yet.
    /// Without it, the first unscheduled item ends the cascade.
    private func shiftTimes<Item>(
        in items: [Item],
        from index: Int,
        to time: TimeInterval,
        defaultUnsetSpacing: TimeInterval? = nil,
        displayTime: (Item) -> TimeInterval?,
        setDisplayTime: (Item, TimeInterval?) -> Void
    ) {
        guard items.indices.contains(index) else {
            return
        }

        let oldTime = displayTime(items[index])
        setDisplayTime(items[index], time)

        var cursor = index + 1

        if let oldTime {
            let delta = time - oldTime
            while cursor < items.count, let itemTime = displayTime(items[cursor]) {
                setDisplayTime(items[cursor], itemTime + delta)
                cursor += 1
            }
        }

        guard let spacing = defaultUnsetSpacing,
              cursor < items.count,
              displayTime(items[cursor]) == nil
        else {
            return
        }

        var previous = time
        while cursor < items.count, displayTime(items[cursor]) == nil {
            previous += spacing
            setDisplayTime(items[cursor], previous)
            cursor += 1
        }
    }
}
