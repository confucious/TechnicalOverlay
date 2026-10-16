//
//  ProtocolImportTests.swift
//  TechnicalOverlayTests
//
//  The app-side merge of an imported protocol (`docs/architecture/protocol-parser.md` §8.1).
//

import Foundation
import ProtocolParser
import Testing
@testable import TechnicalOverlay

@Suite("Protocol import merge")
struct ProtocolImportTests {

    private func existing(
        _ name: String, base: Int = 100, goe: Int = 10, bonus: Int = 0, at time: TimeInterval? = nil
    ) -> ElementData {
        ElementData(name: name, baseValue: base, goeValue: goe, bonusValue: bonus, displayTime: time)
    }

    private func parsed(
        _ index: Int, _ abbreviation: String, base: Int, goe: Int, bonus: Int = 0
    ) -> ProtocolElement {
        ProtocolElement(
            index: index,
            abbreviation: abbreviation,
            baseValue: base,
            goeValue: goe,
            bonusValue: bonus,
            panelScore: base + goe + bonus)
    }

    @Test("values at an index are replaced and the existing displayTime is kept")
    func replacesValuesAndKeepsTiming() {
        let data = OverlayData(elementScores: [
            existing("Typed By Hand", base: 100, goe: 10, at: 12.5),
        ])

        data.merge(ProtocolSkater(
            name: "Milo Yeon, SC of Boston",
            elements: [parsed(1, "2Lz", base: 210, goe: 42)]))

        #expect(data.elementScores.count == 1)
        #expect(data.elementScores[0].name == "2 Lutz")          // the display name, not "2Lz"
        #expect(data.elementScores[0].baseValue == 210)
        #expect(data.elementScores[0].goeValue == 42)
        #expect(data.elementScores[0].displayTime == 12.5)
    }

    @Test("an untimed existing entry stays untimed")
    func keepsNilTimingNil() {
        let data = OverlayData(elementScores: [existing("Typed By Hand", at: nil)])

        data.merge(ProtocolSkater(name: "Skater", elements: [parsed(1, "3T", base: 462, goe: 84)]))

        #expect(data.elementScores[0].displayTime == nil)
        #expect(data.elementScores[0].name == "3 Toeloop")
    }

    @Test("elements the protocol adds beyond the current data are appended, untimed")
    func appendsSurplusProtocolElements() {
        let data = OverlayData(elementScores: [existing("2Lz", at: 3.0)])

        data.merge(ProtocolSkater(name: "Skater", elements: [
            parsed(1, "2Lz", base: 210, goe: 42),
            parsed(2, "3Tb1+2T", base: 550, goe: 25, bonus: 100),
        ]))

        #expect(data.elementScores.count == 2)
        #expect(data.elementScores[0].displayTime == 3.0)
        #expect(data.elementScores[1].name == "3 Toeloop + 2 Toeloop")   // bonus marker dropped
        #expect(data.elementScores[1].baseValue == 550)
        #expect(data.elementScores[1].bonusValue == 100)
        #expect(data.elementScores[1].displayTime == nil)
    }

    @Test("entries beyond the protocol's element count are left untouched")
    func leavesSurplusExistingEntriesAlone() {
        let data = OverlayData(elementScores: [
            existing("2Lz", base: 100, goe: 10, at: 3.0),
            existing("Left Alone", base: 999, goe: -50, bonus: 100, at: 7.25),
        ])

        data.merge(ProtocolSkater(name: "Skater", elements: [parsed(1, "2Lz", base: 210, goe: 42)]))

        #expect(data.elementScores.count == 2)
        #expect(data.elementScores[0].baseValue == 210)
        let untouched = data.elementScores[1]
        #expect(untouched.name == "Left Alone")
        #expect(untouched.baseValue == 999)
        #expect(untouched.goeValue == -50)
        #expect(untouched.bonusValue == 100)
        #expect(untouched.displayTime == 7.25)
    }

    @Test("importing into empty data adds every element, untimed")
    func importsIntoEmptyData() {
        let data = OverlayData()

        data.merge(ProtocolSkater(name: "Skater", elements: [
            parsed(1, "2Lz", base: 210, goe: 42),
            parsed(2, "3S", base: 473, goe: 43),
        ]))

        #expect(data.elementScores.map(\.name) == ["2 Lutz", "3 Salchow"])
        #expect(data.elementScores.allSatisfy { $0.displayTime == nil })
    }

    @Test("a translator can be handed in — the identity default keeps the abbreviation")
    func injectedIdentityTranslator() {
        // The seam the spec specifies: the app uses the expander by default, and a caller that wants
        // the raw code (or a different naming policy) supplies its own translator.
        struct Verbatim: ElementNameTranslating {}

        let data = OverlayData(elementScores: [existing("Typed By Hand", at: 3.0)])
        data.merge(
            ProtocolSkater(name: "Skater", elements: [
                parsed(1, "3Tb1+2T", base: 550, goe: 25, bonus: 100),
                parsed(2, "2A", base: 363, goe: 59),
            ]),
            translator: Verbatim())

        #expect(data.elementScores.map(\.name) == ["3Tb1+2T", "2A"])
        #expect(data.elementScores[0].displayTime == 3.0)       // timing still preserved
    }
}
