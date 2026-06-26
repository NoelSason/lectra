//
//  TerminalDocuments.swift
//  Lectra
//
//  Bridges the terminal's raw view of the Documents container to the documents
//  the rest of the app knows about. On disk a PDF is `pdfs/<UUID>/` and a
//  notebook is `notebooks/<UUID>.ipynb` — opaque ids. This maps those ids back to
//  their human titles (so `ls` can label them) and classifies a path into
//  something openable (PDF annotation, notebook editor, or a project in the IDE),
//  which the `open` builtin hands to the library to present.
//

import Foundation

extension Notification.Name {
    /// Posted by the `open` builtin for a path inside a project / git repo.
    /// Observed by the library, which presents that project in the IDE.
    static let lectraOpenProjectRequest = Notification.Name("LectraOpenProjectRequest")

    /// Posted by `nano` (and `vi`/`vim`) to open a specific file for editing.
    /// `userInfo["path"]` is the absolute file path. Observed by the IDE
    /// workspace, which loads that file into its editor pane.
    static let lectraOpenFileInEditor = Notification.Name("LectraOpenFileInEditor")
}

/// What a filesystem path resolves to, from the app's point of view.
enum TerminalDocumentTarget {
    /// A PDF document (`pdfs/<UUID>/…`) to open in the annotation editor.
    case document(id: UUID, title: String)
    /// A notebook (`notebooks/<UUID>.ipynb`) to open in the notebook editor.
    case notebook(id: UUID, title: String)
    /// A file inside a project / git working tree; opens that project in the IDE.
    case project(root: URL)
}

