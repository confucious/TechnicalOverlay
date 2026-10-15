//
//  ProtocolDetailLinkTests.swift
//  ProtocolParserTests
//
//  Locating the judge-detail link on a leaderboard page
//  (`docs/architecture/protocol-parser.md` §2.1, §7.2).
//

import Foundation
import Testing
@testable import ProtocolParser

@Suite("Judge-detail link")
struct ProtocolDetailLinkTests {
    private let leaderboard034 = URL(
        string: "https://ijs.usfigureskating.org/leaderboard/results/2026/36683/CAT022SEG034.html")!
    private let leaderboard033 = URL(
        string: "https://ijs.usfigureskating.org/leaderboard/results/2026/36683/CAT022SEG033.html")!

    @Test("the link resolves against the leaderboard page's directory")
    func resolvesAgainstBase() throws {
        let link = try ProtocolHTMLParser.judgeDetailLink(
            in: try Fixture.html("CAT022SEG034.html"), relativeTo: leaderboard034)
        #expect(link.absoluteString
            == "https://ijs.usfigureskating.org/leaderboard/results/2026/36683/SEGM034.html")
    }

    @Test("the sibling segment's leaderboard link is not mistaken for the detail link")
    func doesNotPickSiblingSegment() throws {
        let link = try ProtocolHTMLParser.judgeDetailLink(
            in: try Fixture.html("CAT022SEG033.html"), relativeTo: leaderboard033)
        // The page also links to CAT022SEG033.html (itself) and CAT022SEG034.html (its sibling).
        #expect(link.lastPathComponent == "SEGM033.html")
    }

    @Test("a leaderboard page without the link reports it as missing")
    func missingLink() throws {
        #expect(throws: ProtocolParserError.detailLinkMissing) {
            _ = try ProtocolHTMLParser.judgeDetailLink(
                in: try Fixture.html("Synthetic-NoDetailLink.html"), relativeTo: leaderboard034)
        }
    }

    @Test("a relative link with no base cannot be resolved")
    func relativeLinkWithoutBase() throws {
        #expect(throws: ProtocolParserError.relativeLinkWithoutBaseURL) {
            _ = try ProtocolHTMLParser.judgeDetailLink(
                in: try Fixture.html("CAT022SEG034.html"), relativeTo: nil)
        }
    }

    @Test("an unquoted href attribute is read")
    func unquotedAttribute() throws {
        let link = try ProtocolHTMLParser.judgeDetailLink(
            in: try Fixture.html("CAT022SEG034.html"), relativeTo: leaderboard034)
        #expect(link.lastPathComponent == "SEGM034.html")
    }
}
