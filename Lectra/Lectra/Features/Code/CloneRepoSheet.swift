//
//  CloneRepoSheet.swift
//  Lectra
//
//  GitHub repository picker for cloning repos into Documents/Projects.
//

import SwiftUI

// MARK: - Clone sheet

struct CloneRepoSheet: View {
    var onCloned: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = GitHubAuth.shared
    @ObservedObject private var store = ProjectsStore.shared
    @State private var repos: [GitHubRepo] = []
    @State private var loading = false
    @State private var error: String?
    @State private var pat = ""
    @State private var showPAT = false

    var body: some View {
        NavigationStack {
            Group {
                if store.cloning { cloningView }
                else if auth.isConnected { repoList }
                else { connectView }
            }
            .background(LectraColor.background.ignoresSafeArea())
            .navigationTitle("Clone a Repo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(LectraColor.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: auth.isConnected) { if auth.isConnected { await loadRepos() } }
    }

    private var cloningView: some View {
        VStack(spacing: 14) {
            ProgressView().tint(LectraColor.accent).controlSize(.large)
            Text(store.cloneStatus ?? "Cloning...")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(LectraColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 32)).foregroundStyle(LectraColor.accentSoft)
            Text("Connect GitHub to clone your repositories.")
                .font(.system(size: 15)).foregroundStyle(LectraColor.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
            Button { Task { await auth.connect() } } label: {
                Text(auth.isWorking ? "Connecting..." : "Connect with GitHub")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: 260).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 12).fill(LectraColor.accent))
            }
            .disabled(auth.isWorking)
            Button("Use a personal access token") { showPAT.toggle() }
                .font(.system(size: 13)).foregroundStyle(LectraColor.textTertiary)
            if showPAT {
                HStack {
                    SecureField("ghp_...", text: $pat)
                        .textFieldStyle(.plain).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .foregroundStyle(LectraColor.textPrimary)
                        .padding(.horizontal, 12).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(LectraColor.edgeStroke))
                    Button("Save") { auth.setToken(pat); pat = "" }.disabled(pat.isEmpty)
                        .foregroundStyle(LectraColor.accentSoft)
                }
                .frame(maxWidth: 300)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var repoList: some View {
        List {
            if loading && repos.isEmpty {
                ProgressView().tint(LectraColor.accentSoft).frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
            ForEach(repos) { repo in
                Button { clone(repo) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed")
                            .font(.system(size: 13)).foregroundStyle(LectraColor.textTertiary)
                        Text(repo.fullName).foregroundStyle(LectraColor.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.down.circle").foregroundStyle(LectraColor.accentSoft)
                    }
                }
                .listRowBackground(LectraColor.surfaceFloating.opacity(0.4))
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(LectraColor.warning).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await loadRepos() }
    }

    private func loadRepos() async {
        loading = true; error = nil
        do { repos = try await GitHubService.shared.repos() }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func clone(_ repo: GitHubRepo) {
        Task {
            if let project = await store.clone(repoFullName: repo.fullName) {
                onCloned(project)
            } else {
                error = store.lastError ?? "Clone failed."
            }
        }
    }
}
