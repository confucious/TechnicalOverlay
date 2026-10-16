//
//  ProtocolParser.swift
//  ProtocolParser
//
//  Created by Jerry Hsu on 10/12/25.
//

import Foundation

// ProtocolParser — imports a skater's executed elements from a published ijsLive competition
// protocol. See docs/architecture/protocol-parser.md for the specification this implements.

/// Every failure the module can report (`protocol-parser.md` §7.4).
/// Structural problems fail fast; only genuinely optional columns default.
public enum ProtocolParserError: Error, LocalizedError, Equatable {
    /// Not a results page this module understands (404 body, login page, another site).
    case unrecognizedPage
    /// A leaderboard page whose judge-detail link has not been published yet. The user retries
    /// later; no leaderboard-page data is used as a fallback (protocol-parser.md §10b).
    case detailLinkMissing
    case detailLinkAmbiguous(count: Int)
    /// A relative `href` with no base URL to resolve it against.
    case relativeLinkWithoutBaseURL
    case fetchFailed(statusCode: Int)
    case undecodableBody
    case skaterNotFound(name: String, available: [String])
    case skaterAmbiguous(name: String, matches: [String])
    /// A skater section with no element table following it.
    case elementTableMissing(skater: String)
    /// A row that is missing a required cell (`num`, `elem`, `bv` or `goe`).
    case malformedElementRow(skater: String, index: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unrecognizedPage:
            return "That page does not look like a competition protocol."
        case .detailLinkMissing:
            return "The judge detail scores have not been published for this segment yet."
        case .detailLinkAmbiguous(let count):
            return "Expected one judge-detail link, found \(count)."
        case .relativeLinkWithoutBaseURL:
            return "The judge-detail link is relative and there is no page URL to resolve it against."
        case .fetchFailed(let statusCode):
            return "The protocol page could not be downloaded (HTTP \(statusCode))."
        case .undecodableBody:
            return "The protocol page could not be decoded as text."
        case .skaterNotFound(let name, let available):
            return "No skater named \(name) on this page. Available: \(available.joined(separator: ", "))"
        case .skaterAmbiguous(let name, let matches):
            return "\(name) matches more than one skater: \(matches.joined(separator: ", "))"
        case .elementTableMissing(let skater):
            return "No element table found for \(skater)."
        case .malformedElementRow(let skater, let index, let reason):
            return "Element \(index) for \(skater) could not be read: \(reason)."
        }
    }
}
