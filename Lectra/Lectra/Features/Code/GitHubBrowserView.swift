//
//  GitHubBrowserView.swift
//  Lectra
//
//  Connect a GitHub account, browse repos / branches / folders, and pull files
//  into Lectra. Notebooks open in the notebook editor; other text files open in
//  the code editor. Each pulled file remembers where it came from (GitLink) so
//  it can be pushed back later.
//

import SwiftUI

struct GitHubBrowserView: View {
    @ObservedObject private var auth = GitHubAuth.shared
    @Environment(\.dismiss) private var dismiss

    /// When set, repos offer a "Clone in Terminal" action that hands the clone
    /// command back to the host (which opens the terminal).
    var onCloneInTerminal: ((String) -> Void)?

    @State private var repos: [GitHubRepo] = []
    @State private var loading = false
    @State private var error: String?
    @State private var patEntry = ""
    @State private var showTokenField = false
    @State private var path: [GitRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if auth.isConnected { repoList } else { connectView }
            }
            .background(LectraGradient.appBackdrop.ignoresSafeArea())
            .navigationTitle("GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundStyle(LectraColor.textSecondary)
                }
                if auth.isConnected {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) { auth.disconnect() } label: {
                                Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: { Image(systemName: "person.crop.circle").foregroundStyle(LectraColor.textSecondary) }
                    }
                }
            }
            .toolbarBackground(LectraColor.surfaceOverlay, for: .navigationBar)
            .navigationDestination(for: GitRoute.self) { route in
                destination(for: route)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: auth.isConnected) { if auth.isConnected { await loadRepos() } }
    }

    // MARK: Connect

    private var connectView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: LectraSpacing.lg)

            ZStack {
                Circle().fill(LectraColor.accentSoft.opacity(0.14)).frame(width: 76, height: 76)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(LectraColor.accentSoft)
            }
            .padding(.bottom, LectraSpacing.md)

            Text("Connect GitHub")
                .font(LectraTypography.title).foregroundStyle(LectraColor.textPrimary)
            Text("Pull notebooks, data, and code from your repositories — and push your changes back.")
                .font(LectraTypography.body).foregroundStyle(LectraColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, LectraSpacing.xs)
                .padding(.horizontal, LectraSpacing.md)

            Button {
                Task { await auth.connect() }
            } label: {
                HStack(spacing: LectraSpacing.sm) {
                    if auth.isWorking { ProgressView().controlSize(.small).tint(.white) }
                    Text(auth.isWorking ? "Connecting…" : "Connect with GitHub")
                }
                .font(LectraTypography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                    .fill(LectraColor.accent))
            }
            .disabled(auth.isWorking)
            .padding(.top, LectraSpacing.lg)

            if let msg = auth.errorMessage {
                Text(msg).font(LectraTypography.footnote).foregroundStyle(LectraColor.warning)
                    .multilineTextAlignment(.center)
                    .padding(.top, LectraSpacing.sm)
            }

            tokenSection
                .padding(.top, LectraSpacing.md)

            Spacer(minLength: LectraSpacing.lg)
        }
        .padding(.horizontal, LectraSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var tokenSection: some View {
        if showTokenField {
            VStack(spacing: LectraSpacing.sm) {
                SecureField("ghp_…", text: $patEntry)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(LectraColor.textPrimary)
                    .padding(.horizontal, LectraSpacing.md).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                        .fill(LectraColor.surfaceFloating.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                            .stroke(LectraColor.edgeStroke, lineWidth: 1)))
                Button {
                    auth.setToken(patEntry); patEntry = ""
                } label: {
                    Text("Save token").font(LectraTypography.bodyEmphasis)
                        .foregroundStyle(patEntry.isEmpty ? LectraColor.textTertiary : LectraColor.accentSoft)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                            .stroke(LectraColor.edgeStroke, lineWidth: 1))
                }
                .disabled(patEntry.isEmpty)
            }
        } else {
            Button("Use a personal access token instead") {
                withAnimation(.easeInOut(duration: 0.2)) { showTokenField = true }
            }
            .font(LectraTypography.footnoteBold)
            .foregroundStyle(LectraColor.textTertiary)
        }
    }

    // MARK: Repos

    private var repoList: some View {
        List {
            if loading && repos.isEmpty {
                ProgressView().tint(LectraColor.accentSoft)
                    .frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
            ForEach(repos) { repo in
                NavigationLink(value: GitRoute.browse(repo: repo.fullName, branch: repo.defaultBranch,
                                                      path: "", title: repo.shortName)) {
                    HStack(spacing: LectraSpacing.sm) {
                        Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed")
                            .font(.system(size: 13)).foregroundStyle(LectraColor.textTertiary)
                        Text(repo.fullName).foregroundStyle(LectraColor.textPrimary)
                    }
                }
                .listRowBackground(LectraColor.surfaceFloating.opacity(0.4))
                .swipeActions(edge: .trailing) {
                    if onCloneInTerminal != nil {
                        Button { cloneInTerminal(repo) } label: {
                            Label("Clone", systemImage: "terminal")
                        }.tint(LectraColor.accent)
                    }
                }
                .contextMenu {
                    if onCloneInTerminal != nil {
                        Button { cloneInTerminal(repo) } label: {
                            Label("Clone in Terminal", systemImage: "terminal")
                        }
                    }
                }
            }
            if let error {
                Text(error).font(LectraTypography.footnote).foregroundStyle(LectraColor.warning)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await loadRepos() }
    }

    @ViewBuilder
    private func destination(for route: GitRoute) -> some View {
        switch route {
        case let .browse(repo, branch, path, title):
            GitTreeView(repo: repo, branch: branch, path: path, title: title,
                        onPushDir: { self.path.append($0) },
                        onOpened: { dismiss() })
        }
    }

    private func loadRepos() async {
        loading = true; error = nil
        do { repos = try await GitHubService.shared.repos() }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    /// Hands a `git clone` for this repo to the host and closes the browser, so
    /// the clone runs in the real terminal against the shared sandbox.
    private func cloneInTerminal(_ repo: GitHubRepo) {
        onCloneInTerminal?("git clone https://github.com/\(repo.fullName).git")
        dismiss()
    }
}

// MARK: - Routes

enum GitRoute: Hashable {
    case browse(repo: String, branch: String, path: String, title: String)
}

// MARK: - Tree view

private struct GitTreeView: View {
    let repo: String
    let branch: String
    let path: String
    let title: String
    let onPushDir: (GitRoute) -> Void
    let onOpened: () -> Void

    @State private var entries: [GitHubEntry] = []
    @State private var loading = false
    @State private var error: String?
    @State private var pulling: String?
    @State private var openTarget: OpenTarget?

    var body: some View {
        List {
            if loading {
                ProgressView().tint(LectraColor.accentSoft)
                    .frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
            ForEach(entries) { entry in
                Button {
                    if entry.isDirectory {
                        onPushDir(.browse(repo: repo, branch: branch, path: entry.path, title: entry.name))
                    } else {
                        pull(entry)
                    }
                } label: {
                    HStack(spacing: LectraSpacing.sm) {
                        Image(systemName: icon(for: entry))
                            .font(.system(size: 14)).foregroundStyle(entry.isDirectory ? LectraColor.accentSoft : LectraColor.textTertiary)
                        Text(entry.name).foregroundStyle(LectraColor.textPrimary)
                        Spacer()
                        if pulling == entry.path { ProgressView().controlSize(.mini).tint(LectraColor.accentSoft) }
                        else if !entry.isDirectory { Image(systemName: "arrow.down.circle").foregroundStyle(LectraColor.textTertiary) }
                    }
                }
                .listRowBackground(LectraColor.surfaceFloating.opacity(0.4))
            }
            if let error {
                Text(error).font(LectraTypography.footnote).foregroundStyle(LectraColor.warning)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LectraGradient.appBackdrop.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openTarget) { target in
            switch target {
            case .notebook(let id):
                if let doc = NotebookStore.shared.load(id: id) {
                    NotebookView(document: doc)
                } else { Text("Couldn’t open notebook.") }
            case .code(let fileName, let key, let url):
                CodeEditorView(fileName: fileName, linkKey: key, fileURL: url)
            }
        }
        .task { await load() }
    }

    private func icon(for entry: GitHubEntry) -> String {
        if entry.isDirectory { return "folder.fill" }
        switch (entry.name as NSString).pathExtension.lowercased() {
        case "ipynb": return "book.closed.fill"
        case "csv", "tsv": return "tablecells"
        case "py": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.text"
        }
    }

    private func load() async {
        loading = true; error = nil
        do { entries = try await GitHubService.shared.contents(repo: repo, path: path, ref: branch) }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func pull(_ entry: GitHubEntry) {
        pulling = entry.path
        Task {
            do {
                let file = try await GitHubService.shared.getFile(repo: repo, path: entry.path, ref: branch)
                let link = GitLink(repoFullName: repo, branch: branch, path: entry.path, baseSha: file.sha)
                openTarget = try await route(for: entry, file: file, link: link)
            } catch {
                self.error = error.localizedDescription
            }
            pulling = nil
        }
    }

    private func route(for entry: GitHubEntry, file: GitHubFile, link: GitLink) async throws -> OpenTarget {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        if ext == "ipynb" {
            let nb = try JupyterNotebook(data: file.data)
            let doc = await MainActor.run { NotebookDocument(jupyter: nb) }
            await MainActor.run {
                NotebookStore.shared.save(doc)
                GitLinkStore.shared.set(link, for: doc.id.uuidString)
            }
            return .notebook(doc.id)
        } else {
            let id = UUID()
            let url = CodeFileStore.shared.url(id: id, ext: ext.isEmpty ? "txt" : ext)
            let text = String(data: file.data, encoding: .utf8) ?? ""
            CodeFileStore.shared.save(text, to: url)
            GitLinkStore.shared.set(link, for: entry.path)
            return .code(fileName: entry.name, key: entry.path, url: url)
        }
    }

    private enum OpenTarget: Hashable, Identifiable {
        case notebook(UUID)
        case code(fileName: String, key: String, url: URL)
        var id: String {
            switch self {
            case .notebook(let id): return "nb-\(id)"
            case .code(_, let key, _): return "code-\(key)"
            }
        }
    }
}
