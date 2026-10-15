//
//  ProtocolSkaterSelectionTests.swift
//  ProtocolParserTests
//
//  Isolating one skater by name (`docs/architecture/protocol-parser.md` §6).
//

import Foundation
import Testing
@testable import ProtocolParser

@Suite("Skater selection")
struct ProtocolSkaterSelectionTests {
    private func segment(_ name: String = "SEGM034.html") throws -> ProtocolSegment {
        try ProtocolHTMLParser.parseSegment(html: try Fixture.html(name))
    }

    @Test("a skater is found by name")
    func findsByName() throws {
        let skater = try ProtocolHTMLParser.skater(named: "Milo Yeon", in: try segment())
        #expect(skater.name == "Milo Yeon, SC of Boston")
        #expect(skater.elements.count == 9)
    }

    @Test("the club-qualified name from the page also matches")
    func findsByQualifiedName() throws {
        let skater = try ProtocolHTMLParser.skater(named: "Milo Yeon, SC of Boston", in: try segment())
        #expect(skater.namePart == "Milo Yeon")
    }

    @Test("case and extra whitespace do not matter")
    func normalisesInput() throws {
        #expect(try ProtocolHTMLParser.skater(named: "  milo   yeon ", in: try segment()).namePart == "Milo Yeon")
    }

    @Test("apostrophes do not matter, because the site drops them itself")
    func ignoresPunctuation() throws {
        // The page prints "Lianna OGrady, Skokie Valley SC".
        let skater = try ProtocolHTMLParser.skater(named: "Lianna O'Grady", in: try segment("SEGM021.html"))
        #expect(skater.namePart == "Lianna OGrady")
    }

    @Test("an unknown name reports the names that are available")
    func unknownName() throws {
        do {
            _ = try ProtocolHTMLParser.skater(named: "Nobody Here", in: try segment())
            Issue.record("expected .skaterNotFound")
        } catch let error as ProtocolParserError {
            guard case .skaterNotFound(let name, let available) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
            #expect(name == "Nobody Here")
            #expect(available.count == 17)
            #expect(available.first == "Milo Yeon, SC of Boston")
        }
    }

    @Test("two skaters with the same name are reported as ambiguous")
    func ambiguousName() throws {
        let twin = ProtocolSkater(name: "Milo Yeon, SC of Boston", elements: [])
        let other = ProtocolSkater(name: "Milo Yeon, Another Club", elements: [])
        let segment = ProtocolSegment(eventName: "E", categorySegment: "S", skaters: [twin, other])
        #expect(throws: ProtocolParserError.skaterAmbiguous(name: "Milo Yeon",
                                                            matches: [twin.name, other.name])) {
            _ = try ProtocolHTMLParser.skater(named: "Milo Yeon", in: segment)
        }
    }

    @Test("the club disambiguates two skaters of the same name")
    func clubDisambiguates() throws {
        let twin = ProtocolSkater(name: "Milo Yeon, SC of Boston", elements: [])
        let other = ProtocolSkater(name: "Milo Yeon, Another Club", elements: [])
        let segment = ProtocolSegment(eventName: "E", categorySegment: "S", skaters: [twin, other])
        let skater = try ProtocolHTMLParser.skater(named: "Milo Yeon, Another Club", in: segment)
        #expect(skater.club == "Another Club")
    }

    @Test("a name that only shares a prefix is not a match")
    func noPrefixMatching() throws {
        #expect(throws: ProtocolParserError.self) {
            _ = try ProtocolHTMLParser.skater(named: "Milo", in: try segment())
        }
    }
}
