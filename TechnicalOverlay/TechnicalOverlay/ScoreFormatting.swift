//
//  ScoreFormatting.swift
//  TechnicalOverlay
//
//  Scores are integer hundredths (3.40 → 340, -1.19 → -119); this is the way in and out of that form.
//

import Foundation

/// Rendering a hundredths score as text.
enum ScoreFormatting {

    /// `340` → `"3.40"`, `-119` → `"-1.19"`. `decimalPlaces` sets the fractional width, so the bonus
    /// column can ask for one decimal while the others keep two.
    static func string(from value: Int, decimalPlaces: Int = 2) -> String {
        let negative = value < 0
        let whole = abs(value) / 100
        let fractional = abs(value) % 100
        if negative {
            return String(format: "-%d.%0\(decimalPlaces)d", whole, fractional)
        } else {
            return String(format: "%d.%0\(decimalPlaces)d", whole, fractional)
        }
    }
}

extension ElementData {

    /// The element's own scores as text — the form the pane and the scoring list show.
    func formatValue(_ value: Int, decimalPlaces: Int = 2) -> String {
        ScoreFormatting.string(from: value, decimalPlaces: decimalPlaces)
    }
}

extension String {

    /// The characters a score can be made of: digits, the decimal point and the minus sign.
    func numberCharacters() -> String {
        let digits = CharacterSet(charactersIn: "-.0123456789")
        return String(
            unicodeScalars.filter { digits.contains($0) }
        )
    }

    func onlyDigits() -> String {
        let digits = CharacterSet(charactersIn: "0123456789")
        return String(
            unicodeScalars.filter { digits.contains($0) }
        )
    }

    /// A typed decimal string as integer hundredths. Text with no number in it is `0`, so a cleared
    /// field means zero rather than a parse failure.
    func toHundredthsInt() -> Int {
        let trimmed = numberCharacters()
        if trimmed.isEmpty {
            return 0
        }
        let components = trimmed.split(
            separator: ".",
            maxSplits: 2,
            omittingEmptySubsequences: false
        )
        let isNegative = components[0].first == "-"
        let whole = Int(components[0]) ?? 0
        let fractionalString = components.count > 1 ? String(components[1]).onlyDigits() + "00" : "00"
        let index = fractionalString.index(
            fractionalString.startIndex,
            offsetBy: 2
        )
        let fractionalValue = Int(fractionalString[..<index]) ?? 0
        
        return (abs(whole) * 100 + fractionalValue) * (isNegative ? -1 : 1)
    }
}
