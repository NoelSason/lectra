import XCTest

/// Reproduces the report that shifted characters (parens, quotes, braces) don't
/// type into a notebook code cell. Drives a real notebook via the library
/// scenario and types special characters through the UI-test key path.
final class NotebookKeyboardUITests: LectraUITestCase {

    func testCodeCellAcceptsShiftedCharacters() {
        let app = launchApp(scenario: .library)

        let newButton = element(in: app, identifier: "library.new")
        XCTAssertTrue(newButton.waitForExistence(timeout: 8), "New button missing")
        newButton.tap()

        let pythonNotebook = app.buttons["Python Notebook"]
        XCTAssertTrue(pythonNotebook.waitForExistence(timeout: 5), "Python Notebook option missing")
        pythonNotebook.tap()

        let editor = element(in: app, identifier: "notebook.code.editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 8), "Code editor missing")
        editor.tap()

        let sample = "print(\"hi\") {}"
        editor.typeText(sample)

        let value = (editor.value as? String) ?? ""
        XCTAssertEqual(value, sample, "Shifted characters were not typed correctly")
    }
}
