//
//  ScoringListImportButtonTests.swift
//  TechnicalOverlayUITests
//
//  The Import Protocol button on the scoring list: it is there, to the left of Add Element, and its
//  dialog offers the two ways to give it a protocol — an address, or a file.
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
    func testImportButtonSitsLeftOfAddElement() throws {
        let app = openScoringList()

        let importButton = app.buttons["Import Protocol"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5),
                      "the scoring list should offer an Import Protocol button")

        let addElement = app.buttons["Add Element"]
        XCTAssertTrue(addElement.exists, "Add Element should still be there")

        // Same row: their vertical extents overlap, and the import button starts to the left.
        XCTAssertLessThan(importButton.frame.minX, addElement.frame.minX)
        XCTAssertLessThan(importButton.frame.minY, addElement.frame.maxY)
        XCTAssertLessThan(addElement.frame.minY, importButton.frame.maxY)

        // The file is an option in the dialog, not a button beside this one.
        XCTAssertFalse(app.buttons["Import From File"].exists)
    }

    @MainActor
    func testImportButtonOffersAnAddressOrAFile() throws {
        let app = openScoringList()

        let importButton = app.buttons["Import Protocol"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        importButton.tap()

        // The flow starts by asking where the protocol is, and how to give it one.
        XCTAssertTrue(app.staticTexts["Import Protocol"].waitForExistence(timeout: 5),
                      "tapping Import Protocol should present the address prompt")
        XCTAssertTrue(app.textFields["Protocol page address"].exists)
        XCTAssertTrue(app.buttons["Import"].exists)
        XCTAssertTrue(app.buttons["Choose File…"].exists, "the dialog should offer a file as well")
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    @MainActor
    func testChoosingAFilePresentsTheFilePicker() throws {
        let app = openScoringList()

        let importButton = app.buttons["Import Protocol"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        importButton.tap()

        let chooseFile = app.buttons["Choose File…"]
        XCTAssertTrue(chooseFile.waitForExistence(timeout: 5))
        chooseFile.tap()

        // The system document picker took the dialog's place.
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10),
                      "choosing a file should present the file picker")
        XCTAssertFalse(app.textFields["Protocol page address"].exists)
    }
}
