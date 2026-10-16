//
//  ElementNameExpanderTests.swift
//  ProtocolParserTests
//
//  The singles expansion rules, the frozen worked examples and the whole-fixture sweep
//  (`docs/architecture/abbreviation-expansion.md` §4, §5, §9).
//

import Foundation
import Testing
@testable import ProtocolParser

@Suite("Element name expansion")
struct ElementNameExpanderTests {

    private let expander = ElementNameExpander()

    private func expanded(_ abbreviation: String) -> String {
        expander.displayName(for: abbreviation)
    }

    // MARK: - Jumps

    @Test("a jump carries its revolution count and its name")
    func jumpsAndNumbers() {
        #expect(expanded("3S") == "3 Salchow")
        #expect(expanded("2Lz") == "2 Lutz")
        #expect(expanded("1A") == "1 Axel")
        #expect(expanded("4T") == "4 Toeloop")
        #expect(expanded("1F") == "1 Flip")
        #expect(expanded("2Lo") == "2 Loop")
    }

    @Test("Euler is never numbered")
    func euler() {
        #expect(expanded("Eu") == "Euler")
        #expect(expanded("2A+Eu+2F") == "2 Axel + Euler + 2 Flip")
    }

    @Test("a jump the protocol printed without a revolution count keeps it that way")
    func numberlessJumps() {
        #expect(expanded("A") == "Axel")
        #expect(expanded("T") == "Toeloop")
        #expect(expanded("A*") == "Axel (Invalid)")
        #expect(expanded("Lo*") == "Loop (Invalid)")
    }

    @Test("the parts of a combination are joined with a spaced plus")
    func separator() {
        #expect(expanded("3Tb1+2T") == "3 Toeloop + 2 Toeloop")
        #expect(expanded("3S+1A+2T+SEQ") == "3 Salchow + 1 Axel + 2 Toeloop + SEQ")
    }

    // MARK: - Markers

    @Test("the bonus marker is ignored wherever it sits")
    func bonusMarker() {
        #expect(expanded("3Tb1") == "3 Toeloop")
        #expect(expanded("3Tb1+2T") == "3 Toeloop + 2 Toeloop")
        #expect(expanded("3Lz<b1") == "3 Lutz")           // bonus after the marker
        #expect(expanded("3S<b1") == "3 Salchow")
    }

    @Test("under-rotation, downgrade and edge markers are ignored")
    func markers() {
        #expect(expanded("2A<") == "2 Axel")
        #expect(expanded("3Lo<<") == "3 Loop")
        #expect(expanded("2Lz!") == "2 Lutz")
        #expect(expanded("2Lze") == "2 Lutz")
        #expect(expanded("3Lzq") == "3 Lutz")
        #expect(expanded("2Lz!<") == "2 Lutz")
        #expect(expanded("2Lo+2Tq") == "2 Loop + 2 Toeloop")
    }

    @Test("an asterisk marks the token it belongs to invalid")
    func invalidFlag() {
        #expect(expanded("1Lz*") == "1 Lutz (Invalid)")
        #expect(expanded("1Lz*+COMBO") == "1 Lutz (Invalid) + COMBO")
        #expect(expanded("3Sb1+COMBO+1T*") == "3 Salchow + COMBO + 1 Toeloop (Invalid)")
        #expect(expanded("A*") == "Axel (Invalid)")
        // Both tokens flagged, each on its own part.
        #expect(expanded("2Lz+SEQ+1A*+2Lo*") == "2 Lutz + SEQ + 1 Axel (Invalid) + 2 Loop (Invalid)")
    }

    // MARK: - Call tokens

