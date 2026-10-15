//
//  ProtocolParserTests.swift
//  ProtocolParserTests
//
//  Created by Jerry Hsu on 10/12/25.
//

import Foundation
import Testing

/// The HTML fixtures are the real ijsLive pages this module was designed against
/// (`docs/architecture/protocol-parser.md` §3), fetched 2026-10-14 from the 2026 Boston Open
/// (event `36683`) and committed beside these tests. Two are synthetic, built from the real pages
/// to exercise error paths that no published page happened to have:
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

    enum FixtureError: Error { case undecodable(String) }

    /// The eleven segment detail pages and the two leaderboard pages of the fixture set.
    static let detailPages = [
        "SEGM001.html", "SEGM011.html", "SEGM015.html", "SEGM021.html", "SEGM026.html",
        "SEGM028.html", "SEGM030.html", "SEGM031.html", "SEGM032.html", "SEGM033.html",
        "SEGM034.html",
    ]
    static let leaderboardPages = ["CAT022SEG033.html", "CAT022SEG034.html"]
}
