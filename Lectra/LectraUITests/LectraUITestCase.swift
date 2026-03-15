import XCTest

class LectraUITestCase: XCTestCase {
    enum Scenario: String {
        case auth
        case library
        case gradescope
        case editorCompact
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @discardableResult
    func launchApp(
        scenario: Scenario,
        contentSizeCategory: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("LECTRA_UI_TESTING")
        app.launchEnvironment["LECTRA_UI_TEST_SCENARIO"] = scenario.rawValue

        if let contentSizeCategory {
            app.launchEnvironment["UIPreferredContentSizeCategoryName"] = contentSizeCategory
        }

        app.launch()
        return app
    }

    func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}