    @Test("the call tokens SEQ, COMBO and REP are shown as published")
    func callTokens() {
        #expect(expanded("2Lz+COMBO") == "2 Lutz + COMBO")
        #expect(expanded("3Lo+REP") == "3 Loop + REP")
        #expect(expanded("2Fq+REP") == "2 Flip + REP")
        #expect(expanded("T+COMBO+2T*+REP") == "Toeloop + COMBO + 2 Toeloop (Invalid) + REP")
        #expect(expanded("SEQ") == "SEQ")
        #expect(expanded("COMBO") == "COMBO")
        #expect(expanded("REP") == "REP")
        // A call token keeps its place rather than moving to the end.
        #expect(expanded("2Lz+SEQ+1A+2Lo") == "2 Lutz + SEQ + 1 Axel + 2 Loop")
    }

    // MARK: - Step sequences and choreographic elements

    @Test("a step sequence is expanded with its level")
    func stepSequences() {
        #expect(expanded("StSqB+kpNNNN") == "Step Sequence B")
        #expect(expanded("StSq1+kpYNNN") == "Step Sequence 1")
        #expect(expanded("StSq2+kpYYNN") == "Step Sequence 2")
        #expect(expanded("StSq3+kpYNYY") == "Step Sequence 3")
        #expect(expanded("StSq4+kpYYYY") == "Step Sequence 4")
        #expect(expanded("StSq4b0.5+kpYYYY") == "Step Sequence 4")   // bonus ignored, no dangling +
    }

    @Test("the choreographic codes keep their digit; only pChSq's prefix is dropped")
    func choreographic() {
        #expect(expanded("ChSq1") == "Choreo Sequence 1")
        #expect(expanded("ChSp1") == "Choreo Spin 1")
        #expect(expanded("pChSq1") == "Choreo Sequence 1")
    }

    // MARK: - Spins

    @Test("a spin is expanded with its level and its reduced-value flag")
    func spins() {
        #expect(expanded("CCoSp4") == "Change Combo Spin 4")
        // The reduced-value V is separated from the level by a space.
        #expect(expanded("CCoSp1V") == "Change Combo Spin 1 V")
        #expect(expanded("CCoSp2V") == "Change Combo Spin 2 V")
        #expect(expanded("CCoSpBV") == "Change Combo Spin B V")
        #expect(expanded("FCCoSp4") == "Flying Change Combo Spin 4")
        #expect(expanded("CSp2") == "Camel Spin 2")
        #expect(expanded("SSpB") == "Sit Spin B")
        #expect(expanded("FCSp3") == "Flying Camel Spin 3")
        #expect(expanded("CSSp4") == "Change Sit Spin 4")
        #expect(expanded("USp2") == "Upright Spin 2")
        #expect(expanded("FUSpB") == "Flying Upright Spin B")
    }

    @Test("a spin the panel called with no level gets the name alone")
    func spinsWithoutLevel() {
        #expect(expanded("CoSp") == "Combo Spin")
        #expect(expanded("CCSp") == "Change Camel Spin")
        #expect(expanded("FSSp") == "Flying Sit Spin")
        #expect(expanded("CCoSp") == "Change Combo Spin")
        #expect(expanded("CSSp") == "Change Sit Spin")
        #expect(expanded("CoSpV") == "Combo Spin V")      // a V with no level still shows
    }

    @Test("the longest spin code wins, and a spin is not a jump")
    func longestSpinCode() {
        #expect(expanded("CCSp3") == "Change Camel Spin 3")
        #expect(expanded("FSSp3") == "Flying Sit Spin 3")
        #expect(expanded("SSp2") == "Sit Spin 2")
        #expect(expanded("FCSSp4") == "Flying Change Sit Spin 4")
    }

    // MARK: - Out of scope

