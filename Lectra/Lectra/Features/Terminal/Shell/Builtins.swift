//
//  Builtins.swift
//  Lectra
//
//  The shell's built-in commands. There is no real exec on iOS, so every command
//  is implemented natively against FileManager. Each builtin reads `io.stdin`,
//  writes `io.stdout` / `io.stderr`, and returns a POSIX-style exit code.
//

import Foundation

struct CommandIO {
    var stdin: Data = Data()
    var stdout = Data()
    var stderr = Data()
    var stdinText: String { String(data: stdin, encoding: .utf8) ?? "" }
    mutating func out(_ s: String) { stdout.append(Data(s.utf8)) }
    mutating func err(_ s: String) { stderr.append(Data(s.utf8)) }
}

protocol Builtin {
    static var name: String { get }
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32
}

enum Builtins {
    static let all: [String: Builtin] = {
        let list: [Builtin] = [
            PwdCmd(), CdCmd(), LsCmd(), EchoCmd(), CatCmd(), TouchCmd(), MkdirCmd(),
            RmdirCmd(), RmCmd(), CpCmd(), MvCmd(), HeadCmd(), TailCmd(), WcCmd(),
            GrepCmd(), FindCmd(), WhichCmd(), EnvCmd(), ExportCmd(), ClearCmd(), HelpCmd(),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { (type(of: $0).name, $0) })
    }()
}

// MARK: - Helpers

private func notFound(_ cmd: String, _ path: String, io: inout CommandIO) -> Int32 {
    io.err("\(cmd): \(path): No such file or directory\n"); return 1
}

// MARK: - Directory / navigation

struct PwdCmd: Builtin {
    static let name = "pwd"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        io.out(env.cwd.path + "\n"); return 0
    }
}

struct CdCmd: Builtin {
    static let name = "cd"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let target = args.first ?? "~"
        guard let url = env.resolve(target) else {
            io.err("cd: \(target): outside the app sandbox\n"); return 1
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            io.err("cd: \(target): Not a directory\n"); return 1
        }
        env.setCwd(url); return 0
    }
}

struct LsCmd: Builtin {
    static let name = "ls"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let opts = args.filter { $0.hasPrefix("-") }.joined()
        let showAll = opts.contains("a")
        let long = opts.contains("l")
        let paths = args.filter { !$0.hasPrefix("-") }
        let targets = paths.isEmpty ? ["."] : paths
        var code: Int32 = 0
        let fm = FileManager.default

        for (i, target) in targets.enumerated() {
            guard let url = env.resolve(target) else { io.err("ls: \(target): outside the app sandbox\n"); code = 1; continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { _ = notFound("ls", target, io: &io); code = 1; continue }
            if targets.count > 1 { io.out("\(target):\n") }
            if isDir.boolValue {
                var entries = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
                if !showAll { entries = entries.filter { !$0.hasPrefix(".") } }
                entries.sort()
                for e in entries { writeEntry(name: e, in: url, long: long, io: &io, fm: fm) }
            } else {
                writeEntry(name: url.lastPathComponent, in: url.deletingLastPathComponent(), long: long, io: &io, fm: fm)
            }
            if targets.count > 1 && i < targets.count - 1 { io.out("\n") }
        }
        return code
    }

    private func writeEntry(name: String, in dir: URL, long: Bool, io: inout CommandIO, fm: FileManager) {
        let url = dir.appendingPathComponent(name)
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        if long {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            let date = (attrs?[.modificationDate] as? Date) ?? Date()
            let df = DateFormatter(); df.dateFormat = "MMM d HH:mm"
            let typeChar = isDir.boolValue ? "d" : "-"
            io.out(String(format: "%@rw-r--r--  %8d %@ %@\n", typeChar, size, df.string(from: date), name + (isDir.boolValue ? "/" : "")))
        } else {
            io.out(name + (isDir.boolValue ? "/" : "") + "\n")
        }
    }
}

// MARK: - Output

struct EchoCmd: Builtin {
    static let name = "echo"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        var args = args
        var newline = true
        if args.first == "-n" { newline = false; args.removeFirst() }
        io.out(args.joined(separator: " ") + (newline ? "\n" : "")); return 0
    }
}

