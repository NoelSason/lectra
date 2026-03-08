import Foundation

final class GradescopeAuthService: GradescopeAuthenticating {
    private struct SessionVerificationResult {
        let isAuthenticated: Bool
        let debugLines: [String]
    }

    private let httpClient: GradescopeHTTPClient
    private let parser: GradescopeHTMLParser
    private let keychainStore: GradescopeKeychainStore

    private(set) var isAuthenticated = false
    private(set) var lastWebSessionImportDebugReport: String?

    var sessionExpirationDate: Date? {
        httpClient.sessionExpirationDate
    }

    init(
        httpClient: GradescopeHTTPClient,
        parser: GradescopeHTMLParser,
        keychainStore: GradescopeKeychainStore
    ) {
        self.httpClient = httpClient
        self.parser = parser
        self.keychainStore = keychainStore
    }

    func restoreSession() async -> Bool {
        guard let snapshot = keychainStore.load() else {
            isAuthenticated = false
            return false
        }

        httpClient.restore(from: snapshot)

        do {
            let loggedIn = try await verifyAuthenticatedSession()
            isAuthenticated = loggedIn
            if !loggedIn {
                logout()
            }
            return loggedIn
        } catch {
            logout()
            return false
        }
    }

    func login(email: String, password: String) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            throw GSError.invalidCredentials
        }

        let homepage = try await httpClient.get(path: "/")
        let homepageHTML = String(decoding: homepage.data, as: UTF8.self)

        guard let authToken = parser.parseLoginAuthenticityToken(from: homepageHTML) else {
            throw GSError.missingAuthToken
        }

        let loginResponse = try await httpClient.postForm(
            path: "/login",
            fields: [
                "utf8": "✓",
                "session[email]": trimmedEmail,
                "session[password]": password,
                "session[remember_me]": "0",
                "commit": "Log In",
                "session[remember_me_sso]": "0",
                "authenticity_token": authToken
            ],
            referer: homepage.url
        )

        let loginHTML = String(decoding: loginResponse.data, as: UTF8.self)
        if let flashError = parser.parseFlashErrorMessage(from: loginHTML) {
            if flashError.lowercased().contains("invalid email/password") {
                throw GSError.invalidCredentials
            }

            // Propagate server feedback for account-specific policies (e.g. SSO-required accounts).
            throw GSError.network(flashError)
        }

        if let csrf = parser.parseCSRFToken(from: loginHTML) {
            httpClient.csrfToken = csrf
        }

        let verification = try await verifyAuthenticatedSessionDetailed(
            referer: loginResponse.url,
            seedHTML: loginHTML,
            requireNetworkProbe: true
        )
        guard verification.isAuthenticated else {
            throw GSError.invalidCredentials
        }

        let snapshot = try httpClient.makeSnapshot()
        try keychainStore.save(snapshot: snapshot)
        isAuthenticated = true
    }

    func loginWithImportedWebSession(cookies: [HTTPCookie], accountPageHTML: String?) async throws {
        var debugLines: [String] = []
        debugLines.append("web-import start")
        debugLines.append("incoming cookies total=\(cookies.count)")
        debugLines.append("incoming gradescope cookies=\(cookies.filter { $0.domain.lowercased().contains("gradescope.com") }.count)")
        debugLines.append(contentsOf: summarizeCookies(cookies, label: "incoming"))
        debugLines.append(contentsOf: summarizeHTML(accountPageHTML, label: "seed-html"))
        do {
            guard !cookies.isEmpty else {
                debugLines.append("fail: no cookies passed from WKWebView")
                throw GSError.webSessionImportFailed
            }

            httpClient.clearSession()
            debugLines.append("http-client session cleared")
            httpClient.importCookies(cookies)
            debugLines.append(contentsOf: summarizeCookies(httpClient.cookies(domainContains: "gradescope.com"), label: "http-client"))

            let hasSessionCookie = httpClient.hasCookie(named: "_gradescope_session", domainContains: "gradescope.com")
            debugLines.append("http-client has _gradescope_session=\(hasSessionCookie)")
            guard hasSessionCookie else {
                debugLines.append("fail: missing _gradescope_session after import")
                throw GSError.webSessionImportFailed
            }

            if let accountPageHTML, let csrf = parser.parseCSRFToken(from: accountPageHTML) {
                httpClient.csrfToken = csrf
                debugLines.append("csrf set from seed-html=true")
            } else {
                debugLines.append("csrf set from seed-html=false")
            }

            // Always verify against live HTTP calls in URLSession so imported cookies are proven valid.
            let verification = try await verifyAuthenticatedSessionDetailed(
                seedHTML: accountPageHTML,
                requireNetworkProbe: true
            )
            debugLines.append(contentsOf: verification.debugLines.map { "verify \($0)" })

            guard verification.isAuthenticated else {
                debugLines.append("fail: live verification returned unauthenticated")
                throw GSError.webSessionImportFailed
            }

            let snapshot = try httpClient.makeSnapshot()
            try keychainStore.save(snapshot: snapshot)
            isAuthenticated = true
            debugLines.append("success: snapshot saved to keychain")
            lastWebSessionImportDebugReport = debugLines.joined(separator: "\n")
        } catch {
            debugLines.append("throw error: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            lastWebSessionImportDebugReport = debugLines.joined(separator: "\n")
            throw error
        }
    }

    func logout() {
        httpClient.clearSession()
        keychainStore.clear()
        isAuthenticated = false
        lastWebSessionImportDebugReport = nil
    }

    private func verifyAuthenticatedSession(
        referer: URL? = nil,
        seedHTML: String? = nil,
        requireNetworkProbe: Bool = false
    ) async throws -> Bool {
        let result = try await verifyAuthenticatedSessionDetailed(
            referer: referer,
            seedHTML: seedHTML,
            requireNetworkProbe: requireNetworkProbe
        )
        return result.isAuthenticated
    }

    private func verifyAuthenticatedSessionDetailed(
        referer: URL? = nil,
        seedHTML: String? = nil,
        requireNetworkProbe: Bool = false
    ) async throws -> SessionVerificationResult {
        var debugLines: [String] = []
        debugLines.append("begin requireNetworkProbe=\(requireNetworkProbe)")
        debugLines.append("referer=\(referer?.absoluteString ?? "none")")

        if let seedHTML {
            if let csrf = parser.parseCSRFToken(from: seedHTML) {
                httpClient.csrfToken = csrf
                debugLines.append("seed-html csrf parsed=true")
            } else {
                debugLines.append("seed-html csrf parsed=false")
            }
            debugLines.append(contentsOf: summarizeHTML(seedHTML, label: "verify-seed-html"))

            if !requireNetworkProbe && parser.isLikelyAuthenticatedAccountPage(seedHTML) {
                debugLines.append("return true from seed-html auth markers")
                return SessionVerificationResult(isAuthenticated: true, debugLines: debugLines)
            }
        }

        let probePaths = ["/account", "/"]
        var firstNetworkError: GSError?
        var sawUnauthorizedOrLogin = false

        for path in probePaths {
            do {
                let response = try await httpClient.get(path: path, referer: referer)
                let status = response.response.statusCode
                debugLines.append("probe \(path) status=\(status) final=\(response.url.path)")

                if status == 401 || status == 403 {
                    sawUnauthorizedOrLogin = true
                    debugLines.append("probe \(path) unauthorized")
                    continue
                }

                guard status == 200 else {
                    debugLines.append("probe \(path) non-200 skipped")
                    continue
                }

                let html = String(decoding: response.data, as: UTF8.self)
                if let csrf = parser.parseCSRFToken(from: html) {
                    httpClient.csrfToken = csrf
                    debugLines.append("probe \(path) csrf parsed=true")
                } else {
                    debugLines.append("probe \(path) csrf parsed=false")
                }

                let isLogin = parser.isLikelyLoginPage(html) || response.url.path.hasPrefix("/login")
                let isAuth = parser.isLikelyAuthenticatedAccountPage(html)
                debugLines.append("probe \(path) loginPage=\(isLogin) authPage=\(isAuth)")
                if isLogin {
                    sawUnauthorizedOrLogin = true
                    debugLines.append("probe \(path) identified as login page")
                    continue
                }

                if isAuth {
                    debugLines.append("return true from auth markers on \(path)")
                    return SessionVerificationResult(isAuthenticated: true, debugLines: debugLines)
                }

                // /account is an authenticated route; if we reached a non-login 200 page,
                // treat the session as valid even when UI markers change.
                if path == "/account" {
                    debugLines.append("return true from /account non-login 200 fallback")
                    return SessionVerificationResult(isAuthenticated: true, debugLines: debugLines)
                }

            } catch let error as GSError {
                debugLines.append("probe \(path) error=\(error.localizedDescription)")
                if firstNetworkError == nil {
                    firstNetworkError = error
                }
            } catch {
                debugLines.append("probe \(path) error=\(error.localizedDescription)")
                if firstNetworkError == nil {
                    firstNetworkError = .network(error.localizedDescription)
                }
            }
        }

        if sawUnauthorizedOrLogin {
            debugLines.append("return false due to unauthorized/login probe")
            return SessionVerificationResult(isAuthenticated: false, debugLines: debugLines)
        }

        if let firstNetworkError {
            debugLines.append("throw firstNetworkError=\(firstNetworkError.localizedDescription)")
            throw firstNetworkError
        }

        debugLines.append("return false: no positive auth signals found")
        return SessionVerificationResult(isAuthenticated: false, debugLines: debugLines)
    }

    private func summarizeCookies(_ cookies: [HTTPCookie], label: String) -> [String] {
        if cookies.isEmpty {
            return ["\(label) cookies: none"]
        }

        let sorted = cookies.sorted {
            if $0.domain == $1.domain {
                return $0.name < $1.name
            }
            return $0.domain < $1.domain
        }

        var lines: [String] = []
        lines.append("\(label) cookies summary count=\(sorted.count)")
        for cookie in sorted.prefix(20) {
            let expires: String
            if let date = cookie.expiresDate {
                expires = ISO8601DateFormatter().string(from: date)
            } else {
                expires = "session"
            }

            lines.append(
                "\(label) cookie name=\(cookie.name) domain=\(cookie.domain) path=\(cookie.path) secure=\(cookie.isSecure) expires=\(expires)"
            )
        }
        if sorted.count > 20 {
            lines.append("\(label) cookies truncated: +\(sorted.count - 20) more")
        }
        return lines
    }

    private func summarizeHTML(_ html: String?, label: String) -> [String] {
        guard let html else {
            return ["\(label): none"]
        }

        let normalized = html.lowercased()
        let hasDashboard = normalized.contains("course dashboard")
        let hasCourses = normalized.contains("coursebox--shortname") || normalized.contains("/courses/")
        let hasLogout = normalized.contains("href=\"/logout\"") || normalized.contains("/sign_out")
        let hasCSRFMeta = parser.parseCSRFToken(from: html) != nil
        let isLoginPage = parser.isLikelyLoginPage(html)
        let isAuthPage = parser.isLikelyAuthenticatedAccountPage(html)

        return [
            "\(label) length=\(html.count)",
            "\(label) signals login=\(isLoginPage) auth=\(isAuthPage) csrfMeta=\(hasCSRFMeta) dashboard=\(hasDashboard) courses=\(hasCourses) logout=\(hasLogout)"
        ]
    }
}
