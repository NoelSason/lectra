//
//  ProjectsStore.swift
//  Lectra
//
//  Manages cloned code projects living under Documents/Projects/<repo>. This is
//  the on-disk home for everything the "Projects" sidebar tab shows: a real git
//  working tree the terminal and editor operate on directly, so edits persist and
//  `git` commands actually work against them.
//

import Foundation
import Combine

struct Project: Identifiable, Hashable {
    let url: URL
    var name: String { url.lastPathComponent }
    var id: String { url.path }
    var isGitRepo: Bool { FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) }
}

@MainActor
final class ProjectsStore: ObservableObject {
    static let shared = ProjectsStore()

    @Published private(set) var projects: [Project] = []
    @Published var cloning = false
    @Published var cloneStatus: String?
    @Published var lastError: String?

    private let git = GitRuntime()

    /// Documents/Projects - created on demand.
    static var projectsRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Projects", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() { reload() }

    func reload() {
        let root = Self.projectsRoot
        let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        projects = entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { Project(url: $0.standardizedFileURL) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Clones `repoFullName` (e.g. "owner/name") into Projects and refreshes.
    @discardableResult
    func clone(repoFullName: String) async -> Project? {
        let url = "https://github.com/\(repoFullName).git"
        let target = (repoFullName.split(separator: "/").last.map(String.init) ?? "repo")
        cloning = true; cloneStatus = "Cloning \(repoFullName)..."; lastError = nil
        defer { cloning = false; cloneStatus = nil }

        // If a folder with this name already exists, clone into a unique name.
        var finalTarget = target
        var n = 2
        while FileManager.default.fileExists(atPath: Self.projectsRoot.appendingPathComponent(finalTarget).path) {
            finalTarget = "\(target)-\(n)"; n += 1
        }

        let result = await git.run(argv: ["clone", url, finalTarget], cwd: Self.projectsRoot.path) { [weak self] line in
            self?.cloneStatus = line
        }
        if result.exitCode != 0 {
            lastError = result.stderr.isEmpty ? "Clone failed." : result.stderr
            return nil
        }
        reload()
        return projects.first { $0.name == finalTarget }
    }

    /// Commits any local changes, pulls remote work, and pushes the project to its
    /// `origin` remote in one pass via the shared git runtime. The repo's GitHub
    /// remote is the cloud, so this is how a project travels between devices.
    /// Returns a short human-readable summary; throws `ProjectSyncError` on failure.
    @discardableResult
    func sync(_ project: Project, message: String? = nil) async throws -> String {
        guard project.isGitRepo else { throw ProjectSyncError.notARepo }

        var argv = ["sync"]
        if let message, !message.isEmpty { argv += ["-m", message] }

        let result = await git.run(argv: argv, cwd: project.url.path)
        if result.exitCode != 0 {
            throw ProjectSyncError.git(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func delete(_ project: Project) {
        try? FileManager.default.removeItem(at: project.url)
        reload()
    }
}

enum ProjectSyncError: LocalizedError {
    case notARepo
    case git(String)

    var errorDescription: String? {
        switch self {
        case .notARepo:
            return "This project isn't a git repository, so there's nothing to sync."
        case .git(let message):
            return message.isEmpty ? "Sync failed. Please try again." : message
        }
    }
}
