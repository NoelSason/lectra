import XCTest
import UIKit
@testable import Lectra

/// Thorough coverage of the notebook code-cell highlighter and auto-indenter.
/// Colors follow the VS Code "Dark+" palette baked into `PythonSyntax`.
final class PythonSyntaxHighlightingTests: XCTestCase {

    private let keywordColor = UIColor(hex: 0xC586C0)
    private let builtinColor = UIColor(hex: 0xDCDCAA)
    private let stringColor  = UIColor(hex: 0xCE9178)
    private let numberColor  = UIColor(hex: 0xB5CEA8)
    private let commentColor = UIColor(hex: 0x6A9955)

    // MARK: Auto-indentation

    func testIndentAfterColon() {
        XCTAssertEqual(PythonSyntax.nextLineIndent(currentLine: "for i in range(10):"), "    ")
    }

    func testIndentMatchesExisting() {
        XCTAssertEqual(PythonSyntax.nextLineIndent(currentLine: "    x = 1"), "    ")
    }

    func testIndentNestsAfterColonInsideBlock() {
        XCTAssertEqual(PythonSyntax.nextLineIndent(currentLine: "    if ready:"), "        ")
    }

    func testNoIndentForPlainLine() {
        XCTAssertEqual(PythonSyntax.nextLineIndent(currentLine: "x = 1"), "")
    }

    func testNoIndentForEmptyLine() {
        XCTAssertEqual(PythonSyntax.nextLineIndent(currentLine: ""), "")
    }

    func testDeeplyNestedColonAddsOneLevel() {
        XCTAssertEqual(PythonSyntax.nextLineIndent(currentLine: "        while x:"), "            ")
    }

    func testTrailingWhitespaceBeforeColonStillIndents() {
        XCTAssertEqual(PythonSyntax.nextLineIndent(currentLine: "def f():   "), "    ")
    }

    func testTabIndentationIsPreserved() {
        XCTAssertEqual(PythonSyntax.nextLineIndent(currentLine: "\tx = 1"), "\t")
    }

    // MARK: Highlighting — single tokens

    @MainActor func testKeywordIsPurple() {
        XCTAssertEqual(color("def go():", at: 0), keywordColor)
    }

    @MainActor func testBuiltinIsYellow() {
        XCTAssertEqual(color("print(x)", at: 0), builtinColor)
    }

    @MainActor func testNumberIsGreen() {
        XCTAssertEqual(color("x = 42", at: 4), numberColor)
    }

    @MainActor func testFloatLiteralIsGreen() {
        XCTAssertEqual(color("y = 3.14", at: 4), numberColor)
    }

    @MainActor func testDoubleQuotedStringIsOrange() {
        XCTAssertEqual(color("\"hi\"", at: 0), stringColor)
    }

    @MainActor func testSingleQuotedStringIsOrange() {
        XCTAssertEqual(color("'hi'", at: 0), stringColor)
    }

    @MainActor func testTripleQuotedStringIsOrange() {
        XCTAssertEqual(color("\"\"\"abc\"\"\"", at: 3), stringColor)
    }

    @MainActor func testCommentIsGreen() {
        XCTAssertEqual(color("# note", at: 0), commentColor)
    }

    @MainActor func testPlainIdentifierUsesDefaultColor() {
        XCTAssertEqual(color("foo", at: 0), PythonSyntax.defaultColor)
    }

    @MainActor func testCustomDefaultColorIsApplied() {
        let font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let attr = PythonSyntax.highlighted("foo", font: font, defaultColor: .red)
        XCTAssertEqual(attr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .red)
    }

    // MARK: Highlighting — precedence (later passes win)

    @MainActor func testKeywordInsideStringStaysString() {
        XCTAssertEqual(color("\"def\"", at: 1), stringColor)
    }

    @MainActor func testNumberInsideStringStaysString() {
        XCTAssertEqual(color("\"42\"", at: 1), stringColor)
    }

    @MainActor func testKeywordInsideCommentStaysComment() {
        XCTAssertEqual(color("# def", at: 2), commentColor)
    }

    @MainActor func testDigitInsideIdentifierIsNotNumber() {
        // No word boundary between 'x' and '1', so '1' is not a number token.
        XCTAssertEqual(color("x1 = 0", at: 1), PythonSyntax.defaultColor)
    }

    @MainActor func testEachKeywordInMultiKeywordLineIsColored() {
        let line = "if x and y:"
        XCTAssertEqual(color(line, at: 0), keywordColor)            // "if"
        XCTAssertEqual(color(line, at: 5), keywordColor)            // "and"
    }

    @MainActor func testFontIsAppliedAcrossString() {
        let font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let attr = PythonSyntax.highlighted("print(1)", font: font)
        XCTAssertEqual(attr.attribute(.font, at: 0, effectiveRange: nil) as? UIFont, font)
    }

    // MARK: Helpers

    @MainActor
    private func color(_ source: String, at index: Int) -> UIColor? {
        let font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let attr = PythonSyntax.highlighted(source, font: font)
        return attr.attribute(.foregroundColor, at: index, effectiveRange: nil) as? UIColor
    }
}
