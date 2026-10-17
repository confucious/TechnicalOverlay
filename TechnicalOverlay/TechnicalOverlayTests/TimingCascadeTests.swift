//
//  TimingCascadeTests.swift
//  TechnicalOverlayTests
//

import Foundation
import Testing
@testable import TechnicalOverlay

/// `setIntroTime` / `setElementTime` move the edited item and carry the delta to everything after it,
/// so the clip keeps its internal spacing. Introductions also lay out a trailing run of unscheduled
/// slides five seconds apart; elements leave an unscheduled one alone.
@Suite struct TimingCascadeTests {

    private func introductions(_ times: [TimeInterval?]) -> OverlayData {
        OverlayData(introductionTexts: times.map {
            IntroductionData(left: "", center: "", right: "", displayTime: $0)
        })
    }

    private func elements(_ times: [TimeInterval?]) -> OverlayData {
        OverlayData(elementScores: times.map {
            ElementData(name: "", baseValue: 0, goeValue: 0, bonusValue: 0, displayTime: $0)
        })
    }

    @Test func movingAnIntroCarriesTheDeltaToTheOnesAfterIt() {
        let data = introductions([10, 15, 25])
        data.setIntroTime(index: 0, time: 20)
        #expect(data.introductionTexts.map(\.displayTime) == [20, 25, 35])
    }

    @Test func anUnscheduledRunAfterAnIntroIsStampedFiveSecondsApart() {
        let data = introductions([10, nil, nil])
        data.setIntroTime(index: 0, time: 20)
        #expect(data.introductionTexts.map(\.displayTime) == [20, 25, 30])
    }

    @Test func anUnscheduledIntroIsStampedOnlyUpToTheNextTimedSlide() {
        let data = introductions([nil, nil, 40])
        data.setIntroTime(index: 0, time: 10)
        #expect(data.introductionTexts.map(\.displayTime) == [10, 15, 40])
    }

    @Test func movingAnElementCarriesTheDeltaAndLeavesUnscheduledOnesAlone() {
        let data = elements([50, 74, nil])
        data.setElementTime(index: 0, time: 60)
        #expect(data.elementScores.map(\.displayTime) == [60, 84, nil])
    }

    @Test func anUnscheduledElementOnlyTakesItsOwnTime() {
        let data = elements([nil, nil])
        data.setElementTime(index: 0, time: 12)
        #expect(data.elementScores.map(\.displayTime) == [12, nil])
    }

    @Test func anIndexPastTheEndChangesNothing() {
        let data = introductions([10])
        data.setIntroTime(index: 3, time: 99)
        #expect(data.introductionTexts.map(\.displayTime) == [10])
    }
}
