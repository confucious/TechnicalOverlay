//
//  ProtocolHTMLParserTests.swift
//  ProtocolParserTests
//
//  Behaviour tests for the pure parsing surface (`docs/architecture/protocol-parser.md` §7.2).
//

import Foundation
import Testing
@testable import ProtocolParser

@Suite("Page classification")
struct ProtocolPageKindTests {

    @Test("a leaderboard page is recognised by its judge-detail link")
    func leaderboardPage() throws {
        let html = try Fixture.html("CAT022SEG034.html")
        #expect(ProtocolHTMLParser.pageKind(of: html) == .leaderboard)
    }

    @Test("a segment detail page is recognised by its element tables")
    func detailPage() throws {
        let html = try Fixture.html("SEGM034.html")
        #expect(ProtocolHTMLParser.pageKind(of: html) == .segmentDetail)
    }

    @Test("every fixture classifies as the kind it is")
    func everyFixture() throws {
        for name in Fixture.detailPages {
            #expect(ProtocolHTMLParser.pageKind(of: try Fixture.html(name)) == .segmentDetail,
                    "\(name) should be a detail page")
        }
        for name in Fixture.leaderboardPages {
            #expect(ProtocolHTMLParser.pageKind(of: try Fixture.html(name)) == .leaderboard,
                    "\(name) should be a leaderboard page")
        }
    }

    @Test("a page that is neither kind is not classified")
    func unrecognisedPages() {
        #expect(ProtocolHTMLParser.pageKind(of: "") == nil)
        #expect(ProtocolHTMLParser.pageKind(of: "<html><body><p>hi</p></body></html>") == nil)
        #expect(ProtocolHTMLParser.pageKind(of: "The resource you are looking for has been removed") == nil)
    }
}
