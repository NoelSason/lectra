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
    /// The name this instance is registered under. Declared as a requirement (not
    /// just an extension) so overrides dispatch dynamically through the `Builtin`
    /// existential — commands that answer to several names (nano/vi/vim) rely on
    /// this to get one registry entry per alias.
    var commandName: String { get }
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32
}

extension Builtin {
    /// Defaults to the type's static name; single-name commands need nothing more.
    var commandName: String { Self.name }
}

enum Builtins {
    static let all: [String: Builtin] = {
        let list: [Builtin] = [
            PwdCmd(), CdCmd(), LsCmd(), OpenCmd(), NanoCmd(name: "nano"), NanoCmd(name: "vi"),
            NanoCmd(name: "vim"), EchoCmd(), CatCmd(), TouchCmd(), MkdirCmd(),
            RmdirCmd(), RmCmd(), TrashCmd(), CpCmd(), MvCmd(), HeadCmd(), TailCmd(), WcCmd(),
            GrepCmd(), FindCmd(), WhichCmd(), EnvCmd(), ExportCmd(), ClearCmd(), HelpCmd(),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.commandName, $0) })
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
                // Present UUID-keyed documents (PDFs, notebooks) under their title.
                let virtual = TerminalDocuments.virtualNames(in: url)
                func shown(_ real: String) -> String { virtual[real] ?? real }
                entries.sort { shown($0).localizedCaseInsensitiveCompare(shown($1)) == .orderedAscending }
                for e in entries {
                    writeEntry(realName: e, display: shown(e), in: url, long: long, io: &io, fm: fm)
                }
            } else {
                writeEntry(realName: url.lastPathComponent, display: url.lastPathComponent,
                           in: url.deletingLastPathComponent(), long: long, io: &io, fm: fm)
            }
            if targets.count > 1 && i < targets.count - 1 { io.out("\n") }
        }
        return code
    }

    /// Lists one entry. `realName` is used for on-disk lookups; `display` is what
    /// the user sees (the friendly title for UUID-keyed documents, otherwise the
    /// same as `realName`).
    private func writeEntry(realName: String, display: String, in dir: URL, long: Bool, io: inout CommandIO, fm: FileManager) {
        let url = dir.appendingPathComponent(realName)
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        let shown = display + (isDir.boolValue ? "/" : "")
        if long {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            let date = (attrs?[.modificationDate] as? Date) ?? Date()
            let df = DateFormatter(); df.dateFormat = "MMM d HH:mm"
            let typeChar = isDir.boolValue ? "d" : "-"
            io.out(String(format: "%@rw-r--r--  %8d %@ %@\n", typeChar, size, df.string(from: date), shown))
        } else {
            io.out(shown + "\n")
        }
    }
}

// MARK: - Opening documents in their editor

/// `open <path>` hands a file back to the app: a PDF opens in the annotation
/// editor, a notebook in the notebook editor, and anything inside a project /
/// git working tree opens that project in the IDE. The actual presentation is
/// done by the library, which observes these notifications.
struct OpenCmd: Builtin {
    static let name = "open"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let paths = args.filter { !$0.hasPrefix("-") }
        guard let first = paths.first else { io.err("usage: open <file>\n"); return 1 }
        guard let url = env.resolve(first) else {
            io.err("open: \(first): outside the app sandbox\n"); return 1
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return notFound("open", first, io: &io)
        }
        guard let target = TerminalDocuments.classify(url) else {
            io.err("open: \(first): no Lectra editor handles this file\n"); return 1
        }
        switch target {
        case .document(let id, let title), .notebook(let id, let title):
            NotificationCenter.default.post(
                name: .lectraOpenDocumentRequest, object: nil,
                userInfo: ["documentId": id.uuidString])
            io.out("Opening \(title)…\n")
        case .project(let root):
            NotificationCenter.default.post(
                name: .lectraOpenProjectRequest, object: nil,
                userInfo: ["path": root.path])
            io.out("Opening \(root.lastPathComponent) in the editor…\n")
        }
        return 0
    }
}

// MARK: - Editing a file in place

