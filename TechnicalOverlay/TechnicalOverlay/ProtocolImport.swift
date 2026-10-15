//
//  ProtocolImport.swift
//  TechnicalOverlay
//
//  The app side of a protocol import: `ProtocolElement` → `ElementData`, and the index-keyed merge
//  that preserves the timing a user has already set. Spec: docs/architecture/protocol-parser.md §8.
//

import Foundation
import ProtocolParser

extension ElementData {
    /// An imported element, untimed — the timeline is the user's, and only a merge may touch it.
    convenience init(_ element: ProtocolElement) {
        self.init(
            name: element.abbreviation,      // verbatim until the name translator lands (§9)
            baseValue: element.baseValue,
            goeValue: element.goeValue,
            bonusValue: element.bonusValue,
            displayTime: nil)
    }
}

extension OverlayData {
    /// Merges an imported protocol into `elementScores`, keyed by element index (§8.1).
    ///
    /// - an entry that exists at an index: values are refreshed in place and **`displayTime` is
    ///   kept** exactly as it was (a timestamp survives, `nil` stays `nil`);
    /// - elements the protocol adds beyond the current data: **appended**, untimed;
    /// - entries beyond the protocol's element count: **left untouched**.
    ///
    /// Timing is never destroyed, so re-importing after a correction cannot cost the user the
    /// work of placing elements on the timeline, and a bad parse cannot either.
    func merge(_ skater: ProtocolSkater) {
        for (index, element) in skater.elements.enumerated() {
            guard index < elementScores.count else {
                elementScores.append(ElementData(element))
                continue
            }
            let existing = elementScores[index]
            existing.name = element.abbreviation
            existing.baseValue = element.baseValue
            existing.goeValue = element.goeValue
            existing.bonusValue = element.bonusValue
            // existing.displayTime deliberately not touched.
        }
    }
}
