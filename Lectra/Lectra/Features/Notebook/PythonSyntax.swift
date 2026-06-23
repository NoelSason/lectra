//
//  PythonSyntax.swift
//  Lectra
//
//  Lightweight Python syntax highlighting and auto-indentation for notebook
//  code cells. Colors follow the widely-used VS Code "Dark+" palette so the
//  notebook reads like a familiar code editor.
//

import UIKit

enum PythonSyntax {

    // MARK: Palette (VS Code Dark+)

    static let defaultColor = UIColor(hex: 0xF6F1E7)   // matches LectraColor.textPrimary
    private static let keywordColor = UIColor(hex: 0xC586C0)   // purple
    private static let builtinColor = UIColor(hex: 0xDCDCAA)   // soft yellow
    private static let stringColor  = UIColor(hex: 0xCE9178)   // orange
    private static let numberColor  = UIColor(hex: 0xB5CEA8)   // light green
    private static let commentColor = UIColor(hex: 0x6A9955)   // green

    // MARK: Patterns

    private static let keyword = regex(
        "\\b(False|None|True|and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield|match|case)\\b")
    private static let builtin = regex(
        "\\b(print|len|range|int|str|float|bool|list|dict|set|tuple|input|open|enumerate|zip|map|filter|sum|min|max|abs|sorted|reversed|type|isinstance|repr|round|any|all|format)\\b")
    private static let number = regex("\\b\\d+(?:\\.\\d+)?\\b")
    private static let string = regex("(\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''|\"[^\"\\n]*\"|'[^'\\n]*')")
    private static let comment = regex("#[^\\n]*")

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are static and known-valid.
        try! NSRegularExpression(pattern: pattern)
    }

    // MARK: Highlighting

    /// Returns `text` colored as Python. Later passes (strings, comments) win
    /// over earlier ones, so a keyword inside a string stays string-colored.
    static func highlighted(_ text: String, font: UIFont, defaultColor: UIColor = defaultColor) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: defaultColor])
        let full = NSRange(location: 0, length: (text as NSString).length)

        apply(number, color: numberColor, to: attributed, text: text, full: full)
        apply(builtin, color: builtinColor, to: attributed, text: text, full: full)
        apply(keyword, color: keywordColor, to: attributed, text: text, full: full)
        apply(string, color: stringColor, to: attributed, text: text, full: full)
        apply(comment, color: commentColor, to: attributed, text: text, full: full)
        return attributed
    }

    private static func apply(_ regex: NSRegularExpression,
                              color: UIColor,
                              to attributed: NSMutableAttributedString,
                              text: String,
                              full: NSRange) {
        regex.enumerateMatches(in: text, range: full) { match, _, _ in
            if let range = match?.range {
                attributed.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
    }

    // MARK: Auto-indentation

    /// The whitespace a new line should start with, given the line the caret was
    /// on when Return was pressed: it matches the current line's indentation and
    /// adds one level (4 spaces) after a line ending in `:`.
    static func nextLineIndent(currentLine: String) -> String {
        let leading = currentLine.prefix { $0 == " " || $0 == "\t" }
        var indent = String(leading)
        let trimmed = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(":") {
            indent += "    "
        }
        return indent
    }
}
