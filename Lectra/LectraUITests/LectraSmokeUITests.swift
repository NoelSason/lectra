import XCTest

final class LectraSmokeUITests: LectraUITestCase {
    private let reviewPacketID = "20000000-0000-0000-0000-000000000001"

    func testCompactEditorShowsOverflowMenu() {
        let app = launchApp(scenario: .editorCompact)
        let moreButton = element(in: app, identifier: "editor.more")

        XCTAssertTrue(
            moreButton.waitForExistence(timeout: 5)
        )
        moreButton.tap()
        XCTAssertTrue(app.buttons["Export to Canvascope"].waitForExistence(timeout: 2))
    }

    func testFullEditorShowsCanvascopeExportAction() {
        let app = launchApp(scenario: .editorFull)
        let canvascopeExport = element(in: app, identifier: "editor.canvascope")

        XCTAssertTrue(canvascopeExport.waitForExistence(timeout: 5))
        XCTAssertTrue(canvascopeExport.label.contains("Canvascope"))
        XCTAssertFalse(canvascopeExport.label.contains("Lectra"))
    }

    func testFullEditorSupportsDrawingErasingToolRailAndUndoRedo() {
        let app = launchApp(scenario: .editorFull)
        let canvas = element(in: app, identifier: "editor.canvas")
        let undo = element(in: app, identifier: "editor.undo")
        let redo = element(in: app, identifier: "editor.redo")

        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let pen = element(in: app, identifier: "editor.tool.pen")
        XCTAssertTrue(pen.exists)
        pen.tap()

        drawLine(on: canvas, from: CGVector(dx: 0.36, dy: 0.46), to: CGVector(dx: 0.62, dy: 0.48))
        XCTAssertTrue(waitUntilEnabled(undo))

        element(in: app, identifier: "editor.tool.highlighter").tap()
        drawLine(on: canvas, from: CGVector(dx: 0.34, dy: 0.54), to: CGVector(dx: 0.66, dy: 0.54))

        element(in: app, identifier: "editor.tool.lasso").tap()
        XCTAssertTrue(element(in: app, identifier: "editor.tool.lasso").exists)

        element(in: app, identifier: "editor.tool.eraser").tap()
        drawLine(on: canvas, from: CGVector(dx: 0.36, dy: 0.46), to: CGVector(dx: 0.62, dy: 0.48))

        undo.tap()
        XCTAssertTrue(waitUntilEnabled(redo))
    }

    func testAuthScreenSupportsLargeDynamicType() {
        let app = launchApp(
            scenario: .auth,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXL"
        )

        XCTAssertTrue(
            element(in: app, identifier: "auth.signIn").waitForExistence(timeout: 5)
        )
    }

    func testLibraryScreenSupportsLargeDynamicType() {
        let app = launchApp(
            scenario: .library,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXL"
        )

        XCTAssertTrue(
            element(in: app, identifier: "library.search").waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            element(in: app, identifier: "library.account").exists
        )
    }

    func testLibraryDoesNotShowNotificationsAffordance() {
        let app = launchApp(scenario: .library)

        XCTAssertTrue(
            element(in: app, identifier: "library.search").waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            element(in: app, identifier: "library.notifications").exists
        )
    }

    func testLibraryShowsCanvascopeImportFolderName() {
        let app = launchApp(scenario: .library)
        let importedFolder = element(
            in: app,
            identifier: "library.folder.card.10000000-0000-0000-0000-000000000001"
        )

        XCTAssertTrue(element(in: app, identifier: "library.search").waitForExistence(timeout: 5))
        XCTAssertTrue(importedFolder.waitForExistence(timeout: 5))
        importedFolder.tap()

        XCTAssertTrue(app.staticTexts["Imported From Canvascope"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Imported From Lectra"].exists)
    }

    func testLibraryNewMenuOnlyShowsImplementedActions() {
        let app = launchApp(scenario: .library)
        let newButton = element(in: app, identifier: "library.new")

        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.tap()

        XCTAssertTrue(app.staticTexts["Import PDF"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Image"].exists)
        XCTAssertTrue(app.staticTexts["QuickNote"].exists)
        XCTAssertFalse(app.staticTexts["Import Gradescope Template"].exists)
        XCTAssertFalse(app.staticTexts["Take Photo"].exists)
        XCTAssertFalse(app.staticTexts["Scan Documents"].exists)
        XCTAssertFalse(app.staticTexts["Quick Record"].exists)
        XCTAssertFalse(app.staticTexts["Study Set"].exists)
    }

    func testCourseAndSubmissionIntegrationsAreNotShown() {
        let app = launchApp(scenario: .library)

        XCTAssertTrue(
            element(in: app, identifier: "library.search").waitForExistence(timeout: 5)
        )
        XCTAssertFalse(element(in: app, identifier: "library.section.courseBrain").exists)
        XCTAssertFalse(element(in: app, identifier: "library.section.gradescope").exists)
    }

    func testLibraryFixtureShowsDocumentCardsAndOptions() {
        let app = launchApp(scenario: .library)
        let reviewCard = element(in: app, identifier: "library.document.card.\(reviewPacketID)")

        XCTAssertTrue(
            element(in: app, identifier: "library.search").waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            element(in: app, identifier: "library.account").exists
        )
        XCTAssertTrue(
            element(in: app, identifier: "library.sidebarToggle").exists
        )
        XCTAssertTrue(
            reviewCard.waitForExistence(timeout: 5)
        )
        XCTAssertTrue(reviewCard.label.contains("Last modified"))
        XCTAssertTrue(
            element(in: app, identifier: "library.document.options.\(reviewPacketID)").exists
        )
    }

    private func drawLine(on element: XCUIElement, from start: CGVector, to end: CGVector) {
        element.coordinate(withNormalizedOffset: start)
            .press(
                forDuration: 0.05,
                thenDragTo: element.coordinate(withNormalizedOffset: end)
            )
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
