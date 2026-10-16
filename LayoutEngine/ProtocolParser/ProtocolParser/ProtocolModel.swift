//
//  ProtocolModel.swift
//  ProtocolParser
//
//  The module's value types (`docs/architecture/protocol-parser.md` §7.1). All scores are integer
//  hundredths, matching the app's `ElementData`.
//

import Foundation

/// Which of the two published page kinds a document is
/// (`protocol-parser.md` §2.1–§2.2).
public enum ProtocolPageKind: Sendable, Equatable {
    /// `CATnnnSEGnnn.html` — the results table; used only to locate the judge-detail link
    /// (protocol-parser.md §7.3).
    case leaderboard
    /// `SEGMnnn.html` — the static page that is actually parsed.
    case segmentDetail
}

/// One executed element. Identified by its raw abbreviation; the `info` column is never read
/// (protocol-parser.md §10a).
public struct ProtocolElement: Sendable, Equatable, Hashable {
    /// The protocol's own element number, 1-based and contiguous (protocol-parser.md §4.5).
    public let index: Int
    /// The abbreviation exactly as published, entity-decoded: `3Tb1+2T`, `2Lz<<`, `StSq2+kpYYNN`.
    public let abbreviation: String
    public let baseValue: Int
    public let goeValue: Int
    /// Bonus for a difficult element; `0` when the column is empty (protocol-parser.md §5.1).
    public let bonusValue: Int
    /// The page's own total column, kept for sanity checking only — never displayed
    /// (protocol-parser.md §5.2, §10e).
    public let panelScore: Int

    public init(
        index: Int,
        abbreviation: String,
        baseValue: Int,
        goeValue: Int,
        bonusValue: Int,
        panelScore: Int
    ) {
        self.index = index
        self.abbreviation = abbreviation
        self.baseValue = baseValue
        self.goeValue = goeValue
        self.bonusValue = bonusValue
        self.panelScore = panelScore
    }
}

/// One skater's section of a segment detail page.
public struct ProtocolSkater: Sendable, Equatable {
    /// The name cell verbatim, e.g. `Milo Yeon, SC of Boston` (pairs: `A / B`, with no club).
    public let name: String
    public let elements: [ProtocolElement]

    public init(name: String, elements: [ProtocolElement]) {
        self.name = name
        self.elements = elements
    }

    /// The skater, without the club: everything before the first comma.
    public var namePart: String {
        let parts = name.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? name
    }

    /// The club, when the protocol gives one — `nil` for names with no comma (pairs).
    public var club: String? {
        let parts = name.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count > 1 else { return nil }
        let club = parts[1].trimmingCharacters(in: .whitespaces)
        return club.isEmpty ? nil : club
    }
}

/// One segment's page: every skater of that segment, in rank order.
public struct ProtocolSegment: Sendable, Equatable {
    public let eventName: String
    public let categorySegment: String
    public let skaters: [ProtocolSkater]

    public init(eventName: String, categorySegment: String, skaters: [ProtocolSkater]) {
        self.eventName = eventName
        self.categorySegment = categorySegment
        self.skaters = skaters
    }
}
