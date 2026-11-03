//
//  ElementNameExpander.swift
//  ProtocolParser
//
//  Abbreviation → display name for the singles vocabulary, plus the shared machinery the pairs and
//  ice-dance rules use (`docs/architecture/abbreviation-expansion.md` §4). Pure, `nonisolated`, no
//  I/O and no state; a token these rules do not know is returned verbatim (§4.9).
//
//  The pairs rules are ElementNameExpander+Pairs.swift, the ice-dance ones
//  ElementNameExpander+Dance.swift.
//

import Foundation

/// Turns a published element abbreviation into the name shown on the overlay and in the scoring
/// list (`abbreviation-expansion.md` §6).
///
/// The default implementation returns the abbreviation unchanged, so a conformer that implements
/// nothing — or the absence of a translator altogether — is not a failure mode.
///
/// The requirement is `nonisolated`: every target is MainActor-isolated by default (`Project.swift`
/// `baseSettings`), so without it the protocol would be MainActor-only and nothing off the main
/// actor could conform to it.
public nonisolated protocol ElementNameTranslating: Sendable {
    func displayName(for abbreviation: String) -> String
}

public extension ElementNameTranslating {
    /// The identity default: the abbreviation, unchanged.
    nonisolated func displayName(for abbreviation: String) -> String { abbreviation }
}

/// The implementation: singles jumps, spins, step sequences and choreographic codes, the pairs
/// family and the ice-dance family, the protocol's markers, and the call tokens
/// (abbreviation-expansion.md §4.1–§4.12).
public struct ElementNameExpander: ElementNameTranslating {

    public nonisolated init() {}

    /// Expands a whole abbreviation — `3Tb1+2T` → `3 Toeloop + 2 Toeloop`. Tokens are split on `+`;
    /// the two halves of a two-partner element are recombined into one name, then the surviving
    /// parts are joined with ` + `, so a dropped token leaves neither a separator nor an empty part
    /// (abbreviation-expansion.md §4.8).
    public nonisolated func displayName(for abbreviation: String) -> String {
        let tokens = abbreviation.split(separator: "+", omittingEmptySubsequences: false)
        var parts: [String] = []
        var index = tokens.startIndex

        while index < tokens.endIndex {
            let next = tokens.index(after: index)

            // One element, two partners: same code, the two partner letters (abbreviation-expansion.md
            // §4.8). Recombining here — rather than per token — is what stops a twizzle set or a step
            // sequence reading as two elements.
            if next < tokens.endIndex,
               let first = Self.partnerHalf(tokens[index]),
               let second = Self.partnerHalf(tokens[next]),
               first.code == second.code,
               first.partner != second.partner {
                parts.append(Self.recombined(first, second))
                index = tokens.index(after: next)
                continue
            }

            if let part = part(of: tokens[index]) { parts.append(part) }
            index = next
        }
        return parts.joined(separator: " + ")
    }

    // MARK: - One token

    /// One `+`-separated token → its part of the name, or `nil` when the token is dropped entirely.
    ///
    /// Classification is ordered: the families first, the jump rule last, because the jump rule
    /// accepts a single letter with an optional leading number and must not read a throw, a twist or
    /// a lift as a jump (abbreviation-expansion.md §4.1, §2.4 traps 4, 7 and 8).
    nonisolated private func part(of token: Substring) -> String? {
        let raw = String(token)
        guard !raw.isEmpty else { return nil }

        let invalid = raw.contains("*")
        let core = Self.withoutIgnoredMarkers(raw)
        guard !core.isEmpty else { return invalid ? "(Invalid)" : nil }

        if Self.callTokens.contains(core) { return core }     // §4.5 — shown as published
        if core.hasPrefix("kp") { return nil }                // §4.6 — key points, dropped

        // `markerFree` keeps a trailing `e`, which the dance edge elements end with (`SpEe`,
        // `CrEe`, `IBEe`); the dance rules strip the markers they own themselves (§4.6).
        let markerFree = Self.removingBonusMarker(from: raw.replacingOccurrences(of: "*", with: ""))

        let name = Self.sequence(core)
            ?? Self.spin(core)
            ?? Self.pairs(core)
            ?? Self.dance(core)
            ?? Self.dance(markerFree)
            ?? Self.patternDance(core)
            ?? Self.jump(core)
        guard let name else { return raw }                    // unknown → verbatim (§4.9)
        return invalid ? "\(name) (Invalid)" : name           // §4.7 — per token, after the element
    }

    // MARK: - Call tokens

    /// Calls the technical panel made rather than elements, plus the dance extra-element token
    /// (abbreviation-expansion.md §4.5). All are shown as published.
    nonisolated static let callTokens: Set<String> = ["SEQ", "COMBO", "REP", "ExEI"]

    // MARK: - Ignored markers

