//
//  ElementNameExpander+Dance.swift
//  ProtocolParser
//
//  The ice-dance vocabulary: lifts, twizzle sets, step sequences, one-foot turns, the pattern-dance
//  element codes and the solo-dance codes
//  (`docs/architecture/abbreviation-expansion.md` §4.11–§4.12). The dance spin is a spin (§4.3) and
//  the choreographic codes are §4.4.
//

import Foundation

extension ElementNameExpander {

    /// One half of a two-partner element: `SqTwW4` is `(.sequential twizzle, W, 4)`.
    ///
    /// The two halves of one element carry the same code and the two partner letters, which is what
    /// `displayName(for:)` keys on to recombine them (abbreviation-expansion.md §4.8).
    nonisolated struct PartnerHalf: Equatable {
        let code: String
        let name: String
        let partner: Character
        let level: String
    }

    /// One dance token → its name: `StaLi4` → `Stationary Lift 4`, `SqTwW4` → `Sequential Twizzle W 4`,
    /// `ChAJ1` is a choreographic code (§4.4) and `FO1Sq4` a pattern-dance one (§4.12).
    nonisolated static func dance(_ core: String) -> String? {
        let token = strippingDanceMarkers(core)
        guard !token.isEmpty else { return nil }

        return danceLift(token)
            ?? partnerHalf(Substring(token)).map(singular)
            ?? patternDanceTypeStepSequence(token)
            ?? soloTwizzles(token)
            ?? edgeElement(token)
    }

    /// `S` (reduce one level — separation or loss of contact) and `>` (an extended lift) are dance
    /// markers, and `S` is also the Salchow code, so they are stripped **here** and nowhere else
    /// (abbreviation-expansion.md §4.6, §2.4 trap 7).
    nonisolated static func strippingDanceMarkers(_ token: String) -> String {
        var text = token
        while let last = text.last, last == "S" || last == ">" { text.removeLast() }
        return text
    }

    // MARK: - Lifts

    /// `StaLi` `SlLi` `CuLi` `RoLi` → `<kind> Lift <level>`. `SiLi` is the ISU list's spelling of
    /// the straight-line lift; the published pages write `SlLi`, so both classify
    /// (abbreviation-expansion.md §4.11).
    nonisolated private static func danceLift(_ token: String) -> String? {
        for entry in danceLifts where token.hasPrefix(entry.code) {
            guard let level = singleLevel(token.dropFirst(entry.code.count)) else { continue }
            return level.isEmpty ? entry.name : "\(entry.name) \(level)"
        }
        return nil
    }

    nonisolated private static let danceLifts: [(code: String, name: String)] = [
        ("StaLi", "Stationary Lift"),
        ("SlLi", "Straight Line Lift"),
        ("SiLi", "Straight Line Lift"),
        ("CuLi", "Curve Lift"),
        ("RoLi", "Rotational Lift"),
    ].sorted { $0.code.count > $1.code.count }

    // MARK: - Twizzle sets, step sequences, one-foot turns

    /// The codes whose halves name a partner: `<code><W|M><level>`.
    nonisolated private static let partnerCodes: [(code: String, name: String)] = [
        ("SqTw", "Sequential Twizzle"),
        ("SyTw", "Synchronized Twizzle"),
        ("pSTw", "Synchronized Twizzle"),
        ("MiSt", "Midline Step"),
        ("DiSt", "Diagonal Step"),
        ("CiSt", "Circular Step"),
        ("SeSt", "Serpentine Step"),
        ("OFT", "One Foot Turn"),
    ].sorted { $0.code.count > $1.code.count }

    /// `SqTwW4` → `(.sequential twizzle, W, 4)`; `nil` when the token is not one half of a pair, or
    /// when it carries the invalid flag (a flagged half is left to the per-token rules at §4.7).
    nonisolated static func partnerHalf(_ token: Substring) -> PartnerHalf? {
        let raw = String(token)
        guard !raw.isEmpty, !raw.contains("*") else { return nil }
        let core = strippingDanceMarkers(removingBonusMarker(from: raw))

        for entry in partnerCodes where core.hasPrefix(entry.code) {
            let rest = core.dropFirst(entry.code.count)
            guard let partner = rest.first, partner == "W" || partner == "M" else { continue }
            guard let level = singleLevel(rest.dropFirst()) else { continue }
            return PartnerHalf(code: entry.code, name: entry.name, partner: partner, level: level)
        }
        return nil
    }

    /// One half on its own — the form a half takes when it has no partner half beside it.
    nonisolated static func singular(_ half: PartnerHalf) -> String {
        "\(half.name) \(half.partner)\(half.level.isEmpty ? "" : " \(half.level)")"
    }

    /// The two halves as one element: `Sequential Twizzles W 4 / M 4`. Plural name, each level with
    /// its own partner letter, and a half the panel did not level left without a number
    /// (abbreviation-expansion.md §4.8).
    nonisolated static func recombined(_ first: PartnerHalf, _ second: PartnerHalf) -> String {
        let one = "\(first.partner)\(first.level.isEmpty ? "" : " \(first.level)")"
        let two = "\(second.partner)\(second.level.isEmpty ? "" : " \(second.level)")"
        return "\(first.name)s \(one) / \(two)"
    }

    // MARK: - Senior and solo-dance codes