struct CatCmd: Builtin {
    static let name = "cat"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let files = args.filter { !$0.hasPrefix("-") }
        if files.isEmpty { io.stdout.append(io.stdin); return 0 }
        var code: Int32 = 0
        for f in files {
            guard let url = env.resolve(f) else { io.err("cat: \(f): outside the app sandbox\n"); code = 1; continue }
            guard let data = FileManager.default.contents(atPath: url.path) else { _ = notFound("cat", f, io: &io); code = 1; continue }
            io.stdout.append(data)
        }
        return code
    }
}

// MARK: - File creation / mutation

struct TouchCmd: Builtin {
    static let name = "touch"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        var code: Int32 = 0
        for f in args where !f.hasPrefix("-") {
            guard let url = env.resolve(f) else { io.err("touch: \(f): outside the app sandbox\n"); code = 1; continue }
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            } else {
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
        }
        return code
    }
}

struct MkdirCmd: Builtin {
    static let name = "mkdir"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let parents = args.contains("-p")
        var code: Int32 = 0
        for f in args where !f.hasPrefix("-") {
            guard let url = env.resolve(f) else { io.err("mkdir: \(f): outside the app sandbox\n"); code = 1; continue }
            do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: parents) }
            catch { io.err("mkdir: \(f): \(error.localizedDescription)\n"); code = 1 }
        }
        return code
    }
}

struct RmdirCmd: Builtin {
    static let name = "rmdir"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        var code: Int32 = 0
        for f in args where !f.hasPrefix("-") {
            guard let url = env.resolve(f) else { io.err("rmdir: \(f): outside the app sandbox\n"); code = 1; continue }
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            if !entries.isEmpty { io.err("rmdir: \(f): Directory not empty\n"); code = 1; continue }
            do { try FileManager.default.removeItem(at: url) } catch { io.err("rmdir: \(f): \(error.localizedDescription)\n"); code = 1 }
        }
        return code
    }
}

struct RmCmd: Builtin {
    static let name = "rm"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let opts = args.filter { $0.hasPrefix("-") }.joined()
        let recursive = opts.contains("r") || opts.contains("R")
        let force = opts.contains("f")
        let files = args.filter { !$0.hasPrefix("-") }
        var code: Int32 = 0
        for f in files {
            guard let url = env.resolve(f) else { io.err("rm: \(f): outside the app sandbox\n"); code = 1; continue }
            if url.path == env.sandboxRoot.path || url.path == (env.vars["HOME"] ?? "") {
                io.err("rm: \(f): refusing to remove a protected directory\n"); code = 1; continue
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                if !force { _ = notFound("rm", f, io: &io); code = 1 }
                continue
            }
            if isDir.boolValue && !recursive { io.err("rm: \(f): is a directory\n"); code = 1; continue }
            do { try FileManager.default.removeItem(at: url) } catch { io.err("rm: \(f): \(error.localizedDescription)\n"); code = 1 }
        }
        return code
    }
}

struct CpCmd: Builtin {
    static let name = "cp"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let files = args.filter { !$0.hasPrefix("-") }
        guard files.count >= 2 else { io.err("cp: missing destination\n"); return 1 }
        return copyOrMove(files, env: env, io: &io, move: false, cmd: "cp")
    }
}

struct MvCmd: Builtin {
    static let name = "mv"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let files = args.filter { !$0.hasPrefix("-") }
        guard files.count >= 2 else { io.err("mv: missing destination\n"); return 1 }
        return copyOrMove(files, env: env, io: &io, move: true, cmd: "mv")
    }
}

private func copyOrMove(_ files: [String], env: ShellEnvironment, io: inout CommandIO, move: Bool, cmd: String) -> Int32 {
    let fm = FileManager.default
    let sources = files.dropLast()
    let destArg = files.last!
    guard let dest = env.resolve(destArg) else { io.err("\(cmd): \(destArg): outside the app sandbox\n"); return 1 }
    var destIsDir: ObjCBool = false
    let destExistsDir = fm.fileExists(atPath: dest.path, isDirectory: &destIsDir) && destIsDir.boolValue
    var code: Int32 = 0
    for s in sources {
        guard let src = env.resolve(s) else { io.err("\(cmd): \(s): outside the app sandbox\n"); code = 1; continue }
        guard fm.fileExists(atPath: src.path) else { _ = notFound(cmd, s, io: &io); code = 1; continue }
        let target = destExistsDir ? dest.appendingPathComponent(src.lastPathComponent) : dest
        if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
        do {
            if move { try fm.moveItem(at: src, to: target) } else { try fm.copyItem(at: src, to: target) }
        } catch { io.err("\(cmd): \(s): \(error.localizedDescription)\n"); code = 1 }
    }
    return code
}

