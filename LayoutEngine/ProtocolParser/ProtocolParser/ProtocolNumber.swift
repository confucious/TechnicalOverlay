//
//  ProtocolNumber.swift
//  ProtocolParser
//
//  Decimal text → integer hundredths (`docs/architecture/protocol-parser.md` §5.1), shared by the
//  HTML and PDF parsers. Every score in this module is `Int` hundredths.
//

import Foundation

nonisolated enum ProtocolNumber {

    /// True when `raw` is a printed score: digits with a decimal point (`3.30`, `-0.38`, `0.00`).
    /// Judge marks (`3`, `-5`) and markers (`x`, `-`, `q`) are not.
    static func isDecimal(_ raw: String) -> Bool {
        let trimmed = normalized(raw)
        guard trimmed.contains("."), trimmed.contains(where: \.isNumber) else { return false }
        return trimmed.allSatisfy { $0.isNumber || $0 == "." || $0 == "-" }
    }

    /// `"3.30"` → `330`, `"-0.90"` → `-90`, `"0.5"` → `50`; `nil` when there is no number.
    ///
    /// The sign is tracked separately from the whole-number component: `Int("-0") == 0`, so reading
    /// the sign off the integer part turns `-0.90` into `+90` — plausible-looking, wrong scores.
    static func hundredths(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let trimmed = normalized(raw)
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

    /// `&nbsp;` padding is not whitespace to `trimmingCharacters`, so normalise it first.
    static func normalized(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
