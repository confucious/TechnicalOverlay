//
//  ProtocolHTMLParser.swift
//  ProtocolParser
//
//  The pure parsing surface: `String` in, values out, no I/O
//  (`docs/architecture/protocol-parser.md` §7.2). Marked `nonisolated` so it can be moved off the
//  main actor without restructuring — every target is MainActor-isolated by default
//  (`Project.swift` `baseSettings`).
//

import Foundation
import SwiftSoup

public enum ProtocolHTMLParser {

    /// Classifies a page, or returns `nil` when it is neither kind (a 404 body, a login page,
    /// some unrelated site).
    ///
    /// The judge-detail link is the surest leaderboard signal, but it is *absent exactly when* the
    /// organizer has not published judge details yet — the page is still a leaderboard page, and
    /// that absence is the `.detailLinkMissing` case (protocol-parser.md §10b). So the results table
    /// and the segment-links list count as leaderboard signals too.
    nonisolated public static func pageKind(of html: String) -> ProtocolPageKind? {
        guard let document = try? SwiftSoup.parse(html) else { return nil }

        let leaderboardSignals = ["li.judgeDetailRef", "table#catSegTable", "div.segLinks"]
        if leaderboardSignals.contains(where: { (try? document.select($0))?.isEmpty == false }) {
            return .leaderboard
        }
        guard let summaryTables = try? document.select("table.sum"), !summaryTables.isEmpty,
              let elementTables = try? document.select("table.elm"), !elementTables.isEmpty
        else { return nil }
        return .segmentDetail
    }

    /// The `<A>` inside `<LI class="judgeDetailRef">` — `"Judge detail scores"` — resolved against
    /// the page it was found on. Throws `.detailLinkMissing` when the organizer has not published
    /// judge details yet, and `.relativeLinkWithoutBaseURL` when a relative link has no base.
    nonisolated public static func judgeDetailLink(in html: String, relativeTo base: URL?) throws -> URL {
        guard let document = try? SwiftSoup.parse(html) else { throw ProtocolParserError.unrecognizedPage }

        let anchors = (try? document.select("li.judgeDetailRef a")) ?? Elements()
        if anchors.count > 1 { throw ProtocolParserError.detailLinkAmbiguous(count: anchors.count) }
        guard let anchor = anchors.first(),
              let href = (try? anchor.attr("href"))?.trimmingCharacters(in: .whitespacesAndNewlines),
              !href.isEmpty
        else { throw ProtocolParserError.detailLinkMissing }

        guard let url = URL(string: href) else { throw ProtocolParserError.detailLinkMissing }
        if url.scheme != nil { return url }                       // already absolute
        guard let base else { throw ProtocolParserError.relativeLinkWithoutBaseURL }
        guard let resolved = URL(string: href, relativeTo: base)?.absoluteURL else {
            throw ProtocolParserError.relativeLinkWithoutBaseURL
        }
        return resolved
    }

    // MARK: - Segment detail page

    /// Reads a whole segment page into skaters and elements (protocol-parser.md §4.4–§4.6).
    nonisolated public static func parseSegment(html: String) throws -> ProtocolSegment {
        guard let document = try? SwiftSoup.parse(html) else { throw ProtocolParserError.unrecognizedPage }

        let eventName = (try? document.select("h2.title").first()?.text()) ?? ""
        let categorySegment = (try? document.select("h2.catseg").first()?.text()) ?? ""

        var skaters: [ProtocolSkater] = []
        var namedSummary: String?
        var matchedTables = 0

        // Walk the tables in document order: a skater's elements come from the *next* element table
        // after their summary table, so a section with no element table fails on its own name
        // (protocol-parser.md §4.4).
        for table in (try? document.select("table"))?.array() ?? [] {
            let classes = (try? table.className())?.split(separator: " ").map(String.init) ?? []
            if classes.contains("sum") {
                let name = text(try table.select("tbody td.name").first()?.text() ?? "")
                if let pending = namedSummary {
                    throw ProtocolParserError.elementTableMissing(skater: pending)
                }
                namedSummary = name
            } else if classes.contains("elm"), let name = namedSummary {
                skaters.append(ProtocolSkater(
                    name: name,
                    elements: try elements(in: table, skater: name)))
                namedSummary = nil
                matchedTables += 1
            }
        }
        if let pending = namedSummary {
            throw ProtocolParserError.elementTableMissing(skater: pending)
        }
        if matchedTables == 0 { throw ProtocolParserError.unrecognizedPage }

        return ProtocolSegment(
            eventName: text(eventName),
            categorySegment: text(categorySegment),
            skaters: skaters)
    }

    /// The element rows of one table: rows carrying a `<TD class=num>`. The program-components
    /// block and the totals rows live in the same table and are skipped by that test
    /// (protocol-parser.md §4.5).
    nonisolated private static func elements(in table: Element, skater: String) throws -> [ProtocolElement] {
        var elements: [ProtocolElement] = []
        for row in (try? table.select("tr"))?.array() ?? [] {
            guard let numberCell = try? row.select("td.num").first() else { continue }
            let index = text((try? numberCell.text()) ?? "")

            guard let elementCell = try? row.select("td.elem").first() else {
                throw ProtocolParserError.malformedElementRow(
                    skater: skater, index: index, reason: "no element abbreviation cell")
            }
            guard let baseCell = try? row.select("td.bv").first(),
                  let baseValue = hundredths(try? baseCell.text()) else {
                throw ProtocolParserError.malformedElementRow(
                    skater: skater, index: index, reason: "Base Value is missing or not a number")
            }
            guard let goeCell = try? row.select("td.goe").first(),
                  let goeValue = hundredths(try? goeCell.text()) else {
                throw ProtocolParserError.malformedElementRow(
                    skater: skater, index: index, reason: "GOE is missing or not a number")
            }

            // Optional columns (protocol-parser.md §5.1–§5.2): an empty or &nbsp; bonus cell is 0,
            // and the panel score is the page's own arithmetic, kept for sanity checking only.
            let bonusValue = hundredths(try? row.select("td.ref").first()?.text()) ?? 0
            let panelScore = hundredths(try? row.select("td.psv").first()?.text()) ?? 0

            elements.append(ProtocolElement(
                index: Int(index) ?? elements.count + 1,
                abbreviation: text(try elementCell.text()),
                baseValue: baseValue,
                goeValue: goeValue,
                bonusValue: bonusValue,
                panelScore: panelScore))
        }
        return elements
    }

    // MARK: - Skater selection

    /// Isolates one skater by name — the shared matcher (`ProtocolSegment.skater(named:)`,
    /// protocol-parser.md §6), kept here because this is the documented HTML entry point.
    nonisolated public static func skater(named name: String, in segment: ProtocolSegment) throws -> ProtocolSkater {
        try segment.skater(named: name)
    }

    // MARK: - Cell text

    /// `&nbsp;` padding is not whitespace to `trimmingCharacters`, so normalise it first.
    nonisolated private static func text(_ raw: String) -> String {
        ProtocolNumber.normalized(raw)
    }

    /// Decimal string → integer hundredths. `nil` when the cell holds no number at all
    /// (protocol-parser.md §5.1 — the sign traps live in `ProtocolNumber`).
    nonisolated private static func hundredths(_ raw: String?) -> Int? {
        ProtocolNumber.hundredths(raw)
    }
}
