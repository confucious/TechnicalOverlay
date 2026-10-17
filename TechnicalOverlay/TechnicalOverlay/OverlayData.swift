//
//  OverlayData.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/24/25.
//
//  The document: the skater, the introduction slides and the scored elements. Timing edits live in
//  OverlayTimeline.swift, persistence in OverlayStore.swift, rendering in SlideFactory.swift and the
//  score string conversions in ScoreFormatting.swift.
//

import Foundation
import LayoutEngine
import Observation

@Observable
class OverlayData: Codable {
    enum CodingKeys: String, CodingKey {
        case _skaterFullName = "skaterFullName"
        case _skaterAbbreviatedName = "skaterAbbreviatedName"
        case _introductionTexts = "introductionTexts"
        case _elementScores = "elementScores"
    }
    
    var skaterFullName: String
    var skaterAbbreviatedName: String
    var introductionTexts: [IntroductionData]
    var elementScores: [ElementData]
    /// Whether the technical pane draws its element box row. A **device preference**, not document
    /// data: `OverlayPreferences` owns it in UserDefaults, so it is deliberately absent from
    /// `CodingKeys` and is not copied by `update(from:)` when a document is loaded.
    var showsElementBox: Bool = true

    internal init(
        skaterFullName: String = "",
        skaterAbbreviatedName: String = "",
        introductionTexts: [IntroductionData] = [],
        elementScores: [ElementData] = []
    ) {
        self.skaterFullName = skaterFullName
        self.skaterAbbreviatedName = skaterAbbreviatedName
        self.introductionTexts = introductionTexts
        self.elementScores = elementScores
    }
    
    func update(from data: OverlayData) {
        skaterFullName = data.skaterFullName
        skaterAbbreviatedName = data.skaterAbbreviatedName
        introductionTexts = data.introductionTexts
        elementScores = data.elementScores
    }

    // MARK: - State management

    var isEmpty: Bool {
        skaterFullName == "" && skaterAbbreviatedName == "" && introductionTexts.isEmpty && elementScores.isEmpty
    }

    // MARK: - Rendering Hash

    /// Deterministic hash of all rendering-affecting fields.
    var renderingHash: String {
        var hasher = Hasher()
        skaterFullName.hash(into: &hasher)
        skaterAbbreviatedName.hash(into: &hasher)
        showsElementBox.hash(into: &hasher)
        for intro in introductionTexts {
            intro.left.hash(into: &hasher)
            intro.center.hash(into: &hasher)
            intro.right.hash(into: &hasher)
            intro.displayTime?.hash(into: &hasher)
        }
        for elem in elementScores {
            elem.name.hash(into: &hasher)
            elem.baseValue.hash(into: &hasher)
            elem.goeValue.hash(into: &hasher)
            elem.bonusValue.hash(into: &hasher)
            elem.displayTime?.hash(into: &hasher)
        }
        return String(hasher.finalize())
    }
}

@Observable
class IntroductionData: Codable {
    enum CodingKeys: String, CodingKey {
        case _left = "left"
        case _center = "center"
        case _right = "right"
        case _displayTime = "displayTime"
    }
    
    var left: String
    var center: String
    var right: String
    var displayTime: TimeInterval?
    
    var displayValue: String {
        [left, center, right]
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
            
    }

    internal init(left: String, center: String, right: String, displayTime: TimeInterval? = nil) {
        self.left = left
        self.center = center
        self.right = right
        self.displayTime = displayTime
    }

    func makeMode(skaterName: String) -> VideoOverlay.Mode {
        return .lowerThirdPane(LowerThirdViewModel(
            skaterName: skaterName,
            leftText: left,
            centerText: center,
            rightText: right
        ))
    }
}

@Observable
class ElementData: Codable {
    enum CodingKeys: String, CodingKey {
        case _name = "name"
        case _baseValue = "baseValue"
        case _goeValue = "goeValue"
        case _bonusValue = "bonusValue"
        case _displayTime = "displayTime"
    }
    
    var name: String
    var baseValue: Int
    var baseValueString: String {
        get {
            formatValue(baseValue)
        }
        set {
            baseValue = newValue.toHundredthsInt()
        }
    }
    var goeValue: Int
    var goeValueString: String {
        get {
            formatValue(goeValue)
        }
        set {
            goeValue = newValue.toHundredthsInt()
        }
    }
    var bonusValue: Int
    var bonusValueString: String {
        get {
            bonusValue > 0 ? formatValue(bonusValue, decimalPlaces: 1) : ""
        }
        set {
            bonusValue = newValue.toHundredthsInt()
        }
    }
    var displayTime: TimeInterval?

    internal init(name: String, baseValue: Int, goeValue: Int, bonusValue: Int, displayTime: TimeInterval? = nil) {
        self.name = name
        self.baseValue = baseValue
        self.goeValue = goeValue
        self.bonusValue = bonusValue
        self.displayTime = displayTime
    }

    func makeMode(
        skaterName: String,
        runningTotal: Int,
        boxModes: [ElementBoxView.Mode],
        showsElementBox: Bool
    ) -> VideoOverlay.Mode {
        return .technicalPane(TechnicalViewModel(
            skaterName: skaterName,
            elementName: name,
            baseValue: bonusValue > 0
            ? "\(formatValue(baseValue)) + \(bonusValue / 100)"
            : formatValue(baseValue),
            goeValue: formatValue(goeValue),
            totalValue: formatValue(runningTotal),
            boxModes: boxModes,
            showsElementBox: showsElementBox
        ))
    }
}
