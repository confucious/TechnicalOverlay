//
//  ScoringListImportButtonTests.swift
//  TechnicalOverlayUITests
//
//  The "Import Protocol" button on the scoring list: it is there, and it sits to the left of
//  "Add Element" in the same button row.
//

import XCTest

final class ScoringListImportButtonTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testImportButtonSitsLeftOfAddElement() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Edit Slides"].tap()

        let importButton = app.buttons["Import Protocol"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5),
                      "the scoring list should offer an Import Protocol button")

        let addElement = app.buttons["Add Element"]
        XCTAssertTrue(addElement.exists, "Add Element should still be there")

        // Same row: their vertical extents overlap, and the import button starts to the left.
        XCTAssertLessThan(importButton.frame.minX, addElement.frame.minX)
        XCTAssertLessThan(importButton.frame.minY, addElement.frame.maxY)
        XCTAssertLessThan(addElement.frame.minY, importButton.frame.maxY)
    }

    @MainActor
    func testImportButtonAsksForTheProtocolAddress() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Edit Slides"].tap()

        let importButton = app.buttons["Import Protocol"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        importButton.tap()

        // The flow starts by asking where the protocol is.
        XCTAssertTrue(app.staticTexts["Import Protocol"].waitForExistence(timeout: 5),
                      "tapping Import Protocol should present the address prompt")
        XCTAssertTrue(app.textFields["Protocol page address"].exists)
        XCTAssertTrue(app.buttons["Import"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }
}
