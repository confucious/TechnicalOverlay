//
//  ProtocolParserTests.swift
//  ProtocolParserTests
//
//  Created by Jerry Hsu on 10/12/25.
//

import Foundation
import Testing

/// The HTML fixtures are the real ijsLive pages of `protocol-parser.md` §3 — the
/// 2026 Boston Open (event `36683`) — committed beside these tests. Two are synthetic, built from the
/// real pages to exercise error paths that no published page happened to have:
///
/// - `Synthetic-NoDetailLink.html` — leaderboard page with the `<LI class="judgeDetailRef">` block
///   removed, i.e. the state before the organizer publishes judge details.
/// - `Synthetic-MalformedRow.html` — detail page with one element row's Base Value cell removed.
enum Fixture {
    /// Resolved relative to this source file, so no resource bundle or machine-specific path is
    /// needed and the fixtures stay readable as plain files in the repo.
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    static func html(_ name: String) throws -> String {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        guard let text = String(data: data, encoding: .isoLatin1) else {
            throw FixtureError.undecodable(name)
        }
        return text
    }

    /// A PDF fixture's bytes — protocol PDFs are parsed from the document, not from text.
    static func pdf(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    /// The two ISU FS Manager protocol PDFs (`protocol-parser.md` §3.2): the 2026 Grand Prix Canada
    /// women's short program, and advanced novice boys' short program from the 2026 Cranberry Cup —
    /// the second one carries a Bonus column.
    static let protocolPDFs = [
        "ISU-FSKWSINGLES-QUAL000100.pdf",
        "ISU-FSKMSINGLES-ADVNOV-QUAL000100.pdf",
    ]

    enum FixtureError: Error { case undecodable(String) }

    /// The eleven segment detail pages and the two leaderboard pages of the fixture set.
    static let detailPages = [
        "SEGM001.html", "SEGM011.html", "SEGM015.html", "SEGM021.html", "SEGM026.html",
        "SEGM028.html", "SEGM030.html", "SEGM031.html", "SEGM032.html", "SEGM033.html",
        "SEGM034.html",
    ]
    static let leaderboardPages = ["CAT022SEG033.html", "CAT022SEG034.html"]

    /// The five **singles** segment pages of the set above — the ones the abbreviation expansion's
    /// census was measured over (`abbreviation-expansion.md` §3.1): 535 element rows.
    /// `SEGM033` is singles too, but it is the sibling page the link test needs; the rest are pairs.
    static let singlesDetailPages = [
        "SEGM001.html", "SEGM011.html", "SEGM015.html", "SEGM021.html", "SEGM034.html",
    ]

    /// The five **pairs** segment pages of the set above (`abbreviation-expansion.md` §3.2):
    /// 182 element rows, 66 distinct abbreviations.
    static let pairsDetailPages = [
        "SEGM026.html", "SEGM028.html", "SEGM030.html", "SEGM031.html", "SEGM032.html",
    ]

    /// Thirteen **ice-dance** pages from the Challenge Cup 2026 protocol set
    /// (`abbreviation-expansion.md` §3.2): juvenile through senior partnered dance, 247 element
    /// rows, 121 distinct abbreviations.
    static let danceDetailPages = [
        "ChallengeCup-SEGM001.html", "ChallengeCup-SEGM002.html", "ChallengeCup-SEGM003.html",
        "ChallengeCup-SEGM004.html", "ChallengeCup-SEGM005.html", "ChallengeCup-SEGM006.html",
        "ChallengeCup-SEGM007.html", "ChallengeCup-SEGM008.html", "ChallengeCup-SEGM009.html",
        "ChallengeCup-SEGM018.html", "ChallengeCup-SEGM019.html", "ChallengeCup-SEGM020.html",
        "ChallengeCup-SEGM021.html",
    ]
}
