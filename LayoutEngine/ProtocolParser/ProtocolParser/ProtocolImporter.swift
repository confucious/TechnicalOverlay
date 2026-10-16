//
//  ProtocolImporter.swift
//  ProtocolParser
//
//  The orchestrator (`docs/architecture/protocol-parser.md` §7.3): classify the page, follow the
//  judge-detail link when that is what we were given, parse the detail page, isolate one skater.
//

import Foundation

public struct ProtocolImporter: Sendable {
    private let fetcher: ProtocolFetching

    public nonisolated init(fetcher: ProtocolFetching = URLSessionProtocolFetcher()) {
        self.fetcher = fetcher
    }

    /// Fetches `url` — a leaderboard page or a detail page — and returns one skater's protocol.
    public nonisolated func skater(named name: String, at url: URL) async throws -> ProtocolSkater {
        try await skater(named: name, inHTML: try await fetcher.fetch(url), baseURL: url)
    }

    /// The same, for page content supplied directly (paste/file/test). `baseURL` is the page's URL,
    /// needed to resolve a relative judge-detail link; it is `async` because a leaderboard page must
    /// still fetch its detail page, while a detail page needs no network at all.
    public nonisolated func skater(
        named name: String,
        inHTML html: String,
        baseURL: URL? = nil
    ) async throws -> ProtocolSkater {
        guard let kind = ProtocolHTMLParser.pageKind(of: html) else {
            throw ProtocolParserError.unrecognizedPage
        }

        switch kind {
        case .segmentDetail:
            return try ProtocolHTMLParser.skater(
                named: name, in: try ProtocolHTMLParser.parseSegment(html: html))

        case .leaderboard:
            // The leaderboard page is used for nothing but locating the link (protocol-parser.md §10b).
            let detailURL = try ProtocolHTMLParser.judgeDetailLink(in: html, relativeTo: baseURL)
            let detailHTML = try await fetcher.fetch(detailURL)
            guard ProtocolHTMLParser.pageKind(of: detailHTML) == .segmentDetail else {
                throw ProtocolParserError.unrecognizedPage
            }
            return try ProtocolHTMLParser.skater(
                named: name, in: try ProtocolHTMLParser.parseSegment(html: detailHTML))
        }
    }
}
