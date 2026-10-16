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
    /// that absence is the `.detailLinkMissing` case (§10b). So the results table and the
    /// segment-links list count as leaderboard signals too.
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

    /// Reads a whole segment page into skaters and elements (§4.4–§4.6).
    nonisolated public static func parseSegment(html: String) throws -> ProtocolSegment {
        guard let document = try? SwiftSoup.parse(html) else { throw ProtocolParserError.unrecognizedPage }

        let eventName = (try? document.select("h2.title").first()?.text()) ?? ""
        let categorySegment = (try? document.select("h2.catseg").first()?.text()) ?? ""

        var skaters: [ProtocolSkater] = []
        var namedSummary: String?
        var matchedTables = 0

        // Walk the tables in document order: a skater's elements come from the *next* element table
        // after their summary table, so a section with no element table fails on its own name
        // (§4.4).
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
    /// block and the totals rows live in the same table and are skipped by that test (§4.5).
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

            // Optional columns: an empty or &nbsp; bonus cell is 0 (§5.1); the panel score is the
            // page's own arithmetic, kept for sanity checking only (§5.2).
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

    /// Isolates one skater by name (§6): normalized exact match against the name part, falling back
    /// to the club-qualified name to disambiguate — never a prefix, substring or fuzzy match.
    nonisolated public static func skater(named name: String, in segment: ProtocolSegment) throws -> ProtocolSkater {
        let query = normalized(name)

        let byNamePart = segment.skaters.filter { normalized($0.namePart) == query }
        if byNamePart.count == 1 { return byNamePart[0] }
        if byNamePart.count > 1 {
            // Two skaters share a name — the club is the tie-breaker.
            let byFullName = byNamePart.filter { normalized($0.name) == query }
            if byFullName.count == 1 { return byFullName[0] }
            throw ProtocolParserError.skaterAmbiguous(
                name: name,
                matches: (byFullName.isEmpty ? byNamePart : byFullName).map(\.name))
        }

        let byFullName = segment.skaters.filter { normalized($0.name) == query }
        if byFullName.count == 1 { return byFullName[0] }
        if byFullName.count > 1 {
            throw ProtocolParserError.skaterAmbiguous(name: name, matches: byFullName.map(\.name))
        }
        throw ProtocolParserError.skaterNotFound(name: name, available: segment.skaters.map(\.name))
    }

    /// Case-folded, diacritic-folded, whitespace-collapsed, punctuation-stripped — so `Lianna
    /// O'Grady` matches the site's own `Lianna OGrady`, and stray commas matter (they distinguish
    /// the name part from the club-qualified name).
    nonisolated private static func normalized(_ raw: String) -> String {
        let folded = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let stripped = folded.filter { !".'’-".contains($0) }
        return stripped.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: - Cell text and values

    /// `&nbsp;` padding is not whitespace to `trimmingCharacters`, so normalise it first.
    nonisolated private static func text(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decimal string → integer hundredths. `nil` when the cell holds no number at all.
    ///
    /// The sign is tracked separately from the whole-number component: `Int("-0") == 0`, so reading
    /// the sign off `parts[0]` turns `-0.90` into `+90` (§5.1).
    nonisolated private static func hundredths(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let trimmed = text(raw)
        guard !trimmed.isEmpty, trimmed != "-" else { return nil }
        let negative = trimmed.hasPrefix("-")
        let digits = trimmed.filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard !digits.isEmpty else { return nil }
        let parts = digits.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let whole = Int(parts[0]) else { return nil }
        var fraction = 0
        if parts.count > 1 {
            let padded = String(parts[1]) + "00"
            fraction = Int(padded.prefix(2)) ?? 0
        }
        return (abs(whole) * 100 + fraction) * (negative ? -1 : 1)
    }
}
