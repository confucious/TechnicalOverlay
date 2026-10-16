//
//  ElementNameExpander.swift
//  ProtocolParser
//
//  Abbreviation → display name for the singles vocabulary
//  (`docs/architecture/abbreviation-expansion.md` §4). Pure, `nonisolated`, no I/O and no state;
//  a token these rules do not know is returned verbatim (§4.9).
//

import Foundation

/// Turns a published element abbreviation into the name shown on the overlay and in the scoring
/// list (`docs/architecture/abbreviation-expansion.md` §6).
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

/// The singles implementation: jumps, spin, step-sequence and choreographic codes, the protocol's
/// markers, and the call tokens (§4.1–§4.9).
public struct ElementNameExpander: ElementNameTranslating {

    public nonisolated init() {}

    /// Expands a whole abbreviation — `3Tb1+2T` → `3 Toeloop + 2 Toeloop`. Tokens are split on `+`
    /// and joined back with ` + `; dropped tokens leave neither a separator nor an empty part (§4.8).
    public nonisolated func displayName(for abbreviation: String) -> String {
        abbreviation
            .split(separator: "+", omittingEmptySubsequences: false)
            .compactMap(part(of:))
            .joined(separator: " + ")
    }

    // MARK: - One token

    /// One `+`-separated token → its part of the name, or `nil` when the token is dropped entirely.
    nonisolated private func part(of token: Substring) -> String? {
        let raw = String(token)
        guard !raw.isEmpty else { return nil }

        let invalid = raw.contains("*")
        let core = Self.withoutIgnoredMarkers(raw)
        guard !core.isEmpty else { return invalid ? "(Invalid)" : nil }

        switch core {
        case "SEQ", "COMBO", "REP":                           // call tokens, shown as published (§4.5)
            return core
        default:
            break
        }
        if core.hasPrefix("kp") { return nil }               // step-sequence key points (§4.6)

        let name = Self.sequence(core) ?? Self.spin(core) ?? Self.jump(core)
        guard let name else { return raw }                   // unknown → verbatim (§4.9)
        return invalid ? "\(name) (Invalid)" : name          // §4.7 — per token, after the element
    }

    // MARK: - Ignored markers

    /// The characters a jump token may carry after its code: under-rotated `<`, downgraded `<<`,
    /// unclear edge `!`, wrong edge `e`, quarter-short `q`.
    ///
    /// These are a **trailing run on a jump token**, never a character class over the whole token:
    /// `q` is also a letter of `StSq`/`ChSq`, so a blanket strip turns `StSq2` into `StS2` and
    /// `ChSq1` into `ChS1`, and every step sequence silently stops classifying (§2.4 trap 1).
    nonisolated private static let markers: Set<Character> = ["<", "!", "e", "q"]

    nonisolated static func withoutIgnoredMarkers(_ token: String) -> String {
        var text = removingBonusMarker(from: token.replacingOccurrences(of: "*", with: ""))
        while let last = text.last, markers.contains(last) { text.removeLast() }
        return text
    }

    /// Removes `b<digits>[.<digits>]` — the bonus for a difficult element, which the protocol also
    /// carries in its own column, so the name drops it (§4.6).
    ///
    /// It is stripped **wherever it sits**: `3Tb1` and `3Lz<b1` both occur, so a fixed "markers then
    /// bonus" order misses the second (§2.4 trap 2). A bare `b` is left alone, which is what keeps
    /// the spin level `B` (uppercase) and codes like `1LiB` intact.
    nonisolated static func removingBonusMarker(from token: String) -> String {
        var characters = Array(token)
        var index = 0
        while index < characters.count {
            guard characters[index] == "b" else { index += 1; continue }

            var end = index + 1
            while end < characters.count, characters[end].isNumber { end += 1 }
            guard end > index + 1 else { index += 1; continue }      // a bare "b" is not a bonus

            if end < characters.count, characters[end] == "." {
                var fraction = end + 1
                while fraction < characters.count, characters[fraction].isNumber { fraction += 1 }
                if fraction > end + 1 { end = fraction }             // b0.5
            }
            characters.removeSubrange(index..<end)
            // No advance: another bonus marker could follow.
        }
        return String(characters)
    }

    // MARK: - Step sequences and choreographic elements

    nonisolated private static let levels: Set<Character> = ["B", "1", "2", "3", "4"]

    /// `StSq<level>` → `Step Sequence <level>`; a choreographic code → `<name> <digit>`.
    ///
    /// A choreographic code's trailing digit is part of the code rather than a level, and **is**
    /// shown; only `pChSq1`'s prefix is dropped (§4.4).
    nonisolated static func sequence(_ core: String) -> String? {
        if core.hasPrefix("StSq") {
            let level = core.dropFirst("StSq".count)
            guard level.isEmpty || (level.count == 1 && level.allSatisfy(levels.contains)) else { return nil }
            return level.isEmpty ? "Step Sequence" : "Step Sequence \(level)"
        }
        for entry in choreographic where core.hasPrefix(entry.code) {
            let trailing = core.dropFirst(entry.code.count)
            guard trailing.allSatisfy(\.isNumber) else { return nil }
            return trailing.isEmpty ? entry.name : "\(entry.name) \(trailing)"
        }
        return nil
    }

    nonisolated private static let choreographic: [(code: String, name: String)] = [
        ("pChSq", "Choreo Sequence"),
        ("ChSq", "Choreo Sequence"),
        ("ChSp", "Choreo Spin"),
    ]

    // MARK: - Spins

    /// `<spin name> <level>` plus, when the panel marked it, a `V` (a reduced value — a spin
    /// requirement was not fulfilled) separated from the level by a space: `CCoSp1V` →
    /// `Change Combo Spin 1 V`, `CCoSpBV` → `Change Combo Spin B V` (§4.3). A spin the panel called
    /// with no level gets the name alone.
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
    ]

    /// Longest code first: the codes are prefixes of one another and all end in `Sp` — `CSp` ⊂
    /// `CCSp`, `SSp` ⊂ `FSSp`/`CSSp`, `CoSp` ⊂ `CCoSp`/`FCoSp`, `CSp` ⊂ `FCSp` — so a
    /// first-match walk over an unordered table would expand `CCSp3` as a Camel Spin (§2.4 trap 3).
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
    /// one (§4.2). The remainder after the code must be empty: `3STh` must not become a Salchow
    /// (§2.4 trap 4).
    nonisolated private static let jumps: [(code: String, name: String)] = [
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
