//
//  OverlayData.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/24/25.
//

import CoreMedia
import Foundation
import LayoutEngine
import Observation
import VideoProcessor

@Observable
class OverlayData: Codable {
    var skaterFullName: String
    var skaterAbbreviatedName: String
    var introductionTexts: [IntroductionData]
    var elementScores: [ElementData]

    internal init(skaterFullName: String, skaterAbbreviatedName: String, introductionTexts: [IntroductionData], elementScores: [ElementData]) {
        self.skaterFullName = skaterFullName
        self.skaterAbbreviatedName = skaterAbbreviatedName
        self.introductionTexts = introductionTexts
        self.elementScores = elementScores
    }

    func makeSlides(size: CGSize) -> [Slide] {
        var slides: [Slide] = []
        for introduction in introductionTexts {
            let mode = introduction.makeMode(skaterName: skaterFullName)
            slides.append(makeSlide(size: size, mode: mode, startTime: introduction.displayTime ?? 0.0
            ))
        }
        // Fade out last intro slide
        if let lastIntro = introductionTexts.last {
            slides.append(makeSlide(size: size, mode: .none, startTime: (lastIntro.displayTime ?? 0.0) + 5
            ))
        }

        var cumulativeBoxModes: [ElementBoxView.Mode] = Array(repeating: .unscored, count: elementScores.count)
        var cumulativeScore = 0

        for (index, element) in elementScores.enumerated() {
            cumulativeBoxModes[index] = element.goeValue >= 0 ? .positive : .negative
            cumulativeScore += element.baseValue + element.goeValue + element.bonusValue
            let mode = element.makeMode(
                skaterName: skaterAbbreviatedName,
                runningTotal: cumulativeScore,
                boxModes: cumulativeBoxModes
            )
            slides.append(makeSlide(size: size, mode: mode, startTime: element.displayTime ?? 0.0
            ))
        }
        // Fade out last intro slide
        if let lastElement = elementScores.last {
            slides.append(makeSlide(size: size, mode: .none, startTime: (lastElement.displayTime ?? 0.0) + 5
            ))
        }

        return slides
    }

    func makeSlide(size: CGSize, mode: VideoOverlay.Mode, startTime: TimeInterval) -> Slide {
        return Slide(
            image: VideoOverlay(mode: mode).render(size: size),
            startTime: CMTime(seconds: startTime, preferredTimescale: 1000)
        )
    }
}

@Observable
class IntroductionData: Codable {
    var left: String
    var center: String
    var right: String
    var displayTime: TimeInterval?

    internal init(left: String, center: String, right: String, displayTime: TimeInterval? = nil) {
        self.left = left
        self.center = center
        self.right = right
        self.displayTime = displayTime
    }

    func makeMode(skaterName: String) -> VideoOverlay.Mode {
        return .lowerThirdPane(LowerThirdViewModel(
            skaterName: skaterName,
            secondaryText: (
                center: center,
                left: left,
                right: right
            )))
    }
}

@Observable
class ElementData: Codable, Identifiable, Hashable {
    static func == (lhs: ElementData, rhs: ElementData) -> Bool {
        lhs.name == rhs.name
        && lhs.baseValue == rhs.baseValue
        && lhs.goeValue == rhs.goeValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    var name: String
    var baseValue: Int
    var baseValueString: String {
        get {
            formatValue(baseValue)
        }
        set {
            baseValue = Int((Double(newValue) ?? 0.0) * 100)
        }
    }
    var goeValue: Int
    var goeValueString: String {
        get {
            formatValue(goeValue)
        }
        set {
            goeValue = Int((Double(newValue) ?? 0.0) * 100)
        }
    }
    var bonusValue: Int
    var bonusValueString: String {
        get {
            formatValue(bonusValue)
        }
        set {
            bonusValue = Int((Double(newValue) ?? 0.0) * 100)
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

    func makeMode(skaterName: String, runningTotal: Int, boxModes: [ElementBoxView.Mode]) -> VideoOverlay.Mode {
        return .technicalPane(TechnicalViewModel(
            skaterName: skaterName,
            elementName: name,
            baseValue: bonusValue > 0
            ? "\(formatValue(baseValue)) + \(bonusValue / 100)"
            : formatValue(baseValue),
            goeValue: formatValue(goeValue),
            totalValue: formatValue(runningTotal),
            boxModes: boxModes
        ))
    }

    func formatValue(_ value: Int) -> String {
        let whole = value / 100
        let fractional = abs(value) % 100
        return String(format: "%d.%02d", whole, fractional)
    }
}

