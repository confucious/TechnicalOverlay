//
//  LayoutEngineTests.swift
//  LayoutEngineTests
//
//  Created by Jerry Hsu on 9/21/25.
//

import Testing
import UIKit
@testable import LayoutEngine

struct LayoutEngineTests {

    private func makePane(showsElementBox: Bool) -> IsuTechnicalPaneView {
        let pane = IsuTechnicalPaneView()
        pane.frame = CGRect(x: 0.0, y: 0.0, width: 300.0, height: 120.0)
        pane.update(from: TechnicalViewModel(
            skaterName: "Jerry Hsu",
            elementName: "3Lz",
            baseValue: "5.90",
            goeValue: "0.50",
            totalValue: "6.40",
            boxModes: [.positive],
            showsElementBox: showsElementBox
        ))
        pane.setNeedsLayout()
        pane.layoutIfNeeded()
        return pane
    }

    @Test func elementBoxRowIsHiddenWhenTurnedOff() {
        let shown = makePane(showsElementBox: true)
        let hidden = makePane(showsElementBox: false)

        #expect(!shown.elementRow.isHidden)
        #expect(shown.elementRow.frame.height > 0)
        #expect(hidden.elementRow.isHidden)
        #expect(hidden.elementRow.frame == .zero)
    }

    @Test func rowsSitHigherWithoutElementBoxes() {
        let shown = makePane(showsElementBox: true)
        let hidden = makePane(showsElementBox: false)

        // The name row takes the box row's place, and the rows below it move up with it.
        #expect(hidden.elementNameView.frame.minY == 0)
        #expect(hidden.elementNameView.frame.minY < shown.elementNameView.frame.minY)
        #expect(hidden.elementScore.frame.minY < shown.elementScore.frame.minY)
        #expect(hidden.total.frame.maxY < shown.total.frame.maxY)
        // Only the box row's height is given up — the remaining rows keep their size.
        #expect(hidden.elementNameView.frame.height == shown.elementNameView.frame.height)
        #expect(hidden.total.frame.height == shown.total.frame.height)
    }

    @Test func paneFrameIsUnchangedWithoutElementBoxes() {
        let shown = makePane(showsElementBox: true)
        let hidden = makePane(showsElementBox: false)

        #expect(hidden.bounds == shown.bounds)
    }
}
