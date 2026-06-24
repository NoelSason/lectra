//
//  ShellEnvironment.swift
//  Lectra
//
//  Mutable per-terminal shell state: working directory, variables, and the last
//  exit code. The root/HOME is the app's Documents directory — the same place
//  notebooks, PDFs, and code files live, so the terminal, the code editor, and
//  git all see one filesystem.
//

import Foundation

final class ShellEnvironment {
    /// Current working directory (absolute, inside the sandbox).
    var cwd: URL
    /// Shell + exported variables.
    var vars: [String: String]
    var exported: Set<String> = ["HOME", "PWD", "PATH"]
    var lastExitCode: Int32 = 0

    /// Sandbox boundary the shell may never escape (the app container).
    let sandboxRoot: URL

    init(startDirectory: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].standardizedFileURL
        let start = (startDirectory ?? docs).standardizedFileURL
        self.cwd = start
        self.sandboxRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
        self.vars = [
            "HOME": docs.path,
            "PWD": start.path,
            "PATH": "/usr/bin:/bin",
            "SHELL": "/lectra/bash",
            "TERM": "xterm-256color",
        ]
    }

    /// Resolves a user-supplied path against cwd / HOME and confines it to the
    /// sandbox. Returns nil if it would escape.
    func resolve(_ path: String) -> URL? {
        var p = path
        if p == "~" { p = vars["HOME"] ?? cwd.path }
        else if p.hasPrefix("~/") { p = (vars["HOME"] ?? cwd.path) + String(p.dropFirst(1)) }

        let url: URL
        if p.hasPrefix("/") { url = URL(fileURLWithPath: p) }
        else { url = cwd.appendingPathComponent(p) }
        let std = url.standardizedFileURL

        let root = sandboxRoot.path.hasSuffix("/") ? sandboxRoot.path : sandboxRoot.path + "/"
        guard std.path == sandboxRoot.path || std.path.hasPrefix(root) else { return nil }
        return std
    }

    func setCwd(_ url: URL) {
        cwd = url.standardizedFileURL
        vars["PWD"] = cwd.path
    }
}
