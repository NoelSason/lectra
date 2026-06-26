//
//  CodeEditorView.swift
//  Lectra
//
//  A basic in-app code editor for text files pulled from GitHub (or created
//  locally): monospaced, line-numbered, with lightweight syntax highlighting for
//  common languages and a commit/push bar for GitHub-linked files. Pushes are
//  conflict-guarded by GitHubService.
//

import SwiftUI
import UIKit

// MARK: - Local code-file storage

/// Persists plain-text code files under Documents/code/<id>.<ext>.
struct CodeFileStore {
    static let shared = CodeFileStore()
    private let fileManager = FileManager.default

    private var directory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("code", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func url(id: UUID, ext: String) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(ext)")
    }

    @discardableResult
    func save(_ text: String, to url: URL) -> Bool {
        (try? text.data(using: .utf8)?.write(to: url, options: .atomic)) != nil
    }

    func load(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}

// MARK: - Editor screen

struct CodeEditorView: View {
    let fileName: String
    /// Key used to look up / store this file's GitHub link (path for code files).
    let linkKey: String
    let fileURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var dirty = false
    @State private var pushing = false
    @State private var notice: String?
    @State private var link: GitLink?

    init(fileName: String, linkKey: String, fileURL: URL) {
        self.fileName = fileName
        self.linkKey = linkKey
        self.fileURL = fileURL
        _text = State(initialValue: CodeFileStore.shared.load(fileURL))
        _link = State(initialValue: GitLinkStore.shared.link(for: linkKey))
    }

    var body: some View {
        VStack(spacing: 0) {
            HighlightedCodeTextView(text: $text, language: CodeLanguage(fileExtension: fileURL.pathExtension)) {
                dirty = true
            }
            if let link { pushBar(link) }
        }
        .background(LectraColor.surfaceOverlay.ignoresSafeArea())
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .foregroundStyle(dirty ? LectraColor.accentSoft : LectraColor.textTertiary)
                    .disabled(!dirty)
            }
        }
        .onDisappear { if dirty { save() } }
        .alert("GitHub", isPresented: noticePresented) {
            Button("OK", role: .cancel) {}
        } message: { Text(notice ?? "") }
        .preferredColorScheme(.dark)
    }

    private var noticePresented: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    private func pushBar(_ link: GitLink) -> some View {
        HStack(spacing: LectraSpacing.sm) {
            Image(systemName: "arrow.triangle.branch").foregroundStyle(LectraColor.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(link.repoFullName).font(LectraTypography.footnoteBold)
                    .foregroundStyle(LectraColor.textSecondary)
                Text("\(link.branch) · \(link.path)").font(LectraTypography.footnote)
                    .foregroundStyle(LectraColor.textTertiary).lineLimit(1)
            }
            Spacer()
            if pushing {
                ProgressView().controlSize(.mini).tint(LectraColor.accentSoft)
            } else {
                Button { push(link) } label: {
                    Label("Commit & push", systemImage: "arrow.up.circle.fill")
                        .font(LectraTypography.footnoteBold)
                        .foregroundStyle(LectraColor.accentSoft)
                }
            }
        }
        .padding(.horizontal, LectraSpacing.lg)
        .padding(.vertical, LectraSpacing.sm)
        .background(LectraColor.surfaceOverlay)
        .overlay(alignment: .top) { Rectangle().fill(LectraColor.edgeStroke).frame(height: 1) }
    }

    private func save() {
        CodeFileStore.shared.save(text, to: fileURL)
        dirty = false
    }

    private func push(_ link: GitLink) {
        save()
        pushing = true
        Task {
            do {
                let data = Data(text.utf8)
                let newSha = try await GitHubService.shared.commit(
                    data, link: link, message: "Update \(link.path) from Lectra")
                var updated = link
                updated.baseSha = newSha
                GitLinkStore.shared.set(updated, for: linkKey)
                self.link = updated
                notice = "Pushed to \(link.repoFullName)."
            } catch {
                notice = error.localizedDescription
            }
            pushing = false
        }
    }
}

// MARK: - Languages

enum CodeLanguage {
    case python, javascript, json, markdown, plain

    init(fileExtension ext: String) {
        switch ext.lowercased() {
        case "py": self = .python
        case "js", "ts", "jsx", "tsx": self = .javascript
        case "json": self = .json
        case "md", "markdown": self = .markdown
        default: self = .plain
        }
    }

    var keywords: Set<String> {
        switch self {
        case .python:
            return ["def", "class", "return", "if", "elif", "else", "for", "while", "import",
                    "from", "as", "with", "try", "except", "finally", "raise", "in", "not",
                    "and", "or", "is", "None", "True", "False", "lambda", "yield", "async",
                    "await", "global", "nonlocal", "pass", "break", "continue", "del"]
        case .javascript:
            return ["const", "let", "var", "function", "return", "if", "else", "for", "while",
                    "class", "extends", "new", "this", "import", "from", "export", "default",
                    "async", "await", "try", "catch", "finally", "throw", "typeof", "instanceof",
                    "null", "undefined", "true", "false", "switch", "case", "break", "continue"]
        default: return []
        }
    }

    var lineComment: String? {
        switch self {
        case .python: return "#"
        case .javascript: return "//"
        default: return nil
        }
    }
}

// MARK: - Highlighter

enum SyntaxHighlighter {
    static let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    // Lectra-flavored token colors.
    private static let base = UIColor(red: 0.93, green: 0.91, blue: 0.90, alpha: 1)
    private static let keyword = UIColor(red: 0.78, green: 0.55, blue: 1.0, alpha: 1)
    private static let string = UIColor(red: 0.55, green: 0.83, blue: 0.56, alpha: 1)
    private static let comment = UIColor(red: 0.55, green: 0.52, blue: 0.50, alpha: 1)
    private static let number = UIColor(red: 1.0, green: 0.70, blue: 0.45, alpha: 1)
    private static let heading = UIColor(red: 1.0, green: 0.42, blue: 0.36, alpha: 1)

