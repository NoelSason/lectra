//
//  TerminalSession.swift
//  Lectra
//
//  View model for one terminal: owns the shell environment, the git runtime, and
//  the executor, holds the scrollback transcript, and runs submitted command
//  lines. State persists for the lifetime of the screen, like a shell session.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class TerminalSession: ObservableObject {
    @Published var transcript = AttributedString("")
    @Published var isRunning = false
    @Published private(set) var prompt = "$ "

    let env: ShellEnvironment
    let git = GitRuntime()
    private lazy var executor = ShellExecutor(env: env, git: git)

    private var history: [String] = []
    private var historyIndex = 0
    private let maxTranscript = 200_000

    init(startDirectory: URL? = nil) {
        self.env = ShellEnvironment(startDirectory: startDirectory)
        append("Lectra terminal — type `help` for commands.\n", color: LectraColor.textTertiary)
        refreshPrompt()
    }

    // MARK: Prompt

    private func refreshPrompt() {
        let home = env.vars["HOME"] ?? ""
        var path = env.cwd.path
        if path == home { path = "~" }
        else if path.hasPrefix(home + "/") { path = "~" + path.dropFirst(home.count) }
        prompt = "\(path) $ "
    }

    // MARK: Running

    func submit(_ raw: String) {
        let command = raw
        // Echo the prompt + command into the transcript.
        append(prompt, color: LectraColor.success)
        append(command + "\n", color: LectraColor.textPrimary)

        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { refreshPrompt(); return }

        if history.last != trimmed { history.append(trimmed) }
        historyIndex = history.count

        isRunning = true
        Task { [weak self] in
            guard let self else { return }
            await executor.run(command) { text, isErr in
                self.handleOutput(text, isErr: isErr)
            }
            self.isRunning = false
            self.refreshPrompt()
        }
    }

    private func handleOutput(_ text: String, isErr: Bool) {
        // A form feed (from `clear`) wipes the scrollback.
        if text.contains("\u{0C}") {
            transcript = AttributedString("")
            let rest = text.replacingOccurrences(of: "\u{0C}", with: "")
            if !rest.isEmpty { append(rest, color: LectraColor.textPrimary) }
            return
        }
        append(text, color: isErr ? LectraColor.accentDestructive : LectraColor.textPrimary)
    }

    private func append(_ text: String, color: Color) {
        var run = AttributedString(text)
        run.foregroundColor = color
        transcript.append(run)
        if transcript.characters.count > maxTranscript {
            let overflow = transcript.characters.count - maxTranscript
            let start = transcript.characters.index(transcript.startIndex, offsetBy: overflow)
            transcript = AttributedString(transcript[start...])
        }
    }

    // MARK: History (up/down arrows)

    func historyPrev(current: String) -> String? {
        guard !history.isEmpty else { return nil }
        historyIndex = max(0, historyIndex - 1)
        return history[historyIndex]
    }
    func historyNext() -> String? {
        guard !history.isEmpty else { return nil }
        historyIndex = min(history.count, historyIndex + 1)
        return historyIndex < history.count ? history[historyIndex] : ""
    }

    func shutdown() { git.shutdown() }
}
