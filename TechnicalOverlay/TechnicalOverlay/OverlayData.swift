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
class OverlayData {
    var skaterFullName: String {
        didSet {
            continuation.yield()
        }
    }
    var skaterAbbreviatedName: String {
        didSet {
            continuation.yield()
        }
    }
    var introductionTexts: [IntroductionData] {
        didSet {
            continuation.yield()
        }
    }
    var elementScores: [ElementData] {
        didSet {
            continuation.yield()
        }
    }

    var changeStream: AsyncStream<Void>
    private var continuation: AsyncStream<Void>.Continuation

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
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        self.changeStream = stream
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
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
class IntroductionData: Codable, Identifiable {
    var id = UUID()
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
class ElementData: Codable, Identifiable {
    var id = UUID()
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
            bonusValue > 0 ? formatValue(bonusValue) : "--"
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
