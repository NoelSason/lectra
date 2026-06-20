//
//  AuthManager.swift
//  Lectra
//
//  Manages authentication state via Supabase Google OAuth.
//  Uses the same Google provider as the Lectra Chrome extension
//  so users log into the SAME Supabase account.
//

import Foundation
import Combine
import CryptoKit
import Supabase
import AuthenticationServices

@MainActor
final class AuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    struct MockState {
        var isAuthenticated: Bool
        var userId: UUID?
        var userEmail: String?
        var userName: String?
        var avatarURL: String?
    }

    // MARK: - Published State
    @Published var isAuthenticated = false
    @Published var userId: UUID?
    @Published var userEmail: String?
    @Published var userName: String?
    @Published var avatarURL: String?
    @Published var isLoading = true
    @Published var errorMessage: String?

    // MARK: - Private
    private let client: SupabaseClient
    private var mockState: MockState?
    private var currentAppleNonce: String?

    // MARK: - Init
    init(mockState: MockState? = nil) {
        self.client = SupabaseManager.shared.client
        self.mockState = mockState
        super.init()

        if let mockState {
            apply(mockState: mockState)
            return
        }

        bootstrapFromCurrentSession()
        Task { await checkExistingSession(showLoadingState: false) }
    }

    // MARK: - Session Check
    func checkExistingSession(showLoadingState: Bool = true) async {
        if let mockState {
            apply(mockState: mockState)
            return
        }

        if showLoadingState {
            isLoading = true
        }
        do {
            let session = try await client.auth.session
            applySession(session)
        } catch {
            clearSessionState()
        }
        if showLoadingState {
            isLoading = false
        }
    }

    // MARK: - Google Sign In (OAuth)
    func signInWithGoogle() async {
        if var mockState {
            mockState.isAuthenticated = true
            mockState.userId = mockState.userId ?? UUID(uuidString: "00000000-0000-0000-0000-000000000001")
            mockState.userEmail = mockState.userEmail ?? "ui-tests@canvascope.com"
            mockState.userName = mockState.userName ?? "UI Test Student"
            self.mockState = mockState
            apply(mockState: mockState)
            return
        }

        errorMessage = nil
        isLoading = true
        do {
            // 1. Get the OAuth URL from Supabase (same as Lectra extension)
            let oauthURL = try client.auth.getOAuthSignInURL(
                provider: .google,
                redirectTo: URL(string: "com.canvascope.lectra://auth/callback")
            )

            // 2. Present the system browser for login
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: oauthURL,
                    callbackURLScheme: "com.canvascope.lectra"
                ) { url, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let url = url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No callback URL received"]))
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }

            // 3. Let Supabase handle the redirect URL.
            // This automatically handles BOTH Implicit flows (token in fragment)
            // and PKCE flows (code in query param).
            let session = try await client.auth.session(from: callbackURL)
            applySession(session)

        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User cancelled – not an error
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Sign in with Apple
    /// Configures the Apple ID request with a fresh, hashed nonce. The raw
    /// nonce is retained so it can be replayed to Supabase for verification.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Handles the result from `SignInWithAppleButton` and exchanges the Apple
    /// identity token for a Supabase session via OpenID Connect.
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        if mockState != nil {
            await signInWithGoogle()
            return
        }

        errorMessage = nil

        switch result {
        case .failure(let error):
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                return // User cancelled – not an error.
            }
            errorMessage = error.localizedDescription
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let identityTokenData = credential.identityToken,
                let identityToken = String(data: identityTokenData, encoding: .utf8),
                let nonce = currentAppleNonce
            else {
                errorMessage = "Apple sign-in did not return the expected credentials."
                return
            }

            isLoading = true
            do {
                let session = try await client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: identityToken, nonce: nonce)
                )
                applySession(session)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            currentAppleNonce = nil
        }
    }

    // MARK: - Apply Session
    private func applySession(_ session: Session) {
        prepareLocalDataForSession(userId: session.user.id)
        userId = session.user.id
        userEmail = session.user.email
        userName = session.user.userMetadata["full_name"]?.stringValue
                ?? session.user.userMetadata["name"]?.stringValue
        avatarURL = session.user.userMetadata["avatar_url"]?.stringValue
        isAuthenticated = true
        isLoading = false
    }

    private func prepareLocalDataForSession(userId newUserId: UUID) {
        let storedOwnerUserId = LectraLocalAccountData.ownerUserId()
        let isSwitchingFromActiveUser = userId.map { $0 != newUserId } ?? false
        let hasDifferentStoredOwner = storedOwnerUserId.map { $0 != newUserId } ?? false
        let hasLegacyUnownedDocuments = storedOwnerUserId == nil && LectraLocalAccountData.hasUnownedLocalDocuments()

        if isSwitchingFromActiveUser || hasDifferentStoredOwner || hasLegacyUnownedDocuments {
            LectraLocalAccountData.purgeAccountScopedData()
            DocumentSyncCoordinator.shared.clearPendingJobsForAccountBoundary()
        }

        LectraLocalAccountData.markOwner(newUserId)
    }

    private func apply(mockState: MockState) {
        isAuthenticated = mockState.isAuthenticated
        userId = mockState.isAuthenticated ? mockState.userId : nil
        userEmail = mockState.isAuthenticated ? mockState.userEmail : nil
        userName = mockState.isAuthenticated ? mockState.userName : nil
        avatarURL = mockState.isAuthenticated ? mockState.avatarURL : nil
        errorMessage = nil
        isLoading = false
    }

    private func bootstrapFromCurrentSession() {
        if let session = client.auth.currentSession {
            applySession(session)
        } else {
            clearSessionState()
        }
        isLoading = false
    }

    private func clearSessionState() {
        isAuthenticated = false
        userId = nil
        userEmail = nil
        userName = nil
        avatarURL = nil
    }

    // MARK: - Sign Out
    func signOut() async {
        if var mockState {
            mockState.isAuthenticated = false
            self.mockState = mockState
            apply(mockState: mockState)
            return
        }

        do {
            try await client.auth.signOut()
        } catch {
            // Best-effort
        }
        LectraLocalAccountData.purgeAccountScopedData()
        DocumentSyncCoordinator.shared.clearPendingJobsForAccountBoundary()
        clearSessionState()
    }

    // MARK: - Account Deletion
    /// Permanently deletes the signed-in user's Lectra account and all of
    /// their server-side data. The destructive work runs in the `delete-account`
    /// Supabase Edge Function (service-role), which the SDK invokes with the
    /// user's JWT so the function can identify and authorize the caller.
    func deleteAccount() async throws {
        if var mockState {
            mockState.isAuthenticated = false
            self.mockState = mockState
            apply(mockState: mockState)
            return
        }

        // Ensure we have a valid session before asking the backend to delete it.
        _ = try await client.auth.session

        try await client.functions.invoke("delete-account", decode: { _, _ in })

        try? await client.auth.signOut()
        LectraLocalAccountData.purgeAccountScopedData()
        DocumentSyncCoordinator.shared.clearPendingJobsForAccountBoundary()
        clearSessionState()
    }

    // MARK: - Nonce Helpers (Sign in with Apple)
    private static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<length).map { _ in UInt8.random(in: 0...255) }
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first as? UIWindowScene
            return windowScene?.windows.first ?? ASPresentationAnchor()
        }
    }
}

// MARK: - JSON Value helper
extension Supabase.AnyJSON {
    var stringValue: String? {
        switch self {
        case .string(let s): return s
        default: return nil
        }
    }
}