/// `nano <file>` (also `vi`/`vim`) opens a file in Lectra's editor instead of a
/// modal terminal editor — there's no curses TTY here, and the IDE already has a
/// full editor pane. The file is created if it doesn't exist (like real nano),
/// then handed to the workspace, which loads it into the editor next to the
/// terminal.
struct NanoCmd: Builtin {
    static let name = "nano"
    let aliasName: String
    var commandName: String { aliasName }

    init(name: String) { self.aliasName = name }

    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let paths = args.filter { !$0.hasPrefix("-") }
        guard let first = paths.first else {
            io.err("usage: \(aliasName) <file>\n"); return 1
        }
        guard let url = env.resolve(first) else {
            io.err("\(aliasName): \(first): outside the app sandbox\n"); return 1
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            io.err("\(aliasName): \(first): is a directory\n"); return 1
        }
        // Create an empty file if it doesn't exist yet, mirroring nano.
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
                io.err("\(aliasName): \(first): could not create file\n"); return 1
            }
        }
        NotificationCenter.default.post(
            name: .lectraOpenFileInEditor, object: nil,
            userInfo: ["path": url.path])
        io.out("Opening \(url.lastPathComponent) in the editor…\n")
        return 0
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

// MARK: - Trash (recoverable deletes)

/// One record of a file moved to the Trash by `rm`, so `trash restore` can put
/// it back exactly where it came from.
struct TrashEntry: Codable {
    let id: String           // unique key; also the on-disk filename prefix
    let name: String         // original basename
    let originalPath: String // absolute path it was removed from
    let deletedAt: Date
}

/// A simple sandbox-local Trash. Items live under `~/.Trash` (the top of the
/// Documents container) so they survive `cd` and stay out of repos nested in
/// subdirectories. An index file maps each stored blob back to its origin.
enum TrashStore {
    static func directory(env: ShellEnvironment) -> URL {
        let home = URL(fileURLWithPath: env.vars["HOME"] ?? env.sandboxRoot.path)
        return home.appendingPathComponent(".Trash", isDirectory: true).standardizedFileURL
    }
    private static func indexURL(env: ShellEnvironment) -> URL {
        directory(env: env).appendingPathComponent(".index.json")
    }
    static func storedURL(for entry: TrashEntry, env: ShellEnvironment) -> URL {
        directory(env: env).appendingPathComponent(entry.id + "__" + entry.name)
    }

    static func load(env: ShellEnvironment) -> [TrashEntry] {
        guard let data = try? Data(contentsOf: indexURL(env: env)) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return ((try? dec.decode([TrashEntry].self, from: data)) ?? [])
            .sorted { $0.deletedAt > $1.deletedAt } // most recent first
    }
    static func save(_ entries: [TrashEntry], env: ShellEnvironment) {
        try? FileManager.default.createDirectory(at: directory(env: env), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(entries) { try? data.write(to: indexURL(env: env)) }
    }

    /// Moves `url` into the Trash and records it. Returns false on failure.
    @discardableResult
    static func trash(_ url: URL, env: ShellEnvironment) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory(env: env), withIntermediateDirectories: true)
        let entry = TrashEntry(id: UUID().uuidString, name: url.lastPathComponent,
                               originalPath: url.path, deletedAt: Date())
        do { try fm.moveItem(at: url, to: storedURL(for: entry, env: env)) } catch { return false }
        var entries = load(env: env); entries.append(entry); save(entries, env: env)
        return true
    }
}

struct RmCmd: Builtin {
    static let name = "rm"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let opts = args.filter { $0.hasPrefix("-") }.joined()
        let recursive = opts.contains("r") || opts.contains("R")
        let force = opts.contains("f")
        let files = args.filter { !$0.hasPrefix("-") }
        let trashDir = TrashStore.directory(env: env)
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
            // Deleting something already inside the Trash is a permanent removal;
            // everything else is moved to the Trash so it can be restored.
            if url.path == trashDir.path || url.path.hasPrefix(trashDir.path + "/") {
                do { try FileManager.default.removeItem(at: url) } catch { io.err("rm: \(f): \(error.localizedDescription)\n"); code = 1 }
            } else if !TrashStore.trash(url, env: env) {
                io.err("rm: \(f): could not move to Trash\n"); code = 1
            }
        }
        return code
    }
}

