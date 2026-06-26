//
//  ProjectWorkspaceView.swift
//  Lectra
//
//  The full-screen coding workspace for one cloned project: a file tree, a fast
//  code editor that saves straight to disk, and an integrated terminal rooted at
//  the project - so edits persist and git commands run against the real repo.
//

import SwiftUI

// MARK: - File tree model

struct FileNode: Identifiable, Hashable, Sendable {
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?
    nonisolated var id: String { url.path }
    nonisolated var name: String { url.lastPathComponent }

    nonisolated static func build(_ root: URL, depth: Int = 0) -> [FileNode] {
        let skip: Set<String> = [".git", "node_modules", ".DS_Store", ".build", "DerivedData"]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
        return entries
            .filter { !skip.contains($0.lastPathComponent) }
            .map { url -> FileNode in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                // Cap recursion depth to keep huge repos responsive; deeper dirs
                // load when tapped via rebuild.
                let kids = (isDir && depth < 6) ? build(url, depth: depth + 1) : (isDir ? [] : nil)
                return FileNode(url: url.standardizedFileURL, isDirectory: isDir, children: kids)
            }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
                return a.name.lowercased() < b.name.lowercased()
            }
    }
}

// MARK: - Workspace

struct ProjectWorkspaceView: View {
    let project: Project
    var onClose: (() -> Void)?

    @State private var tree: [FileNode] = []
    @State private var selectedFile: URL?
    @State private var fileText: String = ""
    @State private var dirty = false
    @State private var showTree = true
    @State private var showTerminal = false
    /// Height of the integrated terminal pane, draggable via the handle above it.
    /// `terminalDragBase` holds the height at the start of the current drag.
    @State private var terminalHeight: CGFloat = 280
    @State private var terminalDragBase: CGFloat = 280
    @State private var showNewFileAlert = false
    @State private var newFilePath = ""
    /// Debounced autosave: edits flush to disk shortly after typing pauses, and on
    /// file switch / leaving the workspace. Git is the version history, so there's
    /// no manual Save.
    @State private var autosaveTask: Task<Void, Never>?
    @State private var treeRefreshTask: Task<Void, Never>?
    @State private var fileLoadTask: Task<Void, Never>?
    @State private var editGeneration = 0
    /// One-tap GitHub sync (commit + pull + push). Git is the cloud for projects.
    @State private var syncing = false
    @State private var syncNotice: String?
    @State private var syncFailed = false

