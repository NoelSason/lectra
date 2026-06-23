//
//  NotebookCellView.swift
//  Lectra
//
//  One notebook cell. Markdown cells render to styled text and flip to a text
//  editor on tap; code cells show a monospace editor with a Run control and an
//  output panel. Styled entirely with Lectra design tokens.
//

import SwiftUI
import UIKit

struct NotebookCellView: View {
    @ObservedObject var cell: NotebookCell

    let onRun: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onChangeType: (NotebookCellType) -> Void

    @State private var isEditingMarkdown = false
    @State private var editorHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.sm) {
            header
            switch cell.type {
            case .markdown: markdownBody
            case .code:     codeBody
            }
        }
        .padding(LectraSpacing.md)
        .lectraCard()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: LectraSpacing.sm) {
            if cell.type == .code {
                Text(executionLabel)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LectraColor.accentSoft)
            } else {
                Label("Markdown", systemImage: "text.alignleft")
                    .labelStyle(.iconOnly)
                    .font(LectraTypography.caption)
                    .foregroundStyle(LectraColor.textTertiary)
            }
            Spacer()
            if cell.type == .code {
                runButton
            } else {
                Button {
                    LectraHaptics.tap()
                    withAnimation(LectraMotion.quick) { isEditingMarkdown.toggle() }
                } label: {
                    Image(systemName: isEditingMarkdown ? "checkmark" : "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LectraColor.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
            cellMenu
        }
    }

    private var executionLabel: String {
        if cell.isRunning { return "[*]" }
        if let n = cell.executionCount { return "[\(n)]" }
        return "[ ]"
    }

    private var runButton: some View {
        Button(action: onRun) {
            HStack(spacing: 5) {
                if cell.isRunning {
                    ProgressView().controlSize(.mini).tint(LectraColor.textPrimary)
                } else {
                    Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                }
                Text(cell.isRunning ? "Running" : "Run")
                    .font(LectraTypography.footnoteBold)
            }
            .foregroundStyle(LectraColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                Capsule().fill(LectraColor.accent.opacity(cell.isRunning ? 0.5 : 1.0)))
        }
        .buttonStyle(.plain)
        .disabled(cell.isRunning)
    }

    private var cellMenu: some View {
        Menu {
            if cell.type == .code {
                Button { onRun() } label: { Label("Run", systemImage: "play") }
                Button { onChangeType(.markdown) } label: { Label("Convert to Markdown", systemImage: "text.alignleft") }
            } else {
                Button { onChangeType(.code) } label: { Label("Convert to Code", systemImage: "chevron.left.forwardslash.chevron.right") }
            }
            Divider()
            Button { onMoveUp() } label: { Label("Move Up", systemImage: "arrow.up") }
            Button { onMoveDown() } label: { Label("Move Down", systemImage: "arrow.down") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("Delete Cell", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LectraColor.textTertiary)
                .frame(width: 30, height: 30)
        }
    }

    // MARK: Markdown

    @ViewBuilder
    private var markdownBody: some View {
        if isEditingMarkdown {
            sourceEditor(placeholder: "Write markdown…", monospaced: false)
        } else if cell.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Empty markdown cell — tap the pencil to edit.")
                .font(LectraTypography.body)
                .foregroundStyle(LectraColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture { isEditingMarkdown = true }
        } else {
            MarkdownText(cell.source)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { isEditingMarkdown = true }
        }
    }

    // MARK: Code

    @ViewBuilder
    private var codeBody: some View {
        sourceEditor(placeholder: "# Write Python…", monospaced: true)
        if let output = cell.output, !output.isEmpty {
            CellOutputView(output: output)
        }
    }

    private func sourceEditor(placeholder: String, monospaced: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            if cell.source.isEmpty {
                Text(placeholder)
                    .font(monospaced ? .system(.body, design: .monospaced) : LectraTypography.body)
                    .foregroundStyle(LectraColor.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            PlainTextEditor(text: $cell.source, codeMode: monospaced, height: $editorHeight)
                .frame(height: max(44, editorHeight))
        }
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                .fill(LectraColor.surfaceFloating.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                        .stroke(LectraColor.edgeStroke, lineWidth: 1)))
    }
}

// MARK: - Plain text editor (UITextView-backed)

/// A code/prose editor that, in `codeMode`, turns off smart quotes, smart
/// dashes, autocorrect, and autocapitalization — SwiftUI's `TextEditor` has no
/// way to disable smart punctuation, which corrupts Python (`"` → `”`). It also
/// self-sizes to its content via the `height` binding.
private struct PlainTextEditor: UIViewRepresentable {
    @Binding var text: String
    var codeMode: Bool
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = UIEdgeInsets(top: 10, left: 2, bottom: 10, right: 2)
        view.textContainer.lineFragmentPadding = 4
        view.textColor = UIColor(hex: 0xF6F1E7)               // LectraColor.textPrimary
        view.tintColor = LectraColor.accentUIColor
        view.font = Self.font(codeMode: codeMode)
        if codeMode {
            view.autocorrectionType = .no
            view.autocapitalizationType = .none
            view.smartQuotesType = .no
            view.smartDashesType = .no
            view.smartInsertDeleteType = .no
            view.spellCheckingType = .no
        }
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        recalcHeight(view)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    fileprivate func recalcHeight(_ view: UITextView) {
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width - 80
        let fitted = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        if abs(height - fitted) > 0.5 {
            DispatchQueue.main.async { height = fitted }
        }
    }

    private static func font(codeMode: Bool) -> UIFont {
        codeMode
            ? UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
            : UIFont.systemFont(ofSize: 15, weight: .regular)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: PlainTextEditor
        init(_ parent: PlainTextEditor) { self.parent = parent }
        func textViewDidChange(_ view: UITextView) {
            parent.text = view.text
            parent.recalcHeight(view)
        }
    }
}

// MARK: - Output

private struct CellOutputView: View {
    let output: CellOutput

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !output.stdout.isEmpty {
                outputText(output.stdout, color: LectraColor.textSecondary)
            }
            if !output.stderr.isEmpty {
                outputText(output.stderr, color: LectraColor.warning)
            }
            if let result = output.result, !result.isEmpty {
                outputText(result, color: LectraColor.accentSoft)
            }
            if let error = output.error, !error.isEmpty {
                outputText(error, color: LectraColor.accentDestructive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LectraSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                .fill(LectraColor.surfaceOverlay.opacity(0.6)))
    }

    private func outputText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

// MARK: - Minimal markdown renderer

/// A small block-level renderer good enough for Lectra's seeded notebooks:
/// headings, bullets, and inline emphasis. Keeps headings looking like headings
/// instead of literal `##` text.
struct MarkdownText: View {
    let source: String
    init(_ source: String) { self.source = source }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
    }

    private var blocks: [String] { source.components(separatedBy: "\n") }

    @ViewBuilder
    private func lineView(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            Spacer().frame(height: 2)
        } else if line.hasPrefix("### ") {
            Text(inline(String(line.dropFirst(4))))
                .font(LectraTypography.headlineMedium)
                .foregroundStyle(LectraColor.textPrimary)
        } else if line.hasPrefix("## ") {
            Text(inline(String(line.dropFirst(3))))
                .font(LectraTypography.titleSmall)
                .foregroundStyle(LectraColor.textPrimary)
        } else if line.hasPrefix("# ") {
            Text(inline(String(line.dropFirst(2))))
                .font(LectraTypography.title)
                .foregroundStyle(LectraColor.textPrimary)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 8) {
                Text("•").foregroundStyle(LectraColor.accentSoft)
                Text(inline(String(line.dropFirst(2))))
                    .foregroundStyle(LectraColor.textSecondary)
            }
            .font(LectraTypography.body)
        } else {
            Text(inline(line))
                .font(LectraTypography.body)
                .foregroundStyle(LectraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Inline emphasis (`**bold**`, `*italic*`, `code`) via AttributedString.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
