//
//  SourceEditorView.swift
//  Lectra
//
//  A fast, full-screen code editor backed by a real file on disk. Built to fix
//  the problems of the old modal editor:
//   - Speed: syntax highlighting is debounced and applied directly to the live
//     textStorage (no re-assigning attributedText on every keystroke, which forced
//     a full relayout). The text view never wraps, so layout stays cheap.
//   - Accurate line numbers: a separate gutter draws one number per logical line.
//     Because wrapping is off, line index maps straight to vertical position -
//     no layoutManager walking (which also forced slow TextKit-1 mode).
//   - Persistence: edits go to the file URL you pass in; there is no hidden copy.
//

import SwiftUI
import UIKit

struct SourceEditorView: UIViewRepresentable {
    @Binding var text: String
    let language: CodeLanguage
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> EditorContainerView {
        let container = EditorContainerView()
        let tv = container.textView
        tv.delegate = context.coordinator
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.spellCheckingType = .no
        tv.keyboardType = .asciiCapable
        tv.text = text
        context.coordinator.highlightNow(tv)
        return container
    }

    func updateUIView(_ container: EditorContainerView, context: Context) {
        let tv = container.textView
        if tv.text != text {
            let sel = tv.selectedRange
            tv.text = text
            context.coordinator.highlightNow(tv)
            tv.selectedRange = sel
            container.gutter.setNeedsDisplay()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: SourceEditorView
        private var highlightWork: DispatchWorkItem?
        init(_ parent: SourceEditorView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.onChange()
            (textView.superview as? EditorContainerView)?.gutter.setNeedsDisplay()
            scheduleHighlight(textView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            (scrollView.superview as? EditorContainerView)?.gutter.setNeedsDisplay()
        }

        // Debounce: only re-highlight once typing pauses, so fast typing never
        // blocks on regex passes.
        private func scheduleHighlight(_ textView: UITextView) {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.highlightNow(textView)
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }

        func highlightNow(_ textView: UITextView) {
            let sel = textView.selectedRange
            let attributed = SyntaxHighlighter.attributed(textView.text, language: parent.language)
            let storage = textView.textStorage
            storage.beginEditing()
            storage.setAttributes([:], range: NSRange(location: 0, length: storage.length))
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
                storage.setAttributes(attrs, range: range)
            }
            storage.endEditing()
            textView.selectedRange = sel
        }
    }
}

/// Hosts the text view plus a left gutter that paints line numbers. The gutter is
/// pinned (doesn't scroll horizontally) and redraws on scroll/edit.
final class EditorContainerView: UIView {
    let textView: CodeScrollTextView
    let gutter: GutterView
    private let gutterWidth: CGFloat = 46

    override init(frame: CGRect) {
        let layout = NSTextContainer()
        textView = CodeScrollTextView(frame: .zero, textContainer: nil)
        gutter = GutterView()
        super.init(frame: frame)
        _ = layout

        textView.backgroundColor = UIColor(LectraColor.surfaceOverlay)
        textView.font = SyntaxHighlighter.font
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 40, right: 12)
        textView.contentInsetAdjustmentBehavior = .never
        // Disable wrapping: each logical line is one visual line, so line numbers
        // map directly to position and layout is cheap.
        textView.textContainer.lineBreakMode = .byClipping
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.size = CGSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude)
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true

        gutter.backgroundColor = UIColor(LectraColor.surfaceOverlay)
        gutter.textView = textView
        gutter.isUserInteractionEnabled = false

        addSubview(textView)
        addSubview(gutter)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gutter.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        textView.frame = CGRect(x: gutterWidth, y: 0, width: bounds.width - gutterWidth, height: bounds.height)
    }
}

/// Text view subclass that forwards horizontal-scroll-free behavior; exists so we
/// can keep a clean reference type and tweak behavior later.
final class CodeScrollTextView: UITextView {}

/// Draws right-aligned line numbers aligned to the text view's lines. Uses the
/// monospaced line height and the text view's vertical offset - O(visible lines),
/// and never touches the layout manager.
final class GutterView: UIView {
    weak var textView: UITextView?
    private let numberColor = UIColor(red: 0.55, green: 0.52, blue: 0.50, alpha: 0.8)
    private let numberFont = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    override func draw(_ rect: CGRect) {
        guard let tv = textView else { return }
        let lineHeight = SyntaxHighlighter.font.lineHeight
        let topInset = tv.textContainerInset.top
        let offsetY = tv.contentOffset.y
        let text = tv.text as NSString

        // Count logical lines and their start offsets up front (cheap, O(n)).
        var lineStarts: [Int] = [0]
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byLines) { _, _, enclosing, _ in
            let end = enclosing.location + enclosing.length
            if end < text.length { lineStarts.append(end) }
        }

        let para = NSMutableParagraphStyle(); para.alignment = .right
        let attrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: numberColor, .paragraphStyle: para]

        let visibleTop = offsetY - lineHeight
        let visibleBottom = offsetY + bounds.height + lineHeight
        for (idx, _) in lineStarts.enumerated() {
            let y = topInset + CGFloat(idx) * lineHeight - offsetY
            let absoluteY = topInset + CGFloat(idx) * lineHeight
            if absoluteY < visibleTop || absoluteY > visibleBottom { continue }
            let r = CGRect(x: 0, y: y, width: bounds.width - 6, height: lineHeight)
            ("\(idx + 1)" as NSString).draw(in: r, withAttributes: attrs)
        }
    }
}
