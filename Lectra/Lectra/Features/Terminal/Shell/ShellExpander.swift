//
//  ShellExpander.swift
//  Lectra
//
//  Turns parsed WordTokens into final argument strings: variable expansion,
//  field splitting (unquoted only), and filename globbing (* ? [...]). Quoting
//  rules follow POSIX closely enough for everyday use.
//

import Foundation

struct ShellExpander {

    /// One field-in-progress, tracking whether any contributing part is eligible
    /// for globbing (i.e. came from unquoted text).
    private struct Field { var text = ""; var globbable = false }

    static func expand(_ word: WordToken, env: ShellEnvironment) -> [String] {
        var fields: [Field] = [Field()]

        for part in word.parts {
            switch part.quote {
            case .single:
                fields[fields.count - 1].text += part.text
            case .double:
                fields[fields.count - 1].text += expandVars(part.text, env: env)
            case .none:
                let expanded = expandVars(part.text, env: env)
                // Field-split on whitespace (only unquoted expansions can split).
                let ws: Set<Character> = [" ", "\t", "\n"]
                let pieces: [String] = expanded.split(whereSeparator: { ws.contains($0) }).map { String($0) }
                if expanded.isEmpty {
                    fields[fields.count - 1].globbable = true
                    continue
                }
                let leadingWS: Bool = expanded.first.map { ws.contains($0) } ?? false
                let trailingWS: Bool = expanded.last.map { ws.contains($0) } ?? false
                for (idx, piece) in pieces.enumerated() {
                    if idx == 0 && !leadingWS {
                        fields[fields.count - 1].text += piece
                        fields[fields.count - 1].globbable = true
                    } else {
                        fields.append(Field(text: piece, globbable: true))
                    }
                }
                if trailingWS { fields.append(Field()) }
            }
        }
        // Drop a trailing empty field introduced by trailing whitespace.
        if let last = fields.last, last.text.isEmpty, fields.count > 1 { fields.removeLast() }

        var result: [String] = []
        for field in fields {
            if field.globbable && containsGlob(field.text) {
                let matches = Glob.expand(pattern: field.text, env: env)
                if matches.isEmpty { result.append(field.text) } // nullglob off
                else { result.append(contentsOf: matches) }
            } else if !field.text.isEmpty || word.parts.contains(where: { $0.quote != .none }) {
                result.append(field.text)
            }
        }
        return result
    }

    // MARK: Variables

    private static func expandVars(_ s: String, env: ShellEnvironment) -> String {
        guard s.contains("$") else { return s }
        var out = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if chars[i] == "$" && i + 1 < chars.count {
                let next = chars[i + 1]
                if next == "?" {
                    out += String(env.lastExitCode); i += 2; continue
                }
                if next == "{" {
                    var name = ""
                    i += 2
                    while i < chars.count && chars[i] != "}" { name.append(chars[i]); i += 1 }
                    if i < chars.count { i += 1 } // closing }
                    out += env.vars[name] ?? ""
                    continue
                }
                if next.isLetter || next == "_" {
                    var name = ""
                    i += 1
                    while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                        name.append(chars[i]); i += 1
                    }
                    out += env.vars[name] ?? ""
                    continue
                }
            }
            out.append(chars[i]); i += 1
        }
        return out
    }

    private static func containsGlob(_ s: String) -> Bool {
        s.contains("*") || s.contains("?") || (s.contains("[") && s.contains("]"))
    }
}

// MARK: - Globbing

enum Glob {
    /// Expands a glob pattern (possibly with directory components) against the
    /// filesystem, returning matching paths (as the user would type them).
    static func expand(pattern: String, env: ShellEnvironment) -> [String] {
        let absolute = pattern.hasPrefix("/")
        let components = pattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let startDir = absolute ? URL(fileURLWithPath: "/") : env.cwd
        let startPrefix = absolute ? "/" : ""

        var results: [(url: URL, display: String)] = [(startDir, startPrefix)]
        for (idx, comp) in components.enumerated() {
            if comp.isEmpty { continue }
            var next: [(URL, String)] = []
            for (dir, display) in results {
                if hasMeta(comp) {
                    let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
                    for entry in entries.sorted() {
                        if entry.hasPrefix(".") && !comp.hasPrefix(".") { continue } // hide dotfiles
                        if match(pattern: comp, name: entry) {
                            let childDisplay = display.isEmpty ? entry : display + (display.hasSuffix("/") ? "" : "/") + entry
                            next.append((dir.appendingPathComponent(entry), childDisplay))
                        }
                    }
                } else {
                    let child = dir.appendingPathComponent(comp)
                    let isLast = idx == components.count - 1
                    if isLast || FileManager.default.fileExists(atPath: child.path) {
                        let childDisplay = display.isEmpty ? comp : display + (display.hasSuffix("/") ? "" : "/") + comp
                        next.append((child, childDisplay))
                    }
                }
            }
            results = next
        }
        return results.map { $0.display }.sorted()
    }

    private static func hasMeta(_ s: String) -> Bool { s.contains("*") || s.contains("?") || s.contains("[") }

    /// fnmatch-style wildcard matching for a single path component.
    static func match(pattern: String, name: String) -> Bool {
        let p = Array(pattern), n = Array(name)
        return matchRec(p, 0, n, 0)
    }
    private static func matchRec(_ p: [Character], _ pi0: Int, _ n: [Character], _ ni0: Int) -> Bool {
        var pi = pi0, ni = ni0
        while pi < p.count {
            let pc = p[pi]
            if pc == "*" {
                // collapse consecutive stars
                while pi < p.count && p[pi] == "*" { pi += 1 }
                if pi == p.count { return true }
                while ni <= n.count {
                    if matchRec(p, pi, n, ni) { return true }
                    ni += 1
                }
                return false
            } else if pc == "?" {
                if ni >= n.count { return false }
                pi += 1; ni += 1
            } else if pc == "[" {
                if ni >= n.count { return false }
                var j = pi + 1
                var negate = false
                if j < p.count && (p[j] == "!" || p[j] == "^") { negate = true; j += 1 }
                var matched = false
                while j < p.count && p[j] != "]" {
                    if j + 2 < p.count && p[j + 1] == "-" && p[j + 2] != "]" {
                        if n[ni] >= p[j] && n[ni] <= p[j + 2] { matched = true }
                        j += 3
                    } else {
                        if n[ni] == p[j] { matched = true }
                        j += 1
                    }
                }
                if j < p.count { j += 1 } // skip ]
                if matched == negate { return false }
                pi = j; ni += 1
            } else {
                if ni >= n.count || n[ni] != pc { return false }
                pi += 1; ni += 1
            }
        }
        return ni == n.count
    }
}