struct TrashCmd: Builtin {
    static let name = "trash"
    func run(_ args: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let sub = args.first ?? "list"
        switch sub {
        case "list", "ls": return list(io: &io, env: env)
        case "restore": return restore(Array(args.dropFirst()), io: &io, env: env)
        case "empty": return empty(io: &io, env: env)
        default:
            io.err("trash: unknown command '\(sub)'\nusage: trash [list] | trash restore <number|name> | trash empty\n")
            return 1
        }
    }

    private func homeRelative(_ path: String, env: ShellEnvironment) -> String {
        let home = env.vars["HOME"] ?? ""
        if !home.isEmpty, path == home { return "~" }
        if !home.isEmpty, path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()

    private func list(io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let entries = TrashStore.load(env: env)
        guard !entries.isEmpty else { io.out("Trash is empty.\n"); return 0 }
        io.out("Trash (\(entries.count) item\(entries.count == 1 ? "" : "s")):\n")
        let width = entries.map { $0.name.count }.max() ?? 0
        for (i, e) in entries.enumerated() {
            let name = e.name.padding(toLength: max(width, 4), withPad: " ", startingAt: 0)
            io.out("  \(i + 1)  \(name)  \(homeRelative(e.originalPath, env: env))  \(Self.dateFmt.string(from: e.deletedAt))\n")
        }
        io.out("(use `trash restore <number|name>` to bring one back)\n")
        return 0
    }

    private func restore(_ targets: [String], io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        guard !targets.isEmpty else { io.err("trash: restore: specify a number or name\n"); return 1 }
        var entries = TrashStore.load(env: env)
        guard !entries.isEmpty else { io.err("trash: Trash is empty\n"); return 1 }
        let fm = FileManager.default
        var code: Int32 = 0
        for t in targets {
            // Match by 1-based list number, falling back to most-recent name match.
            let entry: TrashEntry?
            if let n = Int(t), n >= 1, n <= entries.count { entry = entries[n - 1] }
            else { entry = entries.first { $0.name == t } }
            guard let e = entry else { io.err("trash: '\(t)': not in Trash\n"); code = 1; continue }

            let dest = URL(fileURLWithPath: e.originalPath)
            if fm.fileExists(atPath: dest.path) {
                io.err("trash: \(e.name): already exists at \(homeRelative(e.originalPath, env: env))\n"); code = 1; continue
            }
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try fm.moveItem(at: TrashStore.storedURL(for: e, env: env), to: dest)
                entries.removeAll { $0.id == e.id }
                io.out("Restored \(e.name) -> \(homeRelative(e.originalPath, env: env))\n")
            } catch {
                io.err("trash: \(e.name): \(error.localizedDescription)\n"); code = 1
            }
        }
        TrashStore.save(entries, env: env)
        return code
    }

    private func empty(io: inout CommandIO, env: ShellEnvironment) -> Int32 {
        let entries = TrashStore.load(env: env)
        let fm = FileManager.default
        for e in entries { try? fm.removeItem(at: TrashStore.storedURL(for: e, env: env)) }
        TrashStore.save([], env: env)
        io.out("Emptied Trash (\(entries.count) item\(entries.count == 1 ? "" : "s") removed).\n")
        return 0
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
            else if TerminalPythonRuntime.commandNames.contains(a) { io.out("\(a): built-in (Pyodide Python)\n") }
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
          open:   open <file> — PDFs open for annotation, notebooks in the notebook editor, project files in the IDE
          edit:   nano/vi/vim <file> — open (or create) a file in the editor next to the terminal
          trash:  rm moves files to the Trash; `trash` lists, `trash restore <number|name>` brings one back, `trash empty` clears it
          search: grep find which
          shell:  echo env export clear help
          python: python/python3 [file.py] or bare python/python3 for a REPL
          git:    git <init|clone|add|status|commit|log|branch|checkout|switch|restore|push|pull|fetch|remote|diff|config>
        Pipes (|), redirection (> >> <), && || ; and glob(* ? []) are supported.

        """)
        return 0
    }
}
