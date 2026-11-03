//
//  ProtocolImporter.swift
//  ProtocolParser
//
//  The orchestrator (`docs/architecture/protocol-parser.md` §7.3): classify the document, follow the
//  judge-detail link when that is what we were given, parse it, isolate one skater.
//

import Foundation

public struct ProtocolImporter: Sendable {
    private let fetcher: ProtocolFetching

    public nonisolated init(fetcher: ProtocolFetching = URLSessionProtocolFetcher()) {
        self.fetcher = fetcher
    }

    /// Fetches `url` — a leaderboard page, a detail page, or a protocol PDF — and returns one
    /// skater's protocol.
    public nonisolated func skater(named name: String, at url: URL) async throws -> ProtocolSkater {
        try await skater(named: name, in: try await fetcher.fetchData(url), baseURL: url)
    }

    /// The same, for content supplied directly (paste/file/test). `baseURL` is the page's URL,
    /// needed to resolve a relative judge-detail link; it is `async` because a leaderboard page must
    /// still fetch its detail page, while a detail page or a PDF needs no network at all.
    ///
    /// The body decides which parser runs — an ISU FS Manager PDF is recognised by its header, not
    /// by the address it was pasted from (`protocol-parser.md` §2.3).
    public nonisolated func skater(
        named name: String,
        in data: Data,
        baseURL: URL? = nil
    ) async throws -> ProtocolSkater {
        if ProtocolPDFParser.isPDF(data) {
            return try ProtocolPDFParser.parseSegment(data: data).skater(named: name)
        }
        guard let html = ProtocolText.decode(data) else {
            throw ProtocolParserError.undecodableBody
        }
        return try await skater(named: name, inHTML: html, baseURL: baseURL)
    }

    /// The same, for HTML supplied as text.
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
            let detailData = try await fetcher.fetchData(detailURL)

            // A judge-detail link may point at a PDF; everything after this point is the same.
            if ProtocolPDFParser.isPDF(detailData) {
                return try ProtocolPDFParser.parseSegment(data: detailData).skater(named: name)
            }
            guard let detailHTML = ProtocolText.decode(detailData),
                  ProtocolHTMLParser.pageKind(of: detailHTML) == .segmentDetail else {
                throw ProtocolParserError.unrecognizedPage
            }
            return try ProtocolHTMLParser.skater(
                named: name, in: try ProtocolHTMLParser.parseSegment(html: detailHTML))
        }
    }
}
