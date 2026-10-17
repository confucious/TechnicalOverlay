//
//  ClearSlidesTests.swift
//  TechnicalOverlayTests
//

import Foundation
import Testing
@testable import TechnicalOverlay

/// Serialized: the suite writes the shared `UserDefaults` autosave key that `ViewModel` reads.
@Suite(.serialized)
struct ClearSlidesTests {

    private static let autosaveKey = "state"

    /// Clearing goes through `ViewModel.clearSlides()`, which updates the shared instance in place,
    /// saves the emptied state and regenerates the slides.
    @Test func clearSlidesEmptiesTheModelAndTheSavedState() throws {
        let originalAutosave = UserDefaults.standard.data(forKey: Self.autosaveKey)
        defer {
            if let originalAutosave {
                UserDefaults.standard.set(originalAutosave, forKey: Self.autosaveKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.autosaveKey)
            }
        }

        let viewModel = MainView.ViewModel()
        let scoring = viewModel.scoring
        scoring.skaterFullName = "Alice"
        scoring.skaterAbbreviatedName = "ALI"
        scoring.introductionTexts = [
            IntroductionData(left: "Age 12", center: "", right: "", displayTime: 3.0)
        ]
        scoring.elementScores = [
            ElementData(name: "3Lz", baseValue: 590, goeValue: 50, bonusValue: 0, displayTime: 8.0)
        ]
        scoring.save()

        viewModel.clearSlides()

        #expect(viewModel.scoring.isEmpty)
        #expect(viewModel.scoring.elementScores.isEmpty)
        #expect(viewModel.scoring.introductionTexts.isEmpty)
        // Same instance, so views holding it see the reset rather than a detached copy.
        #expect(viewModel.scoring === scoring)

        let saved = try #require(UserDefaults.standard.data(forKey: Self.autosaveKey))
        let persisted = try JSONDecoder().decode(OverlayData.self, from: saved)
        #expect(persisted.isEmpty)
    }

    /// A cleared model still shows the element boxes setting the device prefers.
    @Test func clearSlidesDoesNotTouchTheDevicePreference() {
        let originalAutosave = UserDefaults.standard.data(forKey: Self.autosaveKey)
        let originalPreference = UserDefaults.standard
            .object(forKey: OverlayPreferences.Key.showsElementBox)
        defer {
            if let originalAutosave {
                UserDefaults.standard.set(originalAutosave, forKey: Self.autosaveKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.autosaveKey)
            }
            if let originalPreference {
                UserDefaults.standard.set(
                    originalPreference,
                    forKey: OverlayPreferences.Key.showsElementBox
                )
            } else {
                UserDefaults.standard.removeObject(forKey: OverlayPreferences.Key.showsElementBox)
            }
        }

        OverlayPreferences.showsElementBox = false
        let viewModel = MainView.ViewModel()
        #expect(!viewModel.scoring.showsElementBox)

        viewModel.clearSlides()

        #expect(!viewModel.scoring.showsElementBox)
    }
}
