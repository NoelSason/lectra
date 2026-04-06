import XCTest

final class LectraSmokeUITests: LectraUITestCase {
    private let reviewPacketID = "20000000-0000-0000-0000-000000000001"

    func testCompactEditorShowsOverflowMenu() {
        let app = launchApp(scenario: .editorCompact)

        XCTAssertTrue(
            element(in: app, identifier: "editor.more").waitForExistence(timeout: 5)
        )
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

    func testGradescopeTechnicalDetailsStartCollapsed() {
        let app = launchApp(scenario: .gradescope)
        let disclosure = element(in: app, identifier: "gradescope.diagnostics.disclosure")
        let body = element(in: app, identifier: "gradescope.diagnostics.body")

        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertFalse(body.exists)
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
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
}
