//
//  TerminalView.swift
//  Lectra
//
//  The terminal screen: a scrollback transcript over a monospace command line.
//  Presented full-screen from the Library, styled to match the app.
//

import SwiftUI

struct TerminalView: View {
    @StateObject private var session: TerminalSession
    @State private var input = ""
    @State private var ranInitial = false
    @FocusState private var inputFocused: Bool
    /// An optional command to run automatically on first appearance (e.g. a
    /// `git clone` queued from the GitHub browser).
    var initialCommand: String?
    var onClose: (() -> Void)?

    init(startDirectory: URL? = nil, initialCommand: String? = nil, onClose: (() -> Void)? = nil) {
        _session = StateObject(wrappedValue: TerminalSession(startDirectory: startDirectory))
        self.initialCommand = initialCommand
        self.onClose = onClose
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
            inputFocused = true
            Task {
                try? await session.git.start()
                if !ranInitial, let initialCommand, !initialCommand.isEmpty {
                    ranInitial = true
                    session.submit(initialCommand)
                }
            }
        }
        .onDisappear { session.shutdown() }
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
                Text(session.transcript)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .id("bottom-anchor-host")
                Color.clear.frame(height: 1).id("bottom")
            }
            .onChange(of: session.transcript) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(session.prompt)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(LectraColor.success)
            TextField("", text: $input)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(LectraColor.textPrimary)
                .tint(LectraColor.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($inputFocused)
                .submitLabel(.go)
                .onSubmit(runCurrent)
                .onKeyPress(.upArrow) {
                    if let prev = session.historyPrev(current: input) { input = prev }
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    if let next = session.historyNext() { input = next }
                    return .handled
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(LectraColor.surfaceFloating)
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = true }
    }

    private func runCurrent() {
        let command = input
        input = ""
        session.submit(command)
        inputFocused = true
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
