//
//  TechnicalPaneStylePreferenceTests.swift
//  TechnicalOverlayTests
//

import Foundation
import LayoutEngine
import Testing
@testable import TechnicalOverlay

/// Serialized: the suite reads and writes one shared `UserDefaults` key.
@Suite(.serialized)
struct TechnicalPaneStylePreferenceTests {

    private let key = OverlayPreferences.Key.technicalPaneStyle

    /// The preference is device state, so each test starts from a known value and leaves one behind.
    private func withClearedPreference(_ body: () throws -> Void) rethrows {
        let original = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try body()
    }

    @Test func stylePreferenceDefaultsToTheClassicPane() {
        withClearedPreference {
            #expect(OverlayPreferences.technicalPaneStyle == .classic)
        }
    }

    /// What the menu writes is what the next launch reads.
    @Test func stylePreferencePersistsAcrossLaunches() {
        withClearedPreference {
            OverlayPreferences.technicalPaneStyle = .isu2026

            #expect(OverlayPreferences.technicalPaneStyle == .isu2026)
            #expect(UserDefaults.standard.string(forKey: key) == "isu2026")

            OverlayPreferences.technicalPaneStyle = .classic

            #expect(OverlayPreferences.technicalPaneStyle == .classic)
        }
    }

    /// A style this build does not know cannot leave the overlay undrawable.
    @Test func anUnknownStoredStyleReadsAsTheClassicPane() {
        withClearedPreference {
            UserDefaults.standard.set("isu2030", forKey: key)

            #expect(OverlayPreferences.technicalPaneStyle == .classic)
        }
    }

    /// A launch picks the stored value up: `MainViewModel` seeds `OverlayData` from it.
    @Test func mainViewModelAppliesTheStoredStyle() {
        withClearedPreference {
            OverlayPreferences.technicalPaneStyle = .isu2026

            let viewModel = MainViewModel()

            #expect(viewModel.scoring.technicalPaneStyle == .isu2026)
        }
    }

    /// The style is not document data: a document carrying the key leaves the setting alone.
    @Test func documentDoesNotCarryTheStyle() throws {
        let documentJSON = """
        {"skaterFullName":"Alice","skaterAbbreviatedName":"ALI","introductionTexts":[],"elementScores":[],"technicalPaneStyle":"isu2026"}
        """
        let decoded = try JSONDecoder().decode(
            OverlayData.self,
            from: Data(documentJSON.utf8)
        )

        #expect(decoded.technicalPaneStyle == .classic)
        #expect(decoded.skaterFullName == "Alice")
    }

    @Test func styleIsNotWrittenToTheDocument() throws {
        let data = OverlayData(skaterFullName: "Alice")
        data.technicalPaneStyle = .isu2026

        let encoded = try JSONEncoder().encode(data)
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(!json.contains("technicalPaneStyle"))
    }

    /// The style changes the rendered slides, so it belongs in the hash.
    @Test func renderingHashChangesWithTheStyle() {
        let data = OverlayData(skaterFullName: "Alice")
        let classic = data.renderingHash

        data.technicalPaneStyle = .isu2026

        #expect(data.renderingHash != classic)
    }

    /// The reordered classic is a style of its own: it round-trips through the stored value and
    /// reaches the slide the pane is drawn from.
    @Test func reorderedClassicStyleReachesTheSlides() throws {
        withClearedPreference {
            OverlayPreferences.technicalPaneStyle = .classic2

            #expect(OverlayPreferences.technicalPaneStyle == .classic2)
            #expect(UserDefaults.standard.string(forKey: key) == "classic2")
        }

        let data = OverlayData(
            skaterFullName: "Alice",
            skaterAbbreviatedName: "ALI",
            elementScores: [ElementData(
                name: "3Lz",
                baseValue: 590,
                goeValue: 50,
                bonusValue: 0,
                displayTime: 10
            )]
        )
        data.technicalPaneStyle = .classic2

        let mode = try #require(data.slidePlan().first?.mode)
        guard case let .technicalPane(viewModel) = mode else {
            Issue.record("the first slide is not a technical pane")
            return
        }
        #expect(viewModel.style == .classic2)
    }

    /// End to end: the document's style reaches the slide the pane is drawn from.
    @Test func slidePlanDrawsElementsInTheStoredStyle() throws {
        let data = OverlayData(
            skaterFullName: "Alice",
            skaterAbbreviatedName: "ALI",
            elementScores: [ElementData(
                name: "3Lz",
                baseValue: 590,
                goeValue: 50,
                bonusValue: 0,
                displayTime: 10
            )]
        )
        data.technicalPaneStyle = .isu2026

        let plan = data.slidePlan()

        let mode = try #require(plan.first?.mode)
        guard case let .technicalPane(viewModel) = mode else {
            Issue.record("the first slide is not a technical pane")
            return
        }
        #expect(viewModel.style == .isu2026)
        #expect(viewModel.totalValue == "6.40")
    }
}