    /// The characters a jump token may carry after its code: under-rotated `<`, downgraded `<<`,
    /// unclear edge `!`, wrong edge `e`, quarter-short `q`.
    ///
    /// These are a **trailing run on a jump token**, never a character class over the whole token:
    /// `q` is also a letter of `StSq`/`ChSq`, so a blanket strip turns `StSq2` into `StS2` and
    /// `ChSq1` into `ChS1`, and every step sequence silently stops classifying
    /// (abbreviation-expansion.md §2.4 trap 1).
    nonisolated private static let markers: Set<Character> = ["<", "!", "e", "q"]

    nonisolated static func withoutIgnoredMarkers(_ token: String) -> String {
        var text = removingBonusMarker(from: token.replacingOccurrences(of: "*", with: ""))
        while let last = text.last, markers.contains(last) { text.removeLast() }
        return text
    }

    /// Removes the bonus marker for a difficult element — the protocol carries the amount in its own
    /// column, so the name drops the marker (abbreviation-expansion.md §4.6).
    ///
    /// Two printed forms. The HTML pages print the amount — `b1`, `b0.5` — and it is stripped
    /// **wherever it sits**: `3Tb1` and `3Lz<b1` both occur, so a fixed "markers then bonus" order
    /// misses the second (abbreviation-expansion.md §2.4 trap 2). The FS Manager PDF prints a bare
    /// lowercase `b` at the end of the token (`3Tb`, `2Ab`, `3Lzb`) and puts the amount only in the
    /// Bonus column, so a trailing lowercase `b` is a marker too.
    ///
    /// Lowercase only: a spin, lift or step sequence level is an uppercase `B` (`CCoSpBV`, `1LiB`,
    /// `StSqB`), and that is what a bare `b` rule must not eat.
    nonisolated static func removingBonusMarker(from token: String) -> String {
        var characters = Array(token)
        var index = 0
        while index < characters.count {
            guard characters[index] == "b" else { index += 1; continue }

            var end = index + 1
            while end < characters.count, characters[end].isNumber { end += 1 }
            guard end > index + 1 else { index += 1; continue }      // trailing bare `b` is handled below

            if end < characters.count, characters[end] == "." {
                var fraction = end + 1
                while fraction < characters.count, characters[fraction].isNumber { fraction += 1 }
                if fraction > end + 1 { end = fraction }             // b0.5
            }
            characters.removeSubrange(index..<end)
            // No advance: another bonus marker could follow.
        }
        // The amount-less form: `3Tb`, `2Ab`, `3Fb+2T<<*` (a token's own trailing `b`).
        if characters.last == "b" { characters.removeLast() }
        return String(characters)
    }

    // MARK: - Levels

    /// The level alphabet every vocabulary shares: `B`, `1`–`4`.
    nonisolated static let levels: Set<Character> = ["B", "1", "2", "3", "4"]

    /// The level a pairs or dance code carries — `""` when the panel levelled nothing, `nil` when
    /// the tail is not a level at all. `V` is a singles spin suffix and is never one of these.
    nonisolated static func singleLevel(_ tail: Substring) -> String? {
        if tail.isEmpty { return "" }
        guard tail.count == 1, let level = tail.first, levels.contains(level) else { return nil }
        return String(level)
    }

    // MARK: - Step sequences and choreographic elements

    /// `StSq<level>` → `Step Sequence <level>`; a choreographic code → `<name> <digit>`; `CDE` →
    /// `Creative Dance Element <level>`.
    ///
    /// A choreographic code's trailing digit is part of the code rather than a level, and **is**
    /// shown; only a `p` prefix is dropped (abbreviation-expansion.md §4.4). `ChSt1` and `pChSt1`
    /// are different elements with different names.
    nonisolated static func sequence(_ core: String) -> String? {
        if core.hasPrefix("StSq") {
            let level = core.dropFirst("StSq".count)
            guard level.isEmpty || (level.count == 1 && level.allSatisfy(levels.contains)) else { return nil }
            return level.isEmpty ? "Step Sequence" : "Step Sequence \(level)"
        }
        if core.hasPrefix("CDE") {
            guard let level = singleLevel(core.dropFirst("CDE".count)) else { return nil }
            return level.isEmpty ? "Creative Dance Element" : "Creative Dance Element \(level)"
        }
        for entry in choreographic where core.hasPrefix(entry.code) {
            let trailing = core.dropFirst(entry.code.count)
            guard trailing.allSatisfy(\.isNumber) else { continue }
            return trailing.isEmpty ? entry.name : "\(entry.name) \(trailing)"
        }
        return nil
    }

    /// Longest code first: the entries share their first three letters (`ChSq`, `ChSp`, `ChSt`,
    /// `ChSl`), so a first-match walk over an unordered table would read `ChSt1` as a sequence.
    nonisolated private static let choreographic: [(code: String, name: String)] = [
        ("pChSq", "Choreo Sequence"),
        ("pChSt", "Choreo Step Sequence"),
        ("ChPSp", "Choreo Pair Spin"),
        ("ChPLi", "Choreo Pair Lift"),
        ("ChAJ", "Choreo Assisted Jumps"),
        ("ChSq", "Choreo Sequence"),
        ("ChSp", "Choreo Spin"),
        ("ChSt", "Choreo Char Step Sequence"),
        ("ChSl", "Choreo Slide"),
        ("ChLi", "Choreo Lift"),
    ].sorted { $0.code.count > $1.code.count }

