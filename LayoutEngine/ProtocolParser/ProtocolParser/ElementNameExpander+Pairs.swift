//
//  ElementNameExpander+Pairs.swift
//  ProtocolParser
//
//  The pairs vocabulary: throws, twist lifts, lifts, death spirals and pivot figures
//  (`docs/architecture/abbreviation-expansion.md` §4.10). Pair spins are spins (§4.3) and the
//  choreographic pair codes are §4.4; both live with their family.
//

import Foundation

extension ElementNameExpander {

    /// `3STh` → `Throw 3 Salchow`; `3Tw3` → `3 Twist Lift 3`; `1Li4` → `1 Lift 4`;
    /// `5ALi4` → `5 Axel Lasso Lift 4`; `BoDs3` → `Backward Outside Death Spiral 3`;
    /// `PiF1` → `Pivot Figure 1`.
    ///
    /// Every code here starts with a digit or a death-spiral/spiral/pivot letter pair, so none of
    /// them can be reached by a singles code (`abbreviation-expansion.md` §4.1).
    nonisolated static func pairs(_ core: String) -> String? {
        throwJump(core) ?? twistLift(core) ?? pairLift(core) ?? deathSpiral(core) ?? pivotFigure(core)
    }

    /// `<n><jump>Th` → `Throw <n> <jump>`. The word goes first here even though the published code
    /// puts `Th` last: the element reads as a throw of a jump, not as a jump.
    nonisolated private static func throwJump(_ core: String) -> String? {
        guard core.hasSuffix("Th") else { return nil }

        var rest = core.dropLast("Th".count)[...]
        var revolutions: Character?
        if let first = rest.first, first.isNumber {
            revolutions = first
            rest = rest.dropFirst()
        }
        for entry in jumps where rest == entry.code[...] {
            let jump = revolutions.map { "\($0) \(entry.name)" } ?? entry.name
            return "Throw \(jump)"
        }
        return nil
    }

    /// `<n>Tw<level>` → `<n> Twist Lift <level>`. The first number is the revolutions, the last the
    /// level — two bare numbers, so the family's own word sits between them.
    nonisolated private static func twistLift(_ core: String) -> String? {
        var rest = core[...]
        guard let first = rest.first, first.isNumber else { return nil }
        rest = rest.dropFirst()
        guard rest.hasPrefix("Tw") else { return nil }
        guard let level = singleLevel(rest.dropFirst("Tw".count)) else { return nil }

        let name = "\(first) Twist Lift"
        return level.isEmpty ? name : "\(name) \(level)"
    }

    /// `1Li`–`4Li` → `<n> Lift <level>`; `5ALi4` → `5 Axel Lasso Lift 4`.
    ///
    /// Group 5's letter is part of the code, so it stays in the name; groups 1–4 have no such letter
    /// to keep (`abbreviation-expansion.md` §4.10).
    nonisolated private static func pairLift(_ core: String) -> String? {
        guard let first = core.first, first.isNumber else { return nil }
        for entry in pairLifts where core.hasPrefix(entry.code) {
            guard let level = singleLevel(core.dropFirst(entry.code.count)) else { continue }
            return level.isEmpty ? entry.name : "\(entry.name) \(level)"
        }
        return nil
    }

    nonisolated private static let pairLifts: [(code: String, name: String)] = [
        ("5TLi", "5 Toe Lasso Lift"),
        ("5SLi", "5 Step-in Lasso Lift"),
        ("5BLi", "5 Backward Lasso Lift"),
        ("5ALi", "5 Axel Lasso Lift"),
        ("5RLi", "5 Reverse Lasso Lift"),
        ("1Li", "1 Lift"),
        ("2Li", "2 Lift"),
        ("3Li", "3 Lift"),
        ("4Li", "4 Lift"),
    ].sorted { $0.code.count > $1.code.count }

    /// `FiDs` `FoDs` `BiDs` `BoDs` → `<direction> Death Spiral <level>`.
    nonisolated private static func deathSpiral(_ core: String) -> String? {
        for entry in deathSpirals where core.hasPrefix(entry.code) {
            guard let level = singleLevel(core.dropFirst(entry.code.count)) else { continue }
            return level.isEmpty ? entry.name : "\(entry.name) \(level)"
        }
        return nil
    }

    nonisolated private static let deathSpirals: [(code: String, name: String)] = [
        ("FiDs", "Forward Inside Death Spiral"),
        ("FoDs", "Forward Outside Death Spiral"),
        ("BiDs", "Backward Inside Death Spiral"),
        ("BoDs", "Backward Outside Death Spiral"),
    ]

    /// `PiF<level>` → `Pivot Figure <level>`.
    nonisolated private static func pivotFigure(_ core: String) -> String? {
        guard core.hasPrefix("PiF") else { return nil }
        guard let level = singleLevel(core.dropFirst("PiF".count)) else { return nil }
        return level.isEmpty ? "Pivot Figure" : "Pivot Figure \(level)"
    }
}
