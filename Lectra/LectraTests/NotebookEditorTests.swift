import XCTest
import UIKit
@testable import Lectra

final class NotebookEditorTests: XCTestCase {

    // MARK: Auto-indentation

    func testIndentAddedAfterColon() {
        XCTAssertEqual(PythonSyntax.nextLineIndent(currentLine: "for i in range(10):"), "    ")
    }

    func testIndentMatchesExistingIndentation() {
        XCTAssertEqual(PythonSyntax.nextLineIndent(currentLine: "    x = 1"), "    ")
    }

    func testIndentNestsAfterColon() {
        XCTAssertEqual(PythonSyntax.nextLineIndent(currentLine: "    if ready:"), "        ")
    }

    func testNoIndentForPlainLine() {
        XCTAssertEqual(PythonSyntax.nextLineIndent(currentLine: "x = 1"), "")
    }

    // MARK: Syntax highlighting

    @MainActor
    func testKeywordIsColored() {
        let font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let attributed = PythonSyntax.highlighted("def go():", font: font)
        let color = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(color, UIColor(hex: 0xC586C0))  // keyword purple
    }

    @MainActor
    func testNumberIsColored() {
        let font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let attributed = PythonSyntax.highlighted("x = 42", font: font)
        let color = attributed.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? UIColor
        XCTAssertEqual(color, UIColor(hex: 0xB5CEA8))  // number green
    }

    @MainActor
    func testKeywordInsideStringStaysStringColored() {
        let font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let attributed = PythonSyntax.highlighted("\"def\"", font: font)
        // index 1 is the 'd' inside the string literal
        let color = attributed.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? UIColor
        XCTAssertEqual(color, UIColor(hex: 0xCE9178))  // string orange wins over keyword
    }

    // MARK: Run-shortcut key commands

    @MainActor
    func testCodeTextViewExposesRunKeyCommands() {
        let view = CodeTextView()

        view.commandsEnabled = false
        XCTAssertNil(view.keyCommands)

        view.commandsEnabled = true
        let commands = view.keyCommands ?? []
        XCTAssertEqual(commands.count, 3)
        XCTAssertTrue(commands.allSatisfy { $0.input == "\r" })
        let modifiers = Set(commands.map { $0.modifierFlags.rawValue })
        XCTAssertTrue(modifiers.contains(UIKeyModifierFlags.shift.rawValue))
        XCTAssertTrue(modifiers.contains(UIKeyModifierFlags.command.rawValue))
        XCTAssertTrue(modifiers.contains(UIKeyModifierFlags.alternate.rawValue))
    }

    // MARK: Document cell helpers (drive the run-and-advance behavior)

    @MainActor
    func testAddCellReturnsNewCellAndNextCodeCellSkipsMarkdown() {
        let doc = NotebookDocument(title: "t", cells: [])
        let first = doc.addCell(.code, after: nil)
        let middle = doc.addCell(.markdown, after: first)
        let last = doc.addCell(.code, after: middle)

        XCTAssertEqual(doc.cells.count, 3)
        XCTAssertEqual(doc.nextCodeCell(after: first)?.id, last.id)  // skips the markdown cell
        XCTAssertNil(doc.nextCodeCell(after: last))
    }
}