enum TerminalDocuments {
    /// The Documents container — the terminal's HOME and the root of pdfs/,
    /// notebooks/, and Projects/.
    static var home: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].standardizedFileURL
    }

    // MARK: Friendly names (for `ls`, `cd`, `open`, tab-completion)
    //
    // On disk a PDF is `pdfs/<UUID>/` and a notebook is `notebooks/<UUID>.ipynb`.
    // That UUID is the document's identity — every local loader derives its path
    // from it, and Canvascope/DropBridge sync matches on it — so it must stay the
    // real on-disk name. The terminal, though, presents these documents under
    // their human title (e.g. `My_first_python_notebook.ipynb`) and accepts that
    // name back, so the user never has to type a UUID. The translation lives
    // entirely here; nothing about the files or sync changes.

    /// Whether `dir` is one of the UUID-keyed document directories whose children
    /// the terminal shows under their title instead of their UUID.
    private static func isVirtualized(_ dir: URL) -> Bool {
        let d = dir.standardizedFileURL
        return d == home.appendingPathComponent("pdfs", isDirectory: true).standardizedFileURL
            || d == home.appendingPathComponent("notebooks", isDirectory: true).standardizedFileURL
    }

    /// Maps each real (UUID) entry in a virtualized directory to the friendly,
    /// title-based name shown in the terminal. Returns an empty map for ordinary
    /// directories, so callers can use `map[name] ?? name` unconditionally.
    /// Entries whose title is missing or sanitizes to nothing keep their raw UUID
    /// name, so a document is never left unreachable.
    static func virtualNames(in dir: URL) -> [String: String] {
        nameTable(in: dir).toVirtual
    }

    /// If `url` points at a document by its friendly terminal name (e.g.
    /// `pdfs/My_Notes` or `notebooks/My_Notes.ipynb`), returns the real on-disk
    /// URL; otherwise returns `url` unchanged. Paths that already name a real
    /// entry are left alone, so typing the raw UUID still works.
    static func resolveVirtual(_ url: URL) -> URL {
        let std = url.standardizedFileURL
        let comps = homeRelativeComponents(of: std)
        guard let first = comps.first, first == "pdfs" || first == "notebooks", comps.count >= 2 else {
            return std
        }
        let dir = home.appendingPathComponent(first, isDirectory: true).standardizedFileURL
        let child = comps[1]
        // Already a real entry (e.g. the user typed the UUID)? Leave it.
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent(child).path) { return std }

        let toReal = nameTable(in: dir).toReal
        let real = toReal[child]
            ?? toReal.first { $0.key.caseInsensitiveCompare(child) == .orderedSame }?.value
        guard let real else { return std }

        var rebuilt = dir.appendingPathComponent(real)
        for extra in comps.dropFirst(2) { rebuilt.appendPathComponent(extra) }
        return rebuilt.standardizedFileURL
    }

    /// Builds the bidirectional real⇄friendly name table for a virtualized
    /// directory. Duplicate titles are disambiguated with a short id suffix so
    /// every friendly name is unique and the reverse lookup is unambiguous.
    private static func nameTable(in dir: URL) -> (toVirtual: [String: String], toReal: [String: String]) {
        let dir = dir.standardizedFileURL
        guard isVirtualized(dir) else { return ([:], [:]) }
        let isNotebooks = dir == home.appendingPathComponent("notebooks", isDirectory: true).standardizedFileURL
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []

        // Desired friendly base name (no extension, before disambiguation) per entry.
        var entries: [(real: String, base: String, ext: String)] = []
        if isNotebooks {
            for name in names where name.hasSuffix(".ipynb") {
                let stem = String(name.dropLast(".ipynb".count))
                guard UUID(uuidString: stem) != nil else { continue }
                let title = notebookTitle(at: dir.appendingPathComponent(name)) ?? ""
                let base = slug(title)
                entries.append((real: name, base: base.isEmpty ? stem : base, ext: ".ipynb"))
            }
        } else {
            let byID = pdfTitlesByID()
            for name in names {
                guard UUID(uuidString: name) != nil else { continue }
                let base = slug(byID[name.uppercased()] ?? "")
                entries.append((real: name, base: base.isEmpty ? name : base, ext: ""))
            }
        }

        var counts: [String: Int] = [:]
        for e in entries { counts[e.base.lowercased(), default: 0] += 1 }

        var toVirtual: [String: String] = [:]
        var toReal: [String: String] = [:]
        for e in entries {
            var base = e.base
            if counts[e.base.lowercased(), default: 0] > 1 {
                base = "\(e.base)_\(shortID(e.real))"
            }
            let virtual = base + e.ext
            toVirtual[e.real] = virtual
            toReal[virtual] = e.real
        }
        return (toVirtual, toReal)
    }

    /// Document id (uppercased UUID string) → title, gathered from every local
    /// source so a PDF folder can be named even when it was synced rather than
    /// saved on this device. Precedence, low → high: the library's title cache,
    /// documents saved locally, then the user's explicit renames.
    private static func pdfTitlesByID() -> [String: String] {
        let defaults = UserDefaults.standard
        var byID: [String: String] = [:]

        if let cache = defaults.dictionary(forKey: LectraLocalAccountData.documentTitleCacheDefaultsKey) as? [String: String] {
            for (key, title) in cache where !title.isEmpty { byID[key.uppercased()] = title }
        }
        if let data = defaults.data(forKey: LectraLocalAccountData.localPDFsDefaultsKey),
           let saved = try? JSONDecoder().decode([SavedLocalDocument].self, from: data) {
            for doc in saved where !doc.title.isEmpty { byID[doc.id.uuidString.uppercased()] = doc.title }
        }
        if let overrides = defaults.dictionary(forKey: LectraLocalAccountData.titleOverridesDefaultsKey) as? [String: String] {
            for (key, title) in overrides where !title.isEmpty { byID[key.uppercased()] = title }
        }
        return byID
    }

    /// A short, stable disambiguator from a real entry name (first 8 hex digits of
    /// its UUID, lowercased).
    private static func shortID(_ realName: String) -> String {
        let stem = realName.hasSuffix(".ipynb") ? String(realName.dropLast(".ipynb".count)) : realName
        return String(stem.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
    }

    /// A friendly, shell-typeable name for a document title: runs of spaces and
    /// characters that are illegal or awkward in a path component collapse to a
    /// single underscore, so the result needs no quoting in the terminal. Empty
    /// when the title has nothing usable left.
    static func slug(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.whitespacesAndNewlines).union(.controlCharacters)
        var name = raw.components(separatedBy: illegal).filter { !$0.isEmpty }.joined(separator: "_")
        while name.hasPrefix(".") { name.removeFirst() }
        let maxLen = 60
        if name.count > maxLen { name = String(name.prefix(maxLen)) }
        return name.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Reads just the Lectra title out of an `.ipynb` file without decoding the
    /// whole notebook.
    static func notebookTitle(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = json["metadata"] as? [String: Any],
              let lectra = metadata["lectra"] as? [String: Any],
              let title = lectra["title"] as? String else { return nil }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Classification (for `open`)

    /// Classifies a resolved, existing path into the thing the app should open,
    /// or nil if nothing in the app handles it.
    static func classify(_ url: URL) -> TerminalDocumentTarget? {
        let url = url.standardizedFileURL
        let components = homeRelativeComponents(of: url)

        // pdfs/<UUID>/...  →  PDF annotation editor.
        if components.first == "pdfs", components.count >= 2, let id = UUID(uuidString: components[1]) {
            let title = LectraDocumentIndex.document(for: id)?.title ?? "PDF"
            return .document(id: id, title: title)
        }

        // notebooks/<UUID>.ipynb  →  notebook editor.
        if components.first == "notebooks",
           let ipynb = components.first(where: { $0.hasSuffix(".ipynb") }) {
            let base = String(ipynb.dropLast(".ipynb".count))
            if let id = UUID(uuidString: base) {
                let fileURL = home.appendingPathComponent("notebooks").appendingPathComponent(ipynb)
                let title = notebookTitle(at: fileURL) ?? "Notebook"
                return .notebook(id: id, title: title)
            }
        }

        // Anything inside a project / git working tree  →  open that project.
        if let root = enclosingProjectRoot(of: url) {
            return .project(root: root)
        }

        return nil
    }

    /// The path of `url` relative to HOME, split into components ("" if not under
    /// HOME).
    private static func homeRelativeComponents(of url: URL) -> [String] {
        let homePath = home.path.hasSuffix("/") ? home.path : home.path + "/"
        guard url.path == home.path || url.path.hasPrefix(homePath) else { return [] }
        let rel = String(url.path.dropFirst(home.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return rel.isEmpty ? [] : rel.split(separator: "/").map(String.init)
    }

    /// Walks up from `url` to the nearest directory holding a `.git` (a project
    /// working tree), or the top-level `Projects/<name>` folder, without escaping
    /// HOME. Returns nil if the path isn't part of a project.
    private static func enclosingProjectRoot(of url: URL) -> URL? {
        let fm = FileManager.default
        let components = homeRelativeComponents(of: url)

        // A path directly under Projects/ is always treated as that project,
        // even before `git init`.
        if components.first == "Projects", components.count >= 2 {
            return home.appendingPathComponent("Projects").appendingPathComponent(components[1]).standardizedFileURL
        }

        var dir = url
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: dir.path, isDirectory: &isDir), !isDir.boolValue {
            dir = dir.deletingLastPathComponent()
        }
        while dir.path.count >= home.path.count {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                return dir.standardizedFileURL
            }
            if dir.standardizedFileURL == home { break }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}