    static func attributed(_ text: String, language: CodeLanguage) -> NSAttributedString {
        if language == .python {
            return PythonSyntax.highlighted(text, font: font)
        }

        let full = NSRange(text.startIndex..., in: text)
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: base
        ])

        if language == .markdown {
            apply(#"(?m)^#{1,6}\s.*$"#, in: text, full: full, color: heading, to: result)
            apply(#"`[^`\n]*`"#, in: text, full: full, color: string, to: result)
            return result
        }

        // Keywords (whole-word).
        if !language.keywords.isEmpty {
            let pattern = "\\b(" + language.keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")\\b"
            apply(pattern, in: text, full: full, color: keyword, to: result)
        }
        // Numbers.
        apply(#"\b\d+(\.\d+)?\b"#, in: text, full: full, color: number, to: result)
        // Strings (single, double, and triple-quoted).
        apply(#"("""[\s\S]*?"""|'''[\s\S]*?'''|"(\\.|[^"\\\n])*"|'(\\.|[^'\\\n])*')"#,
              in: text, full: full, color: string, to: result)
        // Line comments last, so a `#`/`//` wins over tokens inside it.
        if let marker = language.lineComment {
            apply("(?m)" + NSRegularExpression.escapedPattern(for: marker) + ".*$",
                  in: text, full: full, color: comment, to: result)
        }
        return result
    }

    private static func apply(_ pattern: String, in text: String, full: NSRange,
                              color: UIColor, to result: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        for match in regex.matches(in: text, range: full) {
            result.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

// MARK: - Line-numbered, highlighted text view

struct HighlightedCodeTextView: UIViewRepresentable {
    @Binding var text: String
    let language: CodeLanguage
    var onChange: () -> Void

    func makeUIView(context: Context) -> LineNumberTextView {
        let view = LineNumberTextView()
        view.delegate = context.coordinator
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.spellCheckingType = .no
        // Leave keyboardType at .default: .asciiCapable drops hardware-keyboard
        // shifted symbols (e.g. Shift+9 inserts "9" instead of "(").
        view.backgroundColor = UIColor(LectraColor.surfaceOverlay)
        view.alwaysBounceVertical = true
        view.attributedText = SyntaxHighlighter.attributed(text, language: language)
        return view
    }

    func updateUIView(_ view: LineNumberTextView, context: Context) {
        // Keep the coordinator's parent current so language/onChange don't go
        // stale across file switches (Python highlighting + auto-indent depend on
        // the live language).
        context.coordinator.parent = self
        // Only push external changes; avoid clobbering the user's cursor mid-typing.
        if view.text != text {
            let selected = view.selectedRange
            view.attributedText = SyntaxHighlighter.attributed(text, language: language)
            view.selectedRange = selected
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: HighlightedCodeTextView
        init(_ parent: HighlightedCodeTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            let selected = textView.selectedRange
            parent.text = textView.text
            // Re-highlight in place, preserving the caret.
            textView.attributedText = SyntaxHighlighter.attributed(
                textView.text, language: parent.language)
            textView.selectedRange = selected
            parent.onChange()
            (textView as? LineNumberTextView)?.setNeedsDisplay()
        }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText replacement: String) -> Bool {
            guard parent.language == .python, replacement == "\n" else { return true }
            let ns = textView.text as NSString
            let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
            let currentLine = ns.substring(with: lineRange)
            let insertion = "\n" + PythonSyntax.nextLineIndent(currentLine: currentLine)
            let updated = ns.replacingCharacters(in: range, with: insertion)
            let selected = NSRange(location: range.location + (insertion as NSString).length, length: 0)

            parent.text = updated
            textView.attributedText = SyntaxHighlighter.attributed(updated, language: parent.language)
            textView.selectedRange = selected
            parent.onChange()
            (textView as? LineNumberTextView)?.setNeedsDisplay()
            return false
        }
    }
}

/// UITextView that paints line numbers in a left gutter. Because the numbers are
/// drawn in the view's own coordinate space inside `draw(_:)`, they scroll with
/// the content for free.
final class LineNumberTextView: UITextView {
    private let gutterWidth: CGFloat = 40
    private let gutterColor = UIColor(red: 0.55, green: 0.52, blue: 0.50, alpha: 0.7)

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        font = SyntaxHighlighter.font
        textContainerInset = UIEdgeInsets(top: 12, left: gutterWidth, bottom: 12, right: 12)
        contentInsetAdjustmentBehavior = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.fill(.zero) // no-op to keep context alive

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: gutterColor
        ]

        // Walk line fragments and draw a number on the first fragment of each
        // logical line (those that start at a newline boundary).
        layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: textStorage.length)) {
            [weak self] _, usedRect, _, glyphRange, _ in
            guard let self else { return }
            let charIndex = self.layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil).location
            if charIndex == 0 || (self.textStorage.string as NSString).character(at: charIndex - 1) == 10 {
                let lineNumber = self.lineNumber(at: charIndex)
                let y = usedRect.minY + self.textContainerInset.top
                let numberRect = CGRect(x: 0, y: y, width: self.gutterWidth - 6, height: usedRect.height)
                ("\(lineNumber)" as NSString).draw(
                    in: numberRect,
                    withAttributes: attrs.merging([.paragraphStyle: Self.rightAligned]) { $1 })
            }
        }
    }

    private func lineNumber(at charIndex: Int) -> Int {
        let prefix = (textStorage.string as NSString).substring(to: charIndex)
        return prefix.reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }
    }

    private static let rightAligned: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.alignment = .right
        return p
    }()
}