// MARK: - Text utilities

struct HeadCmd: Builtin {
    static let name = "head"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let (n, files) = lineCountAndFiles(args, defaultN: 10)
        return emitLines(files, env: env, io: &io, cmd: "head") { Array($0.prefix(n)) }
    }
}

struct TailCmd: Builtin {
    static let name = "tail"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let (n, files) = lineCountAndFiles(args, defaultN: 10)
        return emitLines(files, env: env, io: &io, cmd: "tail") { Array($0.suffix(n)) }
    }
}

private func lineCountAndFiles(_ args: [String], defaultN: Int) -> (Int, [String]) {
    var n = defaultN, files: [String] = []
    var i = 0
    while i < args.count {
        if args[i] == "-n", i + 1 < args.count { n = Int(args[i + 1]) ?? defaultN; i += 2 }
        else if args[i].hasPrefix("-") && Int(args[i].dropFirst()) != nil { n = Int(args[i].dropFirst()) ?? defaultN; i += 1 }
        else { files.append(args[i]); i += 1 }
    }
    return (n, files)
}

private func emitLines(_ files: [String], env: ShellEnvironment, io: inout CommandIO, cmd: String, transform: ([Substring]) -> [Substring]) -> Int32 {
    func emit(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let trimmed = lines.last == "" ? Array(lines.dropLast()) : Array(lines)
        for l in transform(trimmed) { io.out(String(l) + "\n") }
    }
    if files.isEmpty { emit(io.stdinText); return 0 }
    var code: Int32 = 0
    for f in files {
        guard let url = env.resolve(f), let data = FileManager.default.contents(atPath: url.path) else { _ = notFound(cmd, f, io: &io); code = 1; continue }
        emit(String(data: data, encoding: .utf8) ?? "")
    }
    return code
}

struct WcCmd: Builtin {
    static let name = "wc"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let opts = args.filter { $0.hasPrefix("-") }.joined()
        let files = args.filter { !$0.hasPrefix("-") }
        let wantL = opts.contains("l"), wantW = opts.contains("w"), wantC = opts.contains("c")
        let showAll = !(wantL || wantW || wantC)
        func count(_ text: String, label: String) {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count - (text.hasSuffix("\n") || text.isEmpty ? 1 : 0)
            let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
            let bytes = text.utf8.count
            var parts: [String] = []
            if showAll || wantL { parts.append(String(format: "%4d", max(lines, 0))) }
            if showAll || wantW { parts.append(String(format: "%4d", words)) }
            if showAll || wantC { parts.append(String(format: "%4d", bytes)) }
            io.out(parts.joined(separator: " ") + (label.isEmpty ? "" : " " + label) + "\n")
        }
        if files.isEmpty { count(io.stdinText, label: ""); return 0 }
        var code: Int32 = 0
        for f in files {
            guard let url = env.resolve(f), let data = FileManager.default.contents(atPath: url.path) else { _ = notFound("wc", f, io: &io); code = 1; continue }
            count(String(data: data, encoding: .utf8) ?? "", label: f)
        }
        return code
    }
}

