//
//  OverlayConfigurationTests.swift
//  TechnicalOverlayTests
//

import Foundation
import Testing
@testable import TechnicalOverlay

/// Serialized: the suite reads and writes one shared `UserDefaults` key.
@Suite(.serialized)
struct OverlayConfigurationTests {

    private let key = OverlayPreferences.Key.showsElementBox

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

    @Test func elementBoxPreferenceDefaultsToShowingBoxes() {
        withClearedPreference {
            #expect(OverlayPreferences.showsElementBox)
        }
    }

    /// What the toggle writes is what the next launch reads.
    @Test func elementBoxPreferencePersistsAcrossLaunches() {
        withClearedPreference {
            OverlayPreferences.showsElementBox = false

            #expect(!OverlayPreferences.showsElementBox)
            #expect(UserDefaults.standard.bool(forKey: key) == false)

            OverlayPreferences.showsElementBox = true

            #expect(OverlayPreferences.showsElementBox)
        }
    }

    /// A launch picks the stored value up: `MainView.ViewModel` seeds `OverlayData` from it.
    @Test func mainViewModelAppliesTheStoredElementBoxPreference() {
        withClearedPreference {
            OverlayPreferences.showsElementBox = false

            let viewModel = MainView.ViewModel()

            #expect(!viewModel.scoring.showsElementBox)
        }
    }

    /// The look is not document data: a document carrying the key leaves the setting alone.
    @Test func documentDoesNotCarryTheElementBoxSetting() throws {
        let documentJSON = """
        {"skaterFullName":"Alice","skaterAbbreviatedName":"ALI","introductionTexts":[],"elementScores":[],"showsElementBox":false}
        """
        let decoded = try JSONDecoder().decode(
            OverlayData.self,
            from: Data(documentJSON.utf8)
        )

        #expect(decoded.showsElementBox)
        #expect(decoded.skaterFullName == "Alice")
    }

    @Test func elementBoxSettingIsNotWrittenToTheDocument() throws {
        let data = OverlayData(skaterFullName: "Alice")
        data.showsElementBox = false

        let encoded = try JSONEncoder().encode(data)
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(!json.contains("showsElementBox"))
    }

    /// The setting changes the rendered slides, so it belongs in the hash.
    @Test func renderingHashChangesWhenElementBoxesAreHidden() {
        let data = OverlayData(skaterFullName: "Alice")
        let withBoxes = data.renderingHash

        data.showsElementBox = false

        #expect(data.renderingHash != withBoxes)
    }

    /// A technical slide's mode is its cache key, so the two settings must not compare equal.
    @Test func elementBoxSettingChangesTheTechnicalMode() {
        let element = ElementData(name: "3Lz", baseValue: 590, goeValue: 50, bonusValue: 0)

        let shown = element.makeMode(
            skaterName: "ALI",
            runningTotal: 640,
            boxModes: [.positive],
            showsElementBox: true
        )
        let hidden = element.makeMode(
            skaterName: "ALI",
            runningTotal: 640,
            boxModes: [.positive],
            showsElementBox: false
        )

        #expect(shown != hidden)
    }
}
