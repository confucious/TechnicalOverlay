//
//  ScoringListImportButtonTests.swift
//  TechnicalOverlayUITests
//
//  The import controls on the scoring list: both are there, they share a row of their own above the
//  hand-entry buttons, and each starts its own flow.
//

import XCTest

final class ScoringListImportButtonTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openScoringList() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Edit Slides"].tap()
        return app
    }

    @MainActor
    func testImportButtonsShareARowAboveTheEntryButtons() throws {
        let app = openScoringList()

        let importButton = app.buttons["Import Protocol"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5),
                      "the scoring list should offer an Import Protocol button")

        let fileButton = app.buttons["Import From File"]
        XCTAssertTrue(fileButton.exists, "the scoring list should offer an Import From File button")

        let addElement = app.buttons["Add Element"]
        XCTAssertTrue(addElement.exists, "Add Element should still be there")

        // One row: their vertical extents overlap, and the address import starts to the left.
        XCTAssertLessThan(importButton.frame.minX, fileButton.frame.minX)
        XCTAssertLessThan(importButton.frame.minY, fileButton.frame.maxY)
        XCTAssertLessThan(fileButton.frame.minY, importButton.frame.maxY)

        // The import pair is its own row, above the hand-entry pair.
        XCTAssertLessThanOrEqual(importButton.frame.maxY, addElement.frame.minY + 1)

        // No label wrapped: a squeezed row in a plain HStack wraps instead of overflowing
        // (docs/HISTORY.md → *Clear Slides resets the document*), which shows up as height.
        XCTAssertLessThan(importButton.frame.height, 45)
        XCTAssertEqual(importButton.frame.height, fileButton.frame.height, accuracy: 1)
    }

    @MainActor
    func testImportButtonAsksForTheProtocolAddress() throws {
        let app = openScoringList()

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

    @MainActor
    func testFileButtonPresentsTheFilePicker() throws {
        let app = openScoringList()

        let fileButton = app.buttons["Import From File"]
        XCTAssertTrue(fileButton.waitForExistence(timeout: 5))
        fileButton.tap()

        // The system document picker, not the address prompt.
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10),
                      "tapping Import From File should present a file picker")
        XCTAssertFalse(app.textFields["Protocol page address"].exists)
    }
}