struct GrepCmd: Builtin {
    static let name = "grep"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let opts = args.filter { $0.hasPrefix("-") && $0 != "-" }.joined()
        let ignoreCase = opts.contains("i")
        let invert = opts.contains("v")
        let showNum = opts.contains("n")
        let positional = args.filter { !$0.hasPrefix("-") }
        guard let pattern = positional.first else { io.err("usage: grep pattern [file ...]\n"); return 2 }
        let files = Array(positional.dropFirst())
        let regex = try? NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])

        func matches(_ line: String) -> Bool {
            let hit: Bool
            if let regex { hit = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil }
            else { hit = ignoreCase ? line.lowercased().contains(pattern.lowercased()) : line.contains(pattern) }
            return hit != invert
        }
        func scan(_ text: String, prefix: String) -> Bool {
            var found = false
            for (idx, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if matches(String(line)) {
                    found = true
                    var out = prefix
                    if showNum { out += "\(idx + 1):" }
                    io.out(out + line + "\n")
                }
            }
            return found
        }
        if files.isEmpty { return scan(io.stdinText, prefix: "") ? 0 : 1 }
        var any = false, code: Int32 = 0
        for f in files {
            guard let url = env.resolve(f), let data = FileManager.default.contents(atPath: url.path) else { _ = notFound("grep", f, io: &io); code = 1; continue }
            let prefix = files.count > 1 ? "\(f):" : ""
            if scan(String(data: data, encoding: .utf8) ?? "", prefix: prefix) { any = true }
        }
        return code != 0 ? code : (any ? 0 : 1)
    }
}

struct FindCmd: Builtin {
    static let name = "find"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        var roots: [String] = []
        var namePattern: String?
        var typeFilter: String?
        var i = 0
        while i < args.count {
            switch args[i] {
            case "-name": if i + 1 < args.count { namePattern = args[i + 1]; i += 2 } else { i += 1 }
            case "-type": if i + 1 < args.count { typeFilter = args[i + 1]; i += 2 } else { i += 1 }
            default: roots.append(args[i]); i += 1
            }
        }
        if roots.isEmpty { roots = ["."] }
        let fm = FileManager.default
        var code: Int32 = 0
        for root in roots {
            guard let url = env.resolve(root) else { io.err("find: \(root): outside the app sandbox\n"); code = 1; continue }
            guard let en = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { _ = notFound("find", root, io: &io); code = 1; continue }
            // include the root itself
            emitMatch(url, display: root, base: url, rootDisplay: root, namePattern: namePattern, typeFilter: typeFilter, io: &io)
            for case let child as URL in en {
                let rel = child.path.replacingOccurrences(of: url.path + "/", with: "")
                let display = (root == "." ? "./" : root + "/") + rel
                emitMatch(child, display: display, base: url, rootDisplay: root, namePattern: namePattern, typeFilter: typeFilter, io: &io)
            }
        }
        return code
    }
    private func emitMatch(_ url: URL, display: String, base: URL, rootDisplay: String, namePattern: String?, typeFilter: String?, io: inout CommandIO) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if let t = typeFilter { if t == "d" && !isDir.boolValue { return }; if t == "f" && isDir.boolValue { return } }
        if let pat = namePattern, !Glob.match(pattern: pat, name: url.lastPathComponent) { return }
        io.out(display + "\n")
    }
}

struct WhichCmd: Builtin {
    static let name = "which"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        var code: Int32 = 0
        for a in args where !a.hasPrefix("-") {
            if a == "git" { io.out("git: built-in (isomorphic-git)\n") }
            else if Builtins.all[a] != nil { io.out("\(a): shell builtin\n") }
            else { io.err("\(a) not found\n"); code = 1 }
        }
        return code
    }
}

struct EnvCmd: Builtin {
    static let name = "env"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        for key in env.vars.keys.sorted() { io.out("\(key)=\(env.vars[key] ?? "")\n") }
        return 0
    }
}

struct ExportCmd: Builtin {
    static let name = "export"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        for a in args {
            if let eq = a.firstIndex(of: "=") {
                let name = String(a[a.startIndex..<eq])
                let value = String(a[a.index(after: eq)...])
                env.vars[name] = value
                env.exported.insert(name)
            } else {
                env.exported.insert(a)
            }
        }
        return 0
    }
}

struct ClearCmd: Builtin {
    static let name = "clear"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        io.out("\u{0C}"); return 0 // form feed: the terminal treats this as "clear scrollback"
    }
}

struct HelpCmd: Builtin {
    static let name = "help"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        io.out("""
        Lectra terminal — built-in commands:
          files:  ls cd pwd cp mv rm mkdir rmdir touch cat head tail wc
          search: grep find which
          shell:  echo env export clear help
          git:    git <init|clone|add|status|commit|log|branch|checkout|push|pull|fetch|remote|diff|config>
        Pipes (|), redirection (> >> <), && || ; and glob(* ? []) are supported.

        """)
        return 0
    }
}
