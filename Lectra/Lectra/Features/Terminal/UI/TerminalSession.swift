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

struct TerminalTranscriptChunk: Identifiable {
    let id = UUID()
    let text: AttributedString
    let characterCount: Int

    init(_ text: AttributedString) {
        self.text = text
        self.characterCount = text.characters.count
    }
}

@MainActor
final class TerminalSession: ObservableObject {
    @Published private(set) var transcriptChunks: [TerminalTranscriptChunk] = []
    @Published private(set) var transcriptRevision = 0
    @Published var isRunning = false
    @Published private(set) var prompt = "$ "

    let env: ShellEnvironment
    let git = GitRuntime()
    private let python = TerminalPythonRuntime()
    private lazy var executor = ShellExecutor(env: env, git: git)

    private var history: [String] = []
    private var historyIndex = 0
    private let maxTranscript = 200_000
    private let transcriptFlushDelay: TimeInterval = 1.0 / 30.0
    private var transcriptCharacterCount = 0
    private var pendingTranscript = AttributedString("")
    private var pendingTranscriptCharacterCount = 0
    private var transcriptFlushWorkItem: DispatchWorkItem?
    private var pythonMode = false
    private var pythonBuffer: [String] = []

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

    func submit(_ raw: String, onFinish: ((String, Int32) -> Void)? = nil) {
        let command = raw
        // Echo the prompt + command into the transcript.
        append(prompt, color: LectraColor.success)
        append(command + "\n", color: LectraColor.textPrimary)
        flushPendingTranscript()

        let trimmed = command.trimmingCharacters(in: .whitespaces)
        if pythonMode {
            handlePythonInput(command, trimmed: trimmed, onFinish: onFinish)
            return
        }

        guard !trimmed.isEmpty else {
            refreshPrompt()
            onFinish?(command, env.lastExitCode)
            return
        }

        remember(trimmed)

        if TerminalPythonRuntime.commandNames.contains(trimmed) {
            enterPythonMode()
            flushPendingTranscript()
            onFinish?(command, 0)
            return
        }

        isRunning = true
        Task { [weak self] in
            guard let self else { return }
            let exitCode = await LectraPerformanceTrace.withAsyncSignpost(.terminal, "TerminalCommand") {
                await self.executor.run(command) { text, isErr in
                    self.handleOutput(text, isErr: isErr)
                }
            }
            self.flushPendingTranscript()
            self.isRunning = false
            self.refreshPrompt()
            onFinish?(command, exitCode)
        }
    }

    // MARK: Tab completion

    /// Completes the last path-like token of `input` against the filesystem.
    /// Returns the new full input line, or `nil` when there is nothing to add
    /// (no match, or already at the longest shared prefix). Directories gain a
    /// trailing `/`; a single file match gains a trailing space, like bash.
    func complete(_ input: String) -> String? {
        // Isolate the final whitespace-separated token (the fragment to complete).
        let fragmentStart = input.lastIndex(of: " ").map { input.index(after: $0) } ?? input.startIndex
        let head = String(input[..<fragmentStart])
        let fragment = String(input[fragmentStart...])

        // Split the fragment into a directory part (kept verbatim) and the
        // partial leaf name we actually match against.
        let dirPart: String
        let partial: String
        if let slash = fragment.lastIndex(of: "/") {
            dirPart = String(fragment[...slash])
            partial = String(fragment[fragment.index(after: slash)...])
        } else {
            dirPart = ""
            partial = fragment
        }

        guard let dirURL = env.resolve(dirPart.isEmpty ? "." : dirPart) else { return nil }
        let options: FileManager.DirectoryEnumerationOptions = partial.hasPrefix(".") ? [] : [.skipsHiddenFiles]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options
        ) else { return nil }

        // Documents are shown under their title in this directory, so complete
        // against those friendly names (resolution maps them back to the UUID).
        let virtual = TerminalDocuments.virtualNames(in: dirURL)
        let matches: [(name: String, isDir: Bool)] = entries.compactMap { url in
            let name = virtual[url.lastPathComponent] ?? url.lastPathComponent
            guard name.hasPrefix(partial) else { return nil }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return (name, isDir)
        }

        guard !matches.isEmpty else { return nil }

        if matches.count == 1 {
            let match = matches[0]
            let suffix = match.isDir ? "/" : " "
            return head + dirPart + match.name + suffix
        }

