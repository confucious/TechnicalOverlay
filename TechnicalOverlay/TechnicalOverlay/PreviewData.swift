//
//  PreviewData.swift
//  TechnicalOverlay
//
//  Sample documents for the `#Preview`s. Nothing in the app reads these — they only give the
//  previews a populated document to draw.
//

import Foundation

/// A full program: two introduction slides and eight scored elements.
let overlayData = OverlayData(
    skaterFullName: "Scotty HSU",
    skaterAbbreviatedName: "S. HSU",
    introductionTexts: [
        IntroductionData(
            left: "Age 12",
            center: "Coaches: Philip Deyesso, Renée Laurin-Roos",
            right: "SC of Boston",
            displayTime: 8.5
        ),
        IntroductionData(
            left: "",
            center: "Music: The Mask of Zorro by James Horner",
            right: "",
            displayTime: 13.5
        )
    ],
    elementScores: [
        ElementData(
            name: "2 Lutz + 2 Toeloop",
            baseValue: 340,
            goeValue: 11,
            bonusValue: 0,
            displayTime: 50.46
        ),
        ElementData(
            name: "2 Axel + 1 Axel + 2 Toeloop + SEQ",
            baseValue: 570,
            goeValue: 17,
            bonusValue: 100,
            displayTime: 74.1
        ),
        ElementData(
            name: "Flying Sit Spin 4",
            baseValue: 300,
            goeValue: 45,
            bonusValue: 0,
            displayTime: 93.8
        ),
        ElementData(
            name: "2 Axel",
            baseValue: 290,
            goeValue: -119,
            bonusValue: 100,
            displayTime: 109
        ),
        ElementData(
            name: "2 Lutz",
            baseValue: 231,
            goeValue: -11,
            bonusValue: 0,
            displayTime: 119
        ),
        ElementData(
            name: "Step Sequence 1",
            baseValue: 180,
            goeValue: 18,
            bonusValue: 0,
            displayTime: 150
        ),
        ElementData(
            name: "2 Flip",
            baseValue: 198,
            goeValue: 14,
            bonusValue: 0,
            displayTime: 161
        ),
        ElementData(
            name: "Ch Combination Spin 4",
            baseValue: 350,
            goeValue: 26,
            bonusValue: 0,
            displayTime: 179
        )
    ])

/// The same document with no timestamps, for the timeline's unset state.
let unsetOverlayData = OverlayData(
    skaterFullName: overlayData.skaterFullName,
    skaterAbbreviatedName: overlayData.skaterAbbreviatedName,
    introductionTexts: overlayData.introductionTexts.map {
        var item = $0
        item.displayTime = nil
        return item
    },
    elementScores: overlayData.elementScores.map {
        var item = $0
        item.displayTime = nil
        return item
    })