    @Test("pairs codes pass through untouched")
    func pairsCodesVerbatim() throws {
        // Frozen examples from the pairs vocabulary (`protocol-parser.md` §9).
        #expect(expanded("3STh") == "3STh")
        #expect(expanded("1LoTh") == "1LoTh")
        #expect(expanded("3Tw3") == "3Tw3")
        #expect(expanded("2Tw4") == "2Tw4")
        #expect(expanded("5ALi4") == "5ALi4")
        #expect(expanded("1Li3") == "1Li3")
        #expect(expanded("1LiB") == "1LiB")
        #expect(expanded("BoDs2") == "BoDs2")
        #expect(expanded("FiDs3") == "FiDs3")
        #expect(expanded("ChPLi1") == "ChPLi1")
        #expect(expanded("ChPSp1") == "ChPSp1")
        #expect(expanded("PSp3") == "PSp3")
        #expect(expanded("PiF1") == "PiF1")

        // And the same holds for every such token on the committed pairs pages.
        var checked = 0
        for page in ["SEGM026.html", "SEGM028.html", "SEGM030.html", "SEGM031.html", "SEGM032.html"] {
            let segment = try ProtocolHTMLParser.parseSegment(html: try Fixture.html(page))
            for skater in segment.skaters {
                for element in skater.elements {
                    for token in element.abbreviation.components(separatedBy: "+") {
                        let isPairs = ["Th", "Tw", "Li", "Ds", "PSp", "PiF"].contains { token.contains($0) }
                        guard isPairs else { continue }
                        checked += 1
                        #expect(expanded(token) == token, "\(token) should pass through unchanged")
                    }
                }
            }
        }
        #expect(checked > 20, "expected the pairs fixtures to contribute pairs tokens, got \(checked)")
    }

    @Test("a translator that implements nothing returns the abbreviation unchanged")
    func identityDefault() {
        struct Untranslated: ElementNameTranslating {}
        let translator: ElementNameTranslating = Untranslated()
        #expect(translator.displayName(for: "3Tb1+2T") == "3Tb1+2T")
        #expect(translator.displayName(for: "StSq4b0.5+kpYYYY") == "StSq4b0.5+kpYYYY")
    }

    // MARK: - Fixture sweeps

    @Test("every row of the five singles fixtures is classified, with nothing passed through")
    func singlesSweep() throws {
        var rows = 0
        for page in Fixture.singlesDetailPages {
            let segment = try ProtocolHTMLParser.parseSegment(html: try Fixture.html(page))
            for skater in segment.skaters {
                for element in skater.elements {
                    rows += 1
                    let abbreviation = element.abbreviation
                    let parts = expanded(abbreviation).components(separatedBy: " + ")

                    // A token the rules do not know comes back verbatim
                    // (abbreviation-expansion.md §4.9), and no row on these pages may: the surviving
                    // parts must line up one-for-one with the tokens that are not dropped. Call
                    // tokens are the exception — a call token's expansion *is* itself.
                    let callTokens: Set<String> = ["SEQ", "COMBO", "REP"]
                    let survivors = abbreviation
                        .components(separatedBy: "+")
                        .filter { !$0.hasPrefix("kp") }
                    #expect(parts.count == survivors.count,
                            "\(page) #\(element.index) \(abbreviation) → \(parts)")
                    for part in parts where !callTokens.contains(part) {
                        #expect(!survivors.contains(part),
                                "verbatim passthrough: \(page) #\(element.index) \(abbreviation) → \(part)")
                    }
                }
            }
        }
        #expect(rows == 535, "the five singles pages hold 535 element rows")
    }

    @Test("no row on any committed page expands to something malformed")
    func everyPageStaysWellFormed() throws {
        var rows = 0
        for page in Fixture.detailPages {
            let segment = try ProtocolHTMLParser.parseSegment(html: try Fixture.html(page))
            for skater in segment.skaters {
                for element in skater.elements {
                    rows += 1
                    let name = expanded(element.abbreviation)
                    #expect(!name.isEmpty, "\(page) #\(element.index) \(element.abbreviation)")
                    #expect(!name.hasPrefix(" + ") && !name.hasSuffix(" + "))
                    #expect(!name.contains("+ +"))
                    #expect(!name.lowercased().contains("kp"))
                }
            }
        }
        #expect(rows == 825, "the eleven committed detail pages hold 825 element rows")
    }
}