        // Multiple matches: extend to the longest common prefix, if it adds
        // anything beyond what the user already typed.
        let common = Self.longestCommonPrefix(matches.map(\.name))
        guard common.count > partial.count else { return nil }
        return head + dirPart + common
    }

    private static func longestCommonPrefix(_ strings: [String]) -> String {
        guard var prefix = strings.first else { return "" }
        for string in strings.dropFirst() {
            while !string.hasPrefix(prefix) {
                prefix = String(prefix.dropLast())
                if prefix.isEmpty { return "" }
            }
        }
        return prefix
    }

    private func remember(_ command: String) {
        if history.last != command { history.append(command) }
        historyIndex = history.count
    }

    private func enterPythonMode() {
        pythonMode = true
        pythonBuffer.removeAll()
        append(TerminalPythonRuntime.replBanner, color: LectraColor.textTertiary)
        prompt = ">>> "
    }

    private func leavePythonMode() {
        pythonMode = false
        pythonBuffer.removeAll()
        refreshPrompt()
    }

    private func handlePythonInput(_ command: String, trimmed: String, onFinish: ((String, Int32) -> Void)?) {
        let lowered = trimmed.lowercased()
        if pythonBuffer.isEmpty, ["exit()", "quit()", "exit", "quit"].contains(lowered) {
            leavePythonMode()
            onFinish?(command, 0)
            return
        }

        if !trimmed.isEmpty { remember(trimmed) }
        pythonBuffer.append(command)

        if shouldContinuePythonInput(after: command) {
            prompt = "... "
            onFinish?(command, 0)
            return
        }

        let code = pythonBuffer.joined(separator: "\n")
        pythonBuffer.removeAll()
        prompt = ">>> "

        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onFinish?(command, 0)
            return
        }

        isRunning = true
        Task { [weak self] in
            guard let self else { return }
            let result = await LectraPerformanceTrace.withAsyncSignpost(.terminal, "PythonCommand") {
                await self.python.runInteractive(code)
            }
            let output = TerminalPythonRuntime.output(from: result, includeResult: true)
            if !output.stdout.isEmpty { self.handleOutput(output.stdout, isErr: false) }
            if !output.stderr.isEmpty { self.handleOutput(output.stderr, isErr: true) }
            self.flushPendingTranscript()
            self.isRunning = false
            self.prompt = ">>> "
            onFinish?(command, output.exitCode)
        }
    }

    private func shouldContinuePythonInput(after line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if pythonBuffer.count == 1 {
            return trimmed.hasSuffix(":") || trimmed.hasSuffix("\\")
        }
        return !trimmed.isEmpty
    }

    private func handleOutput(_ text: String, isErr: Bool) {
        // A form feed (from `clear`) wipes the scrollback.
        if text.contains("\u{0C}") {
            transcriptFlushWorkItem?.cancel()
            transcriptFlushWorkItem = nil
            pendingTranscript = AttributedString("")
            pendingTranscriptCharacterCount = 0
            transcriptChunks = []
            transcriptCharacterCount = 0
            let rest = text.replacingOccurrences(of: "\u{0C}", with: "")
            if !rest.isEmpty {
                append(rest, color: LectraColor.textPrimary)
            }
            flushPendingTranscript()
            return
        }
        append(text, color: isErr ? LectraColor.accentDestructive : LectraColor.textPrimary)
    }

    private func append(_ text: String, color: Color) {
        var run = AttributedString(text)
        run.foregroundColor = color
        pendingTranscript.append(run)
        pendingTranscriptCharacterCount += run.characters.count
        scheduleTranscriptFlush()
    }

    private func scheduleTranscriptFlush() {
        guard transcriptFlushWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.flushPendingTranscript()
            }
        }
        transcriptFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + transcriptFlushDelay, execute: workItem)
    }

    private func flushPendingTranscript() {
        transcriptFlushWorkItem?.cancel()
        transcriptFlushWorkItem = nil
        guard pendingTranscriptCharacterCount > 0 else { return }

        LectraPerformanceTrace.withSignpost(.terminal, "FlushTerminalTranscript") {
            transcriptChunks.append(TerminalTranscriptChunk(pendingTranscript))
            transcriptCharacterCount += pendingTranscriptCharacterCount
            pendingTranscript = AttributedString("")
            pendingTranscriptCharacterCount = 0
            trimTranscriptIfNeeded()
            transcriptRevision &+= 1
        }
    }

    private func trimTranscriptIfNeeded() {
        while transcriptCharacterCount > maxTranscript, transcriptChunks.count > 1 {
            let removed = transcriptChunks.removeFirst()
            transcriptCharacterCount -= removed.characterCount
        }

        guard transcriptCharacterCount > maxTranscript, let first = transcriptChunks.first else { return }
        let overflow = transcriptCharacterCount - maxTranscript
        guard overflow < first.characterCount else { return }

        let start = first.text.characters.index(first.text.startIndex, offsetBy: overflow)
        let trimmed = AttributedString(first.text[start...])
        transcriptChunks[0] = TerminalTranscriptChunk(trimmed)
        transcriptCharacterCount = maxTranscript
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

    func shutdown() {
        flushPendingTranscript()
        git.shutdown()
        python.shutdown()
    }
}