    var body: some View {
        GeometryReader { geo in
            let maxTerminalHeight = max(160, geo.size.height - 220)
            VStack(spacing: 0) {
                header
                Divider().overlay(LectraColor.sidebarDivider)
                HStack(spacing: 0) {
                    if showTree {
                        fileTree
                            .frame(width: 250)
                            .background(LectraColor.sidebarBackground)
                        Divider().overlay(LectraColor.sidebarDivider)
                    }
                    editorPane
                }
                .frame(maxHeight: .infinity)
                if showTerminal {
                    terminalResizeHandle(maxHeight: maxTerminalHeight)
                    TerminalView(startDirectory: project.url, onCommandFinished: { command, exitCode in
                        handleTerminalCommandFinished(command: command, exitCode: exitCode)
                    })
                        .frame(height: min(terminalHeight, maxTerminalHeight))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: geo.size.height) { _, _ in
                terminalHeight = min(terminalHeight, maxTerminalHeight)
                terminalDragBase = terminalHeight
            }
        }
        .background(LectraColor.background.ignoresSafeArea())
        .onAppear {
            LectraPerformanceTrace.setActiveSurface(.projects)
            refreshTree()
        }
        .onDisappear {
            saveIfNeeded()
            treeRefreshTask?.cancel()
            fileLoadTask?.cancel()
            LectraPerformanceTrace.setActiveSurface(.unknown)
        }
        .onReceive(NotificationCenter.default.publisher(for: .lectraOpenFileInEditor)) { note in
            openFileFromTerminal(note)
        }
        .alert("New File", isPresented: $showNewFileAlert) {
            TextField("path/to/file.swift", text: $newFilePath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Create") { createNewFile() }
            Button("Cancel", role: .cancel) { newFilePath = "" }
        } message: {
            Text("Create a file in this project. Folders in the path will be created.")
        }
        .alert(syncFailed ? "Sync" : "Synced", isPresented: syncNoticePresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(syncNotice ?? "")
        }
    }

    private var syncNoticePresented: Binding<Bool> {
        Binding(get: { syncNotice != nil }, set: { if !$0 { syncNotice = nil } })
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            if let onClose {
                Button { saveIfNeeded(); onClose() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                        Text("Projects").font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(LectraColor.accentSoft)
                }
            }
            Button { withAnimation(.easeInOut(duration: 0.15)) { showTree.toggle() } } label: {
                Image(systemName: "sidebar.left").foregroundStyle(LectraColor.textSecondary)
            }
            Image(systemName: "folder.fill").foregroundStyle(LectraColor.accent).font(.system(size: 13))
            Text(project.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(LectraColor.textPrimary)
            if let selectedFile {
                Text("- \(selectedFile.lastPathComponent)")
                    .font(.system(size: 13))
                    .foregroundStyle(LectraColor.textTertiary)
            }
            Spacer()
            if selectedFile != nil {
                // Autosave status: a quiet indicator instead of a Save button.
                Text(dirty ? "Saving..." : "Saved")
                    .font(.system(size: 12))
                    .foregroundStyle(LectraColor.textTertiary)
            }
            if syncing {
                ProgressView()
                    .controlSize(.small)
                    .tint(LectraColor.accentSoft)
                    .accessibilityLabel("Syncing")
            } else {
                Button { runSync() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(LectraColor.textSecondary)
                }
                .accessibilityLabel("Sync to GitHub")
            }
            Button { withAnimation(.easeInOut(duration: 0.15)) { showTerminal.toggle() } } label: {
                Image(systemName: "terminal")
                    .foregroundStyle(showTerminal ? LectraColor.accent : LectraColor.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: File tree

    private var fileTree: some View {
        VStack(spacing: 0) {
            fileTreeToolbar
            Divider().overlay(LectraColor.sidebarDivider)
            ScrollView {
                if tree.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 24))
                            .foregroundStyle(LectraColor.textTertiary)
                        Text("No files yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(LectraColor.textTertiary)
                        Button { showNewFileAlert = true } label: {
                            Label("New File", systemImage: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(LectraColor.accentSoft)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(tree) { node in
                            FileTreeRow(node: node, depth: 0, selected: selectedFile) { open($0) }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var fileTreeToolbar: some View {
        HStack(spacing: 8) {
            Text("Files")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LectraColor.textSecondary)
            Spacer(minLength: 0)
            Button { showNewFileAlert = true } label: {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LectraColor.accentSoft)
            .accessibilityLabel("New File")

            Button { refreshTree() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LectraColor.textTertiary)
            .accessibilityLabel("Refresh Files")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Editor

    @ViewBuilder
    private var editorPane: some View {
        if selectedFile != nil {
            SourceEditorView(
                text: $fileText,
                language: CodeLanguage(fileExtension: selectedFile?.pathExtension ?? ""),
                onChange: { dirty = true; scheduleAutosave() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text").font(.system(size: 36)).foregroundStyle(LectraColor.textTertiary)
                Text("Select a file to edit").font(.system(size: 15)).foregroundStyle(LectraColor.textTertiary)
                Text("Open the terminal to run git, build, or shell commands in this project.")
                    .font(.system(size: 12)).foregroundStyle(LectraColor.textTertiary.opacity(0.7))
                    .multilineTextAlignment(.center).frame(maxWidth: 280)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Terminal resize

    /// A draggable grip above the terminal. Dragging up grows the terminal,
    /// dragging down shrinks it, clamped between a usable minimum and `maxHeight`.
    private func terminalResizeHandle(maxHeight: CGFloat) -> some View {
        ZStack {
            LectraColor.surfaceFloating
            Capsule()
                .fill(LectraColor.textTertiary.opacity(0.5))
                .frame(width: 40, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 16)
        .overlay(Divider().overlay(LectraColor.sidebarDivider), alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    let proposed = terminalDragBase - value.translation.height
                    terminalHeight = min(max(proposed, 120), maxHeight)
                }
                .onEnded { _ in terminalDragBase = terminalHeight }
        )
    }

    /// Opens a file requested by the terminal's `nano`/`vi`/`vim` command, as long
    /// as it lives inside this project, loading it into the editor pane.
    private func openFileFromTerminal(_ note: Notification) {
        guard let path = note.userInfo?["path"] as? String else { return }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let root = project.url.standardizedFileURL.path
        guard url.path == root || url.path.hasPrefix(root + "/") else { return }
        refreshTree(debounce: 0.1) // a file `nano` just created should show in the tree
        open(url)
    }

    // MARK: Actions

    private func open(_ url: URL) {
        let fileURL = url.standardizedFileURL
        guard !fileURL.hasDirectoryPath else { return }
        saveIfNeeded()

        fileLoadTask?.cancel()
        fileLoadTask = Task {
            let loadedText = await Task.detached(priority: .userInitiated) { () -> String? in
                LectraPerformanceTrace.withSignpost(.projects, "OpenProjectFile") {
                    guard let data = try? Data(contentsOf: fileURL) else { return nil }
                    return String(data: data, encoding: .utf8)
                }
            }.value

            guard !Task.isCancelled else { return }
            fileText = loadedText ?? "// Binary or non-text file - can't edit here."
            selectedFile = fileURL
            dirty = false
        }
    }

    private func refreshTree(debounce delay: TimeInterval? = nil) {
        treeRefreshTask?.cancel()
        let root = project.url
        treeRefreshTask = Task {
            if let delay {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
            }

            let nodes = await Task.detached(priority: .utility) {
                LectraPerformanceTrace.withSignpost(.projects, "BuildProjectTree") {
                    FileNode.build(root)
                }
            }.value

            guard !Task.isCancelled else { return }
            tree = nodes
        }
    }

    private func handleTerminalCommandFinished(command: String, exitCode: Int32) {
        guard exitCode == 0, terminalCommandMayMutateProject(command) else { return }
        refreshTree(debounce: 0.35)
    }

    private func terminalCommandMayMutateProject(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains(">") { return true }

        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "|;&"))
        let tokens = trimmed
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return false }

        let mutatingBuiltins: Set<String> = ["touch", "mkdir", "rmdir", "rm", "cp", "mv"]
        let readOnlyGitSubcommands: Set<String> = ["status", "log", "diff", "show"]

        for (index, token) in tokens.enumerated() {
            if mutatingBuiltins.contains(token) {
                return true
            }
            if token == "git" {
                let subcommand = tokens.dropFirst(index + 1).first { !$0.hasPrefix("-") }
                guard let subcommand else { return false }
                return !readOnlyGitSubcommands.contains(subcommand)
            }
        }

        return false
    }

    private func createNewFile() {
        let rawPath = newFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        newFilePath = ""
        guard !rawPath.isEmpty else { return }

        let normalizedPath = rawPath.replacingOccurrences(of: "\\", with: "/")
        guard !normalizedPath.hasPrefix("/"), !normalizedPath.hasSuffix("/") else { return }

        let parts = normalizedPath.split(separator: "/").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return }

        var fileURL = project.url
        for part in parts {
            fileURL.appendPathComponent(part)
        }
        fileURL = fileURL.standardizedFileURL

        Task {
            await Task.detached(priority: .utility) {
                let parentURL = fileURL.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
                }
            }.value

            guard !Task.isCancelled else { return }
            refreshTree()
            open(fileURL)
        }
    }

    /// Flush to disk a beat after typing stops (git keeps the history).
    private func scheduleAutosave() {
        guard let url = selectedFile else { return }
        dirty = true
        editGeneration &+= 1
        let generation = editGeneration
        let text = fileText

        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await write(text: text, to: url, generation: generation)
        }
    }

    private func save() {
        guard let url = selectedFile, dirty else { return }
        editGeneration &+= 1
        let generation = editGeneration
        let text = fileText

        Task {
            await write(text: text, to: url, generation: generation)
        }
    }

    private func write(text: String, to url: URL, generation: Int) async {
        let didWrite = await Task.detached(priority: .utility) {
            LectraPerformanceTrace.withSignpost(.projects, "SaveProjectFile") {
                do {
                    try Data(text.utf8).write(to: url, options: .atomic)
                    return true
                } catch {
                    return false
                }
            }
        }.value

        guard didWrite, selectedFile == url, editGeneration == generation else { return }
        dirty = false
    }

    private func saveIfNeeded() {
        autosaveTask?.cancel()
        save()
    }

    /// Flush the in-flight edit to disk and wait for it, so git stages the latest
    /// bytes rather than racing the debounced autosave.
    private func flushPendingWrite() async {
        autosaveTask?.cancel()
        guard let url = selectedFile, dirty else { return }
        editGeneration &+= 1
        await write(text: fileText, to: url, generation: editGeneration)
    }

    /// Commit local changes, pull, and push to the project's GitHub remote.
    private func runSync() {
        guard !syncing else { return }
        syncing = true
        Task {
            await flushPendingWrite()
            do {
                let summary = try await ProjectsStore.shared.sync(project)
                syncFailed = false
                syncNotice = summary.isEmpty ? "Synced with GitHub." : summary
                refreshTree(debounce: 0.1)
            } catch {
                syncFailed = true
                syncNotice = error.localizedDescription
            }
            syncing = false
        }
    }
}

// MARK: - Tree row (recursive, with disclosure)

private struct FileTreeRow: View {
    let node: FileNode
    let depth: Int
    let selected: URL?
    let onSelect: (URL) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if node.isDirectory { withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() } }
                else { onSelect(node.url) }
            } label: {
                HStack(spacing: 6) {
                    if node.isDirectory {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(LectraColor.textTertiary)
                            .frame(width: 10)
                    } else {
                        Image(systemName: icon).font(.system(size: 11))
                            .foregroundStyle(LectraColor.textTertiary).frame(width: 10)
                    }
                    Text(node.name)
                        .font(.system(size: 13, design: node.isDirectory ? .rounded : .monospaced))
                        .foregroundStyle(selected == node.url ? LectraColor.accentSoft : LectraColor.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .padding(.leading, CGFloat(depth) * 12 + 12)
                .padding(.trailing, 8)
                .background(selected == node.url ? LectraColor.sidebarSelection : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if node.isDirectory, expanded, let children = node.children {
                ForEach(children) { child in
                    FileTreeRow(node: child, depth: depth + 1, selected: selected, onSelect: onSelect)
                }
            }
        }
    }

    private var icon: String {
        switch node.url.pathExtension.lowercased() {
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "json": return "curlybraces.square"
        case "md", "markdown": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "pdf": return "photo"
        default: return "doc.text"
        }
    }
}