    // MARK: - Spins

    /// `<spin name> <level>` plus, when the panel marked it, a `V` (a reduced value — a spin
    /// requirement was not fulfilled) separated from the level by a space: `CCoSp1V` →
    /// `Change Combo Spin 1 V`, `CCoSpBV` → `Change Combo Spin B V`
    /// (abbreviation-expansion.md §4.3). A spin the panel called with no level gets the name alone.
    ///
    /// The pairs and dance spins (`PSp`, `PCoSp`, `DSp`) are spins by the same rules.
    nonisolated private static let spins: [(code: String, name: String)] = [
        ("USp", "Upright Spin"),
        ("LSp", "Layback Spin"),
        ("CSp", "Camel Spin"),
        ("SSp", "Sit Spin"),
        ("FUSp", "Flying Upright Spin"),
        ("FLSp", "Flying Layback Spin"),
        ("FCSp", "Flying Camel Spin"),
        ("FSSp", "Flying Sit Spin"),
        ("CUSp", "Change Upright Spin"),
        ("CLSp", "Change Layback Spin"),
        ("CCSp", "Change Camel Spin"),
        ("CSSp", "Change Sit Spin"),
        ("FCUSp", "Flying Change Upright Spin"),
        ("FCLSp", "Flying Change Layback Spin"),
        ("FCCSp", "Flying Change Camel Spin"),
        ("FCSSp", "Flying Change Sit Spin"),
        ("CoSp", "Combo Spin"),
        ("CCoSp", "Change Combo Spin"),
        ("FCoSp", "Flying Combo Spin"),
        ("FCCoSp", "Flying Change Combo Spin"),
        ("PCoSp", "Pair Combo Spin"),
        ("PSp", "Pair Spin"),
        ("DSp", "Dance Spin"),
    ]

    /// Longest code first: the codes are prefixes of one another and all end in `Sp` — `CSp` ⊂
    /// `CCSp`, `SSp` ⊂ `FSSp`/`CSSp`, `CoSp` ⊂ `CCoSp`/`FCoSp`, `CSp` ⊂ `FCSp` — so a
    /// first-match walk over an unordered table would expand `CCSp3` as a Camel Spin
    /// (abbreviation-expansion.md §2.4 trap 3).
    nonisolated private static let spinsByLength: [(code: String, name: String)] =
        spins.sorted { $0.code.count > $1.code.count }

    nonisolated static func spin(_ core: String) -> String? {
        for entry in spinsByLength where core.hasPrefix(entry.code) {
            guard let suffix = levelSuffix(core.dropFirst(entry.code.count)) else { continue }
            return suffix.isEmpty ? entry.name : "\(entry.name) \(suffix)"
        }
        return nil
    }

    /// The text a spin's tail contributes: the level (`B`, `1`–`4`) with the reduced-value `V` after
    /// it, space-separated — `""` for a spin the panel did not level, `"B V"` / `"1 V"` when the `V`
    /// is there. `nil` when the tail is neither, so `SSp2` classifies as a spin while `2Tw4` matches
    /// no spin at all.
    nonisolated static func levelSuffix(_ tail: Substring) -> String? {
        var rest = tail
        var parts: [Substring] = []
        if let first = rest.first, levels.contains(first) {
            parts.append(rest.prefix(1))
            rest = rest.dropFirst()
        }
        if rest.first == "V" {
            parts.append(rest.prefix(1))
            rest = rest.dropFirst()
        }
        guard rest.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    // MARK: - Jumps

    /// `<revolutions> <jump name>`, the number always shown — `Euler` excepted, which never takes
    /// one (abbreviation-expansion.md §4.2). The remainder after the code must be empty: `3STh` must
    /// not become a Salchow (abbreviation-expansion.md §2.4 trap 4).
    nonisolated static let jumps: [(code: String, name: String)] = [
        ("Eu", "Euler"),
        ("Lo", "Loop"),
        ("Lz", "Lutz"),
        ("S", "Salchow"),
        ("T", "Toeloop"),
        ("A", "Axel"),
        ("F", "Flip"),
    ]

    nonisolated static func jump(_ core: String) -> String? {
        var rest = core[...]
        var revolutions: Character?
        if let first = rest.first, first.isNumber {
            revolutions = first
            rest = rest.dropFirst()
        }
        for entry in jumps where rest.hasPrefix(entry.code) {
            guard rest.dropFirst(entry.code.count).isEmpty else { continue }
            if entry.code == "Eu" { return entry.name }
            guard let revolutions else { return entry.name }      // no number in the source → none shown
            return "\(revolutions) \(entry.name)"
        }
        return nil
    }
}