    /// `PSt<level>` → `Pattern Dance Type Step Sequence Style D <level>` — the senior rhythm dance's
    /// pattern-dance-type step sequence.
    nonisolated private static func patternDanceTypeStepSequence(_ token: String) -> String? {
        guard token.hasPrefix("PSt") else { return nil }
        guard let level = singleLevel(token.dropFirst("PSt".count)) else { return nil }
        let name = "Pattern Dance Type Step Sequence Style D"
        return level.isEmpty ? name : "\(name) \(level)"
    }

    /// `SoTw<level>` → `Solo Twizzles <level>`.
    nonisolated private static func soloTwizzles(_ token: String) -> String? {
        guard token.hasPrefix("SoTw") else { return nil }
        guard let level = singleLevel(token.dropFirst("SoTw".count)) else { return nil }
        return level.isEmpty ? "Solo Twizzles" : "Solo Twizzles \(level)"
    }

    /// `SpEe` `CrEe` `SeEs` `IBEe` → the solo-dance edge elements.
    nonisolated private static func edgeElement(_ token: String) -> String? {
        for entry in edgeElements where token.hasPrefix(entry.code) {
            guard let level = singleLevel(token.dropFirst(entry.code.count)) else { continue }
            return level.isEmpty ? entry.name : "\(entry.name) \(level)"
        }
        return nil
    }

    nonisolated private static let edgeElements: [(code: String, name: String)] = [
        ("SpEe", "Spiral Edge Element"),
        ("CrEe", "Crouch Edge Element"),
        ("SeEs", "Spread Eagle Edge Element"),
        ("IBEe", "Ina Bauer Type Edge Element"),
    ]

    // MARK: - Pattern-dance elements

    /// Three published shapes, all with key points after a `+` (dropped as any `kp…` token is):
    ///
    /// - `<dance><sequence>Sq<level>` — `FO1Sq4` → `Fourteenstep Seq 1 4`
    /// - `<slot><dance><level>` — `1GW2` → `Golden Waltz 1 2`
    /// - `RPD<sequences><sequence>Sq<level>` — `RPD41Sq4` → `Pattern Dance Seq 1 4`
    ///
    /// The first number of the slot form is the element's place in the segment, not a sequence, and
    /// `RPD`'s is the number of sequences in the dance rather than a dance (abbreviation-expansion.md
    /// §4.12).
    nonisolated static func patternDance(_ core: String) -> String? {
        if core.hasPrefix("RPD") {
            let rest = core.dropFirst("RPD".count)
            guard rest.count == 5,
                  let sequence = rest.dropFirst().first, sequence.isNumber,
                  rest.first?.isNumber == true,
                  rest.dropFirst(2).hasPrefix("Sq"),
                  let level = singleLevel(rest.dropFirst(4)) else { return nil }
            return "Pattern Dance Seq \(sequence) \(level)"
        }

        for entry in patternDances where core.hasPrefix(entry.code) {
            let rest = core.dropFirst(entry.code.count)
            guard rest.count == 4,
                  let sequence = rest.first, sequence.isNumber,
                  rest.dropFirst().hasPrefix("Sq"),
                  let level = singleLevel(rest.dropFirst(3)) else { continue }
            return "\(entry.name) Seq \(sequence) \(level)"
        }

        if let slot = core.first, slot.isNumber {
            let afterSlot = core.dropFirst()
            for entry in patternDances where afterSlot.hasPrefix(entry.code) {
                guard let level = singleLevel(afterSlot.dropFirst(entry.code.count)) else { continue }
                return entry.isSlot
                    ? "Pattern Dance \(slot) \(level)"
                    : "\(entry.name) \(slot) \(level)"
            }
        }
        return nil
    }

    /// The ISU's dance codes. `WW` is flagged because in a rhythm dance it is a **slot**, not the
    /// dance: its label in the ISU list still describes 2025-26's `1RH`/`1QS`, so the name cannot be
    /// claimed (abbreviation-expansion.md §4.12).
    nonisolated private static let patternDances: [(code: String, name: String, isSlot: Bool)] = [
        ("TTF", "Tea-Time Foxtrot", false),
        ("TFO", "Ten Fox", false),
        ("HHO", "Hickory Hoedown", false),
        ("WiW", "Willow Waltz", false),
        ("EW", "European Waltz", false),
        ("AW", "American Waltz", false),
        ("WW", "", true),
        ("VW", "Viennese Waltz", false),
        ("OW", "Austrian Waltz", false),
        ("SW", "Starlight Waltz", false),
        ("RW", "Ravensburger Waltz", false),
        ("GW", "Golden Waltz", false),
        ("RF", "Rocker Foxtrot", false),
        ("FT", "Foxtrot", false),
        ("FO", "Fourteenstep", false),
        ("SD", "Swing Dance", false),
        ("DW", "Dutch Waltz", false),
        ("KI", "Kilian", false),
        ("YP", "Yankee Polka", false),
        ("QS", "Quickstep", false),
        ("FS", "Finnstep", false),
        ("PD", "Paso Doble", false),
        ("RH", "Rhumba", false),
        ("CC", "Cha Cha Congelado", false),
        ("SS", "Silver Samba", false),
        ("TF", "Tango Fiesta", false),
        ("TC", "Tango Canasta", false),
        ("TA", "Tango", false),
        ("AT", "Argentine Tango", false),
        ("TR", "Tango Romantica", false),
        ("RB", "Rhythm Blues", false),
        ("BL", "Blues", false),
        ("MB", "Midnight Blues", false),
    ].sorted { $0.code.count > $1.code.count }
}
