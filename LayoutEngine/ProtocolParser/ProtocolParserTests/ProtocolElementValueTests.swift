//
//  ProtocolElementValueTests.swift
//  ProtocolParserTests
//
//  Element values: hundredths conversion, the source's own arithmetic, entity decoding and the
//  optional/zero columns (`docs/architecture/protocol-parser.md` §5, §4.2, §4.6).
//

import Foundation
import Testing
@testable import ProtocolParser

@Suite("Element values")
struct ProtocolElementValueTests {

    @Test("the reference skater's nine elements, value for value")
    func referenceSkaterValues() throws {
        let milo = try #require(try ProtocolHTMLParser.parseSegment(html: try Fixture.html("SEGM034.html"))
            .skaters.first { $0.namePart == "Milo Yeon" })

        // #, abbreviation, base, GOE, bonus, panel — all in hundredths (§5.2).
        let expected: [(String, Int, Int, Int, Int)] = [
            ("2Lz", 210, 42, 0, 252),
            ("3Tb1+2T", 550, 25, 100, 675),
            ("3Sb1+1A+2Lo+SEQ", 710, -26, 100, 784),
            ("CCoSp4", 420, 42, 0, 462),
            ("3T", 462, 84, 0, 546),
            ("3S", 473, 43, 0, 516),
            ("2A", 363, 59, 0, 422),
            ("StSq2+kpYYNN", 270, 38, 0, 308),
            ("FSSp3", 310, 50, 0, 360),
        ]
        #expect(milo.elements.count == expected.count)
        for (element, want) in zip(milo.elements, expected) {
            #expect(element.abbreviation == want.0)
            #expect(element.baseValue == want.1)
            #expect(element.goeValue == want.2)
            #expect(element.bonusValue == want.3)
            #expect(element.panelScore == want.4)
        }
    }

    @Test("a negative GOE below one point keeps its sign")
    func negativeFractionalGOE() throws {
        // -0.26 must not become +26: the sign is not carried by the whole-number component (§5.1).
        let milo = try #require(try ProtocolHTMLParser.parseSegment(html: try Fixture.html("SEGM034.html"))
            .skaters.first { $0.namePart == "Milo Yeon" })
        let sequenced = try #require(milo.elements.first { $0.abbreviation == "3Sb1+1A+2Lo+SEQ" })
        #expect(sequenced.goeValue == -26)
    }

    @Test("a half-point bonus reads as fifty hundredths")
    func halfPointBonus() throws {
        let all = try Fixture.detailPages.flatMap { try ProtocolHTMLParser.parseSegment(html: try Fixture.html($0)).skaters }
        let bonuses = Set(all.flatMap { $0.elements.map(\.bonusValue) })
        #expect(bonuses.isSubset(of: [0, 50, 100]), "unexpected bonus values: \(bonuses.sorted())")
        #expect(bonuses.contains(50), "the 0.50 bonus column should appear somewhere")
    }

    @Test("the source's own total equals base + GOE + bonus on every row of every segment")
    func totalIsAnInvariant() throws {
        var rows = 0
        for name in Fixture.detailPages {
            let segment = try ProtocolHTMLParser.parseSegment(html: try Fixture.html(name))
            for skater in segment.skaters {
                for element in skater.elements {
                    rows += 1
                    #expect(element.baseValue + element.goeValue + element.bonusValue == element.panelScore,
                            "\(name) \(skater.name) #\(element.index) \(element.abbreviation)")
                }
            }
        }
        // The eleven committed detail pages (the ten reference segments plus SEGM033, the sibling
        // used by the link test): 825 element rows, none of which may break the invariant.
        #expect(rows == 825)
    }

    @Test("entities in the abbreviation are decoded")
    func entityDecoding() throws {
        let skaters = try ProtocolHTMLParser.parseSegment(html: try Fixture.html("SEGM034.html")).skaters
        let abbreviations = Set(skaters.flatMap { $0.elements.map(\.abbreviation) })
        #expect(abbreviations.contains("2Lz<<"))     // written as 2Lz&lt;&lt;
        #expect(abbreviations.contains("3Lz<b1"))    // written as 3Lz&lt;b1
    }

    @Test("a row missing its Base Value fails with the skater and element number")
    func malformedRow() throws {
        do {
            _ = try ProtocolHTMLParser.parseSegment(html: try Fixture.html("Synthetic-MalformedRow.html"))
            Issue.record("expected .malformedElementRow")
        } catch let error as ProtocolParserError {
            guard case .malformedElementRow(let skater, let index, _) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
            #expect(skater == "Milo Yeon, SC of Boston")
            #expect(index == "2")
        }
    }
}
