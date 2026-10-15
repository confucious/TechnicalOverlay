//
//  ProtocolImporterTests.swift
//  ProtocolParserTests
//
//  The orchestrator and the fetching seam (`docs/architecture/protocol-parser.md` §7.3).
//  No test here touches the network: `ProtocolFetching` is faked with fixture text.
//

import Foundation
import Testing
@testable import ProtocolParser

/// Returns fixture text for known URLs and records what was asked for, in order.
actor RecordingFetcher: ProtocolFetching {
    private let pages: [URL: String]
    private let failures: [URL: ProtocolParserError]
    private(set) var requested: [URL] = []

    init(pages: [URL: String] = [:], failures: [URL: ProtocolParserError] = [:]) {
        self.pages = pages
        self.failures = failures
    }

    func fetch(_ url: URL) async throws -> String {
        requested.append(url)
        if let failure = failures[url] { throw failure }
        guard let page = pages[url] else { throw ProtocolParserError.fetchFailed(statusCode: 404) }
        return page
    }
}

@Suite("Importing a skater")
struct ProtocolImporterTests {
    private let leaderboard = URL(
        string: "https://ijs.usfigureskating.org/leaderboard/results/2026/36683/CAT022SEG034.html")!
    private let detail = URL(
        string: "https://ijs.usfigureskating.org/leaderboard/results/2026/36683/SEGM034.html")!

    private func fetcher() async throws -> RecordingFetcher {
        RecordingFetcher(pages: [
            leaderboard: try Fixture.html("CAT022SEG034.html"),
            detail: try Fixture.html("SEGM034.html"),
        ])
    }

    @Test("a leaderboard URL is followed to the segment detail page and parsed")
    func followsTheLink() async throws {
        let fetcher = try await fetcher()
        let skater = try await ProtocolImporter(fetcher: fetcher).skater(named: "Milo Yeon", at: leaderboard)
        #expect(skater.name == "Milo Yeon, SC of Boston")
        #expect(skater.elements.count == 9)
        #expect(await fetcher.requested == [leaderboard, detail])
    }

    @Test("a detail-page URL is parsed without any further fetch")
    func parsesDetailPageDirectly() async throws {
        let fetcher = try await fetcher()
        let skater = try await ProtocolImporter(fetcher: fetcher).skater(named: "Milo Yeon", at: detail)
        #expect(skater.namePart == "Milo Yeon")
        #expect(await fetcher.requested == [detail])
    }

    @Test("a leaderboard page with no judge-detail link is an error, not a fallback")
    func missingLinkIsAnError() async throws {
        let page = URL(string: "https://example.test/CAT022SEG034.html")!
        let fetcher = RecordingFetcher(pages: [page: try Fixture.html("Synthetic-NoDetailLink.html")])
        await #expect(throws: ProtocolParserError.detailLinkMissing) {
            _ = try await ProtocolImporter(fetcher: fetcher).skater(named: "Milo Yeon", at: page)
        }
    }

    @Test("a page that is neither kind is rejected")
    func unrecognisedPage() async throws {
        let page = URL(string: "https://example.test/index.asp")!
        let fetcher = RecordingFetcher(pages: [page: "<html><body><p>not a protocol</p></body></html>"])
        await #expect(throws: ProtocolParserError.unrecognizedPage) {
            _ = try await ProtocolImporter(fetcher: fetcher).skater(named: "Milo Yeon", at: page)
        }
    }

    @Test("a download failure is reported")
    func downloadFailure() async throws {
        let page = URL(string: "https://example.test/CAT022SEG034.html")!
        let fetcher = RecordingFetcher(failures: [page: .fetchFailed(statusCode: 503)])
        await #expect(throws: ProtocolParserError.fetchFailed(statusCode: 503)) {
            _ = try await ProtocolImporter(fetcher: fetcher).skater(named: "Milo Yeon", at: page)
        }
    }

    @Test("page content supplied directly is parsed without fetching")
    func suppliedHTML() async throws {
        let importer = ProtocolImporter(fetcher: RecordingFetcher())
        let skater = try await importer.skater(
            named: "Milo Yeon", inHTML: try Fixture.html("SEGM034.html"))
        #expect(skater.elements.count == 9)
    }

    @Test("supplied leaderboard content still follows its link, resolved against the page URL")
    func suppliedLeaderboardHTML() async throws {
        let fetcher = try await fetcher()
        let importer = ProtocolImporter(fetcher: fetcher)
        let skater = try await importer.skater(
            named: "Milo Yeon", inHTML: try Fixture.html("CAT022SEG034.html"), baseURL: leaderboard)
        #expect(skater.namePart == "Milo Yeon")
        #expect(await fetcher.requested == [detail])
    }

    @Test("supplied leaderboard content with no page URL cannot resolve its relative link")
    func suppliedLeaderboardHTMLWithoutBase() async throws {
        let importer = ProtocolImporter(fetcher: try await fetcher())
        await #expect(throws: ProtocolParserError.relativeLinkWithoutBaseURL) {
            _ = try await importer.skater(
                named: "Milo Yeon", inHTML: try Fixture.html("CAT022SEG034.html"))
        }
    }

    @Test("pages are decoded as UTF-8 first, then ISO-8859-1")
    func bodyDecoding() {
        #expect(URLSessionProtocolFetcher.decode(Data("Milo".utf8)) == "Milo")
        // 0xD8 is "Ø" in ISO-8859-1 and invalid on its own in UTF-8.
        #expect(URLSessionProtocolFetcher.decode(Data([0x4D, 0x69, 0xD8])) == "MiØ")
        #expect(URLSessionProtocolFetcher.decode(Data()) == "")
    }
}
