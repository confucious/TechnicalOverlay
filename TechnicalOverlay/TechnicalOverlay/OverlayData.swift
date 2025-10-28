//
//  OverlayData.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/24/25.
//

import CoreImage
import CoreMedia
import Foundation
import LayoutEngine
import Observation
import VideoProcessor

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

    // MARK: - Load / Save
    func save() {
        guard let json = try? JSONEncoder().encode(self)
        else {
            print("Couldn't serialize to save state")
            return
        }
        print("saved")
        UserDefaults.standard.set(json, forKey: "state")
    }
    
    func load() {
        guard let data = UserDefaults.standard.data(forKey: "state") else {
            print("No saved state found.")
            return
        }
        guard let loaded = try? JSONDecoder().decode(Self.self, from: data) else {
            print("Couldn't decode saved state")
            return
        }
        self.skaterFullName = loaded.skaterFullName
        self.skaterAbbreviatedName = loaded.skaterAbbreviatedName
        self.introductionTexts = loaded.introductionTexts
        self.elementScores = loaded.elementScores
        print("loaded")
    }
    
    // MARK: - State management

    var isEmpty: Bool {
        skaterFullName == "" && skaterAbbreviatedName == "" && introductionTexts.isEmpty && elementScores.isEmpty
    }

    func setIntroTime(index: Int, time: TimeInterval) {
        guard index < introductionTexts.count else {
            return
        }
        if let oldTime = introductionTexts[index].displayTime {
            let diff = time - oldTime
            introductionTexts[index].displayTime = time
            if index + 1 < introductionTexts.count {
                let nextItem = introductionTexts[index + 1]
                if let oldNextTime = nextItem.displayTime {
                    setIntroTime(index: index + 1, time: oldNextTime + diff)
                } else {
                    setIntroTime(index: index + 1, time: time + 5)
                }
            }
        } else {
            // Old time wasn't set.
            introductionTexts[index].displayTime = time
            if index + 1 < introductionTexts.count {
                let nextItem = introductionTexts[index + 1]
                if nextItem.displayTime == nil {
                    setIntroTime(index: index + 1, time: time + 5)
                }
            }
        }
    }

    func setElementTime(index: Int, time: TimeInterval) {
        guard index < elementScores.count else {
            return
        }
        if let oldTime = elementScores[index].displayTime {
            let diff = time - oldTime
            elementScores[index].displayTime = time
            if index + 1 < elementScores.count {
                if let oldNextTime = elementScores[index + 1].displayTime {
                    setElementTime(index: index + 1, time: oldNextTime + diff)
                }
            }
        } else {
            // Old time wasn't set.
            elementScores[index].displayTime = time
        }
    }

    // MARK: - Generation
    private struct CacheKey: Hashable {
        let size: CGSize
        let mode: VideoOverlay.Mode
    }
    private var imageCache: [CacheKey:CIImage] = [:]

    func clearCache() {
        imageCache = [:]
    }
    
    func makeSlides(size: CGSize) -> [Slide] {
        var slides: [Slide] = []
        for introduction in introductionTexts {
            let mode = introduction.makeMode(skaterName: skaterFullName)
            if let displayTime = introduction.displayTime {
                slides.append(
                    makeSlide(
                        size: size,
                        mode: mode,
                        startTime: displayTime
                    )
                )
            }
        }
        // Fade out last intro slide
        if let lastSlide = slides.last {
            slides.append(makeSlide(size: size, mode: .none, startTime: lastSlide.startTime.seconds + 5))
        }

        var cumulativeBoxModes: [ElementBoxView.Mode] = Array(repeating: .unscored, count: elementScores.count)
        var cumulativeScore = 0

        for (index, element) in elementScores.enumerated() {
            cumulativeBoxModes[index] = if element.baseValue == 0 {
                .neutral
            } else if element.goeValue >= 0 {
                .positive
            } else {
                .negative
            }
            cumulativeScore += element.baseValue + element.goeValue + element.bonusValue
            let mode = element.makeMode(
                skaterName: skaterAbbreviatedName,
                runningTotal: cumulativeScore,
                boxModes: cumulativeBoxModes
            )
            if let displayTime = element.displayTime {
                slides
                    .append(makeSlide(size: size, mode: mode, startTime: displayTime
                                       ))
            }
        }
        // Fade out last intro slide
        if let lastSlide = slides.last {
            slides
                .append(
                    makeSlide(
                        size: size,
                        mode: .none,
                        startTime: lastSlide.startTime.seconds + 5
            ))
        }

        return slides
    }

    func makeSlide(size: CGSize, mode: VideoOverlay.Mode, startTime: TimeInterval) -> Slide {
        let image: CIImage
        if let cachedImage = imageCache[CacheKey(size: size, mode: mode)] {
            image = cachedImage
        } else {
            image = VideoOverlay(mode: mode).render(size: size)
            imageCache[CacheKey(size: size, mode: mode)] = image
        }
        return Slide(
            image: image,
            startTime: CMTime(seconds: startTime, preferredTimescale: 1000)
        )
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
            bonusValue > 0 ? formatValue(bonusValue) : ""
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
        let negative = value < 0
        let whole = abs(value) / 100
        let fractional = abs(value) % 100
        if negative {
            return String(format: "-%d.%02d", whole, fractional)
        } else {
            return String(format: "%d.%02d", whole, fractional)
        }
    }
}
