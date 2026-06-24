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

struct FileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?
    var id: String { url.path }
    var name: String { url.lastPathComponent }

    static func build(_ root: URL, depth: Int = 0) -> [FileNode] {
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
    /// Debounced autosave: edits flush to disk shortly after typing pauses, and on
    /// file switch / leaving the workspace. Git is the version history, so there's
    /// no manual Save.
    @State private var autosaveWork: DispatchWorkItem?

    var body: some View {
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
            if showTerminal {
                Divider().overlay(LectraColor.sidebarDivider)
                TerminalView(startDirectory: project.url)
                    .frame(height: 320)
            }
        }
        .background(LectraColor.background.ignoresSafeArea())
        .onAppear { tree = FileNode.build(project.url) }
        .onDisappear { saveIfNeeded() }
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(tree) { node in
                    FileTreeRow(node: node, depth: 0, selected: selectedFile) { open($0) }
                }
            }
            .padding(.vertical, 8)
        }
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

    // MARK: Actions

    private func open(_ url: URL) {
        guard !url.hasDirectoryPath else { return }
        saveIfNeeded()
        // Skip obviously binary files.
        guard let data = try? Data(contentsOf: url), let str = String(data: data, encoding: .utf8) else {
            fileText = "// Binary or non-text file - can't edit here."
            selectedFile = url; dirty = false; return
        }
        fileText = str
        selectedFile = url
        dirty = false
    }

    /// Flush to disk a beat after typing stops (git keeps the history).
    private func scheduleAutosave() {
        autosaveWork?.cancel()
        let work = DispatchWorkItem { save() }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func save() {
        guard let url = selectedFile, dirty else { return }
        try? Data(fileText.utf8).write(to: url, options: .atomic)
        dirty = false
    }

    private func saveIfNeeded() {
        autosaveWork?.cancel()
        save()
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
