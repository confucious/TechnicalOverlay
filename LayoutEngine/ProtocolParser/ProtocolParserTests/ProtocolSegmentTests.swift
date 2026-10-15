//
//  ProtocolSegmentTests.swift
//  ProtocolParserTests
//
//  Reading a segment detail page into skaters and elements
//  (`docs/architecture/protocol-parser.md` §4.4–§4.6).
//

import Foundation
import Testing
@testable import ProtocolParser

@Suite("Segment parsing")
struct ProtocolSegmentTests {
    private func segment(_ name: String = "SEGM034.html") throws -> ProtocolSegment {
        try ProtocolHTMLParser.parseSegment(html: try Fixture.html(name))
    }

    @Test("the segment identifies its event and category")
    func identifiesSegment() throws {
        let segment = try segment()
        #expect(segment.eventName == "2026 Boston Open")
        #expect(segment.categorySegment == "101_109 Champ Intermediate Men / Free Skate")
    }

    @Test("every skater of the segment is found, in rank order")
    func findsEverySkater() throws {
        let segment = try segment()
        #expect(segment.skaters.count == 17)
        #expect(segment.skaters.first?.name == "Milo Yeon, SC of Boston")
        #expect(segment.skaters.last?.name == "Jackson Patterson, Boise FSC")
    }

    @Test("a skater's name and club are split at the first comma")
    func splitsNameAndClub() throws {
        let milo = try #require(try segment().skaters.first)
        #expect(milo.namePart == "Milo Yeon")
        #expect(milo.club == "SC of Boston")
    }

    @Test("each skater's elements are in protocol order, indexed 1…n")
    func elementsAreContiguous() throws {
        for skater in try segment().skaters {
            #expect(skater.elements.map(\.index) == Array(1...skater.elements.count),
                    "\(skater.name) has a gap in its element numbering")
        }
        #expect(try segment().skaters.reduce(0) { $0 + $1.elements.count } == 153)
    }

    @Test("the abbreviation is read verbatim, with entities decoded")
    func readsAbbreviations() throws {
        let milo = try #require(try segment().skaters.first)
        #expect(milo.elements.map(\.abbreviation) == [
            "2Lz", "3Tb1+2T", "3Sb1+1A+2Lo+SEQ", "CCoSp4", "3T", "3S", "2A", "StSq2+kpYYNN", "FSSp3",
        ])
    }

    @Test("elements with no credited value are still imported")
    func keepsZeroValueElements() throws {
        // Jackson Patterson's last two elements were attempted but not credited.
        let last = try #require(try segment().skaters.last)
        let zeros = last.elements.filter { $0.baseValue == 0 && $0.goeValue == 0 }
        #expect(zeros.count == 2)
        #expect(zeros.contains { $0.abbreviation == "CoSp" })
    }

    @Test("a pairs segment parses to the same schema")
    func pairsSegment() throws {
        let pairs = try segment("SEGM030.html")
        // Pairs names carry no club: "Partner / Partner".
        #expect(pairs.skaters.map(\.name) == ["Sydney Cooke / Matthew Kennedy",
                                              "Amelie Wilson-Bivera / William Church"])
        #expect(pairs.skaters.first?.elements.contains { $0.abbreviation == "3Tw3" } == true)
        #expect(pairs.skaters.first?.club == nil)
    }
}
