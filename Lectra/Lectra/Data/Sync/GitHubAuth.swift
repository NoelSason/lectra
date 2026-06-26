//
//  GitHubAuth.swift
//  Lectra
//
//  Holds the GitHub access token used by GitHubService. The token is obtained
//  through Supabase-managed GitHub OAuth (reusing the same ASWebAuthenticationSession
//  pattern as AuthManager) and stored in the Keychain. Connecting GitHub does NOT
//  change the user's primary Lectra account: we capture the provider token and
//  then restore the original Supabase session.
//
//  Requires the GitHub provider to be enabled in the Supabase dashboard with the
//  `repo` scope (needed for private repos and pushes).
//

import Foundation
import Combine
import Supabase
import AuthenticationServices

@MainActor
final class GitHubAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GitHubAuth()

    @Published private(set) var isConnected: Bool
    @Published var isWorking = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private let keychain = GitHubKeychain()

    /// The stored GitHub token, if connected. Read off the main actor by the
    /// service before each request.
    var token: String? { keychain.token }

    private override init() {
        self.client = SupabaseManager.shared.client
        self.isConnected = keychain.token != nil
        super.init()
    }

    private let callbackScheme = "com.canvascope.lectra"
    private var callbackURL: URL { URL(string: "\(callbackScheme)://auth/callback")! }

    // MARK: Connect / disconnect

    func connect() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        // GitHub must be *linked* to the signed-in Lectra account, not signed in
        // as a separate user — otherwise a GitHub account sharing the same email
        // collides ("Multiple accounts with the same email…"). Linking requires an
        // existing session.
        guard client.auth.currentSession != nil else {
            errorMessage = "Sign in to Lectra first, then connect GitHub."
            return
        }

        do {
            // Supabase only returns the GitHub provider token at the moment of
            // linking, and never refreshes or re-issues it. If the keychain token
            // is lost (reinstall, new device, or a prior disconnect that cleared
            // the token but left the identity linked), re-linking fails with
            // "422: Identity is already linked" and the auth sheet closes with no
            // token captured. Unlink any pre-existing GitHub identity first so the
            // link flow runs cleanly and hands back a fresh token. Allowed because
            // the account still has its primary (Google) identity — Supabase only
            // blocks unlinking the last remaining identity.
            if let existing = try? await client.auth.userIdentities()
                .first(where: { $0.provider == "github" }) {
                try? await client.auth.unlinkIdentity(existing)
            }

            let linkURL = try await client.auth.getLinkIdentityURL(
                provider: .github,
                scopes: "repo",
                redirectTo: callbackURL).url

            let callback = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: linkURL, callbackURLScheme: callbackScheme) { url, error in
                    if let error { cont.resume(throwing: error) }
                    else if let url { cont.resume(returning: url) }
                    else { cont.resume(throwing: GitHubError.notConnected) }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }

            // Exchange the link callback; the resulting session carries the GitHub
            // provider token and keeps the user on their original account.
            let session = try await client.auth.session(from: callback)
            guard let providerToken = session.providerToken else {
                throw GitHubError.http(0,
                    "GitHub linked, but no access token came back. Use a personal access token instead.")
            }
            keychain.token = providerToken
            isConnected = true

        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Manually set a Personal Access Token instead of OAuth (fallback path).
    func setToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        keychain.token = trimmed
        isConnected = true
    }

    func disconnect() {
        keychain.token = nil
        isConnected = false
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            return scene?.windows.first ?? ASPresentationAnchor()
        }
    }
}

// MARK: - Keychain

/// Minimal Keychain wrapper for the GitHub token (one service/account pair).
private struct GitHubKeychain {
    private let service = "com.canvascope.lectra.github"
    private let account = "provider_token"

    var token: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        nonmutating set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(base as CFDictionary)
            guard let newValue, let data = newValue.data(using: .utf8) else { return }
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}

// MARK: - Link store

/// Persists the GitHub binding for each local document (keyed by a stable id —
/// a notebook UUID or a code file's path). Kept in UserDefaults alongside the
/// app's other local document metadata.
struct GitLinkStore {
    static let shared = GitLinkStore()
    private let defaultsKey = "lectra.github.links.v1"

    private func all() -> [String: GitLink] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let map = try? JSONDecoder().decode([String: GitLink].self, from: data) else { return [:] }
        return map
    }

    private func persist(_ map: [String: GitLink]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func link(for key: String) -> GitLink? { all()[key] }

    func set(_ link: GitLink, for key: String) {
        var map = all(); map[key] = link; persist(map)
    }

    func remove(for key: String) {
        var map = all(); map.removeValue(forKey: key); persist(map)
    }
}
