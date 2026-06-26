//
//  TerminalView.swift
//  Lectra
//
//  The terminal screen: a scrollback transcript over a monospace command line.
//  Presented full-screen from the Library, styled to match the app.
//

import SwiftUI
import UIKit

struct TerminalView: View {
    @StateObject private var session: TerminalSession
    @State private var input = ""
    @State private var ranInitial = false
    @State private var inputFocused = false
    /// An optional command to run automatically on first appearance (e.g. a
    /// `git clone` queued from the GitHub browser).
    var initialCommand: String?
    var onClose: (() -> Void)?
    var onCommandFinished: ((String, Int32) -> Void)?

    init(
        startDirectory: URL? = nil,
        initialCommand: String? = nil,
        onClose: (() -> Void)? = nil,
        onCommandFinished: ((String, Int32) -> Void)? = nil
    ) {
        _session = StateObject(wrappedValue: TerminalSession(startDirectory: startDirectory))
        self.initialCommand = initialCommand
        self.onClose = onClose
        self.onCommandFinished = onCommandFinished
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(LectraColor.sidebarDivider)
            transcriptArea
            inputBar
        }
        .background(LectraColor.background.ignoresSafeArea())
        .onAppear {
            LectraPerformanceTrace.setActiveSurface(.terminal)
            inputFocused = true
            Task {
                try? await session.git.start()
                if !ranInitial, let initialCommand, !initialCommand.isEmpty {
                    ranInitial = true
                    session.submit(initialCommand, onFinish: onCommandFinished)
                }
            }
        }
        .onDisappear {
            session.shutdown()
            LectraPerformanceTrace.setActiveSurface(.unknown)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .foregroundStyle(LectraColor.accent)
            Text("Terminal")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(LectraColor.textPrimary)
            if session.isRunning {
                ProgressView().controlSize(.small).tint(LectraColor.accent)
            }
            Spacer()
            GitHubConnectionPill()
            if let onClose {
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LectraColor.textTertiary)
                        .font(.system(size: 20))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(session.transcriptChunks) { chunk in
                        Text(chunk.text)
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Color.clear.frame(height: 1).id("bottom")
            }
            .onChange(of: session.transcriptRevision) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(session.prompt)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(LectraColor.success)
                .padding(.top, 1)
            TerminalInputField(
                text: $input,
                isFocused: $inputFocused,
                onSubmit: runCurrent,
                onHistoryPrevious: {
                    if let prev = session.historyPrev(current: input) { input = prev }
                },
                onHistoryNext: {
                    if let next = session.historyNext() { input = next }
                },
                onComplete: { session.complete($0) }
            )
            .frame(height: TerminalTextView.lineHeight)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(LectraColor.surfaceFloating)
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = true }
    }

    private func runCurrent() {
        let command = input
        input = ""
        session.submit(command, onFinish: onCommandFinished)
        inputFocused = true
    }
}

/// A tiny UITextView-backed command line, matching the notebook/code editors.
/// UITextView lets iPadOS handle hardware-keyboard modifiers normally (Shift,
/// Command-A/C/V/X, etc.); we only intercept Return and arrow history.
private struct TerminalInputField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void
    let onHistoryPrevious: () -> Void
    let onHistoryNext: () -> Void
    /// Given the current line, returns the tab-completed line, or `nil` if there
    /// is nothing to complete.
    let onComplete: (String) -> String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> TerminalTextView {
        let view = TerminalTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.maximumNumberOfLines = 1
        view.textContainer.lineBreakMode = .byClipping
        view.contentInset = .zero
        view.scrollIndicatorInsets = .zero
        view.contentInsetAdjustmentBehavior = .never
        view.isScrollEnabled = false
        view.clipsToBounds = true
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.returnKeyType = .go
        view.onHistoryPrevious = { context.coordinator.parent.onHistoryPrevious() }
        view.onHistoryNext = { context.coordinator.parent.onHistoryNext() }
        view.onComplete = { context.coordinator.parent.onComplete($0) }
        view.onTextChanged = { context.coordinator.parent.text = $0 }
        return view
    }

    func updateUIView(_ view: TerminalTextView, context: Context) {
        context.coordinator.parent = self
        view.textColor = UIColor(LectraColor.textPrimary)
        view.tintColor = UIColor(LectraColor.accent)
        view.shouldFocusWhenAttached = isFocused
        view.onHistoryPrevious = { context.coordinator.parent.onHistoryPrevious() }
        view.onHistoryNext = { context.coordinator.parent.onHistoryNext() }
        view.onComplete = { context.coordinator.parent.onComplete($0) }
        view.onTextChanged = { context.coordinator.parent.text = $0 }
        if view.text != text {
            view.text = text
        }
        if isFocused, !view.isFirstResponder {
            DispatchQueue.main.async {
                if view.window != nil {
                    view.becomeFirstResponder()
                }
            }
        } else if !isFocused, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: TerminalInputField

        init(_ parent: TerminalInputField) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText replacement: String) -> Bool {
            guard replacement == "\n" else { return true }
            parent.text = textView.text
            parent.onSubmit()
            return false
        }
    }
}

private final class TerminalTextView: UITextView {
    static let lineHeight: CGFloat = 18

    var shouldFocusWhenAttached = false
    var onHistoryPrevious: (() -> Void)?
    var onHistoryNext: (() -> Void)?
    var onComplete: ((String) -> String?)?
    var onTextChanged: ((String) -> Void)?

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.lineHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if contentOffset != .zero {
            contentOffset = .zero
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(historyPrevious)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(historyNext)),
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(completePath))
        ]
    }

    @objc private func historyPrevious() {
        onHistoryPrevious?()
    }

    @objc private func historyNext() {
        onHistoryNext?()
    }

    @objc private func completePath() {
        let current = text ?? ""
        guard let completed = onComplete?(current), completed != current else { return }
        text = completed
        selectedRange = NSRange(location: (completed as NSString).length, length: 0)
        onTextChanged?(completed)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard shouldFocusWhenAttached, window != nil, !isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.shouldFocusWhenAttached, self.window != nil else { return }
            self.becomeFirstResponder()
        }
    }
}

/// Small status pill showing whether GitHub is connected, with a tap to connect.
private struct GitHubConnectionPill: View {
    @ObservedObject private var auth = GitHubAuth.shared

    var body: some View {
        Button {
            if !auth.isConnected { Task { await auth.connect() } }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(auth.isConnected ? LectraColor.success : LectraColor.textTertiary)
                    .frame(width: 7, height: 7)
                Text(auth.isConnected ? "GitHub" : "Connect GitHub")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LectraColor.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(LectraColor.surfaceElevated))
        }
        .disabled(auth.isWorking)
    }
}
