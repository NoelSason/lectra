import Foundation
import WebKit

enum CanvasCookieStore {
    static let persistedCookiesDefaultsKey = "LectraCanvasPersistedCookies"

    private static let syntheticExpiryMarkerKey = "LectraSyntheticExpiration"
    private static let primaryHostDefaultsKey = "LectraCanvasPrimaryHost"
    private static let syntheticExpiryLifetime: TimeInterval = 30 * 24 * 60 * 60

    struct StoredCookie {
        let cookie: HTTPCookie
        let usesSyntheticExpiry: Bool
    }

    static func persist(_ cookies: [HTTPCookie], primaryHost: String?) {
        let scopedCookies = filter(cookies: cookies, for: primaryHost)
        let serializedCookies = scopedCookies.compactMap { cookie -> [String: Any]? in
            guard var properties = cookie.properties else { return nil }

            let hadExplicitExpiration = properties[.expires] != nil
            if !hadExplicitExpiration {
                properties[.expires] = Date().addingTimeInterval(syntheticExpiryLifetime)
            }

            var safeProperties: [String: Any] = [:]
            for (key, value) in properties {
                safeProperties[key.rawValue] = value
            }
            safeProperties[syntheticExpiryMarkerKey] = !hadExplicitExpiration
            return safeProperties
        }

        UserDefaults.standard.set(serializedCookies, forKey: persistedCookiesDefaultsKey)
        if let primaryHost = primaryHost?.lowercased(), !primaryHost.isEmpty {
            UserDefaults.standard.set(primaryHost, forKey: primaryHostDefaultsKey)
        }

        NotificationCenter.default.post(name: .lectraCanvasSessionUpdated, object: nil)
    }

    static func load() -> [StoredCookie] {
        guard let cookieDictionaries = UserDefaults.standard.array(forKey: persistedCookiesDefaultsKey) as? [[String: Any]] else {
            return []
        }

        return cookieDictionaries.compactMap { dictionary in
            let usesSyntheticExpiry = dictionary[syntheticExpiryMarkerKey] as? Bool ?? false

            var properties: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in dictionary where key != syntheticExpiryMarkerKey {
                properties[HTTPCookiePropertyKey(rawValue: key)] = value
            }

            guard let cookie = HTTPCookie(properties: properties) else {
                return nil
            }

            return StoredCookie(cookie: cookie, usesSyntheticExpiry: usesSyntheticExpiry)
        }
    }

    static func restoreIntoDefaultWebViewStore() async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        for storedCookie in load() {
            await cookieStore.setCookie(storedCookie.cookie)
        }
    }

    static func loadMergedSession() async -> [StoredCookie] {
        var mergedCookies: [CookieIdentity: StoredCookie] = [:]
        for storedCookie in load() {
            mergedCookies[CookieIdentity(cookie: storedCookie.cookie)] = storedCookie
        }

        for liveCookie in await liveCookies() {
            let identity = CookieIdentity(cookie: liveCookie.cookie)
            if let existingCookie = mergedCookies[identity] {
                mergedCookies[identity] = preferredCookie(existing: existingCookie, candidate: liveCookie)
            } else {
                mergedCookies[identity] = liveCookie
            }
        }

        return Array(mergedCookies.values)
    }

    static func clearPersistedSession() async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let identities = Set(load().map { CookieIdentity(cookie: $0.cookie) })

        UserDefaults.standard.removeObject(forKey: persistedCookiesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: primaryHostDefaultsKey)
        NotificationCenter.default.post(name: .lectraCanvasSessionUpdated, object: nil)

        guard !identities.isEmpty else { return }

        let existingCookies = await cookieStore.allCookies()
        for cookie in existingCookies where identities.contains(CookieIdentity(cookie: cookie)) {
            await delete(cookie, from: cookieStore)
        }
    }

    private static func delete(_ cookie: HTTPCookie, from cookieStore: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            cookieStore.delete(cookie) {
                continuation.resume()
            }
        }
    }

    private static func filter(cookies: [HTTPCookie], for primaryHost: String?) -> [HTTPCookie] {
        guard let primaryHost = primaryHost?.lowercased(), !primaryHost.isEmpty else {
            return cookies.filter { cookie in
                matchesLikelyCanvasDomain(cookie.domain)
            }
        }

        return cookies.filter { cookie in
            matches(cookieDomain: cookie.domain, primaryHost: primaryHost)
                || sharesRootDomain(cookieDomain: cookie.domain, primaryHost: primaryHost)
                || matchesLikelyCanvasDomain(cookie.domain)
        }
    }

    private static func liveCookies() async -> [StoredCookie] {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await cookieStore.allCookies()
        let primaryHost = UserDefaults.standard.string(forKey: primaryHostDefaultsKey)

        return filter(cookies: cookies, for: primaryHost).map { cookie in
            StoredCookie(cookie: cookie, usesSyntheticExpiry: false)
        }
    }

    private static func matches(cookieDomain: String, primaryHost: String) -> Bool {
        let normalizedDomain = cookieDomain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard !normalizedDomain.isEmpty else { return false }

        return primaryHost == normalizedDomain
            || primaryHost.hasSuffix(".\(normalizedDomain)")
            || normalizedDomain.hasSuffix(".\(primaryHost)")
    }

    private static func matchesLikelyCanvasDomain(_ cookieDomain: String) -> Bool {
        let normalizedDomain = cookieDomain.lowercased()
        return normalizedDomain.contains("canvas")
            || normalizedDomain.contains("instructure")
            || normalizedDomain.contains("canvaslms")
            || normalizedDomain.contains("bcourse")
            || normalizedDomain.contains("berkeley")
            || normalizedDomain.contains("okta")
            || normalizedDomain.contains("duosecurity")
            || normalizedDomain.contains("shibb")
            || normalizedDomain.contains("saml")
            || normalizedDomain.contains("login")
            || normalizedDomain.contains("auth")
            || normalizedDomain.contains("cas")
            || normalizedDomain.contains("idp")
    }

    private static func sharesRootDomain(cookieDomain: String, primaryHost: String) -> Bool {
        guard let cookieRoot = rootDomain(from: cookieDomain),
              let hostRoot = rootDomain(from: primaryHost) else {
            return false
        }

        return cookieRoot == hostRoot
    }

    private static func rootDomain(from domain: String) -> String? {
        let normalizedDomain = domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        let components = normalizedDomain.split(separator: ".")
        guard components.count >= 2 else { return nil }
        return components.suffix(2).joined(separator: ".")
    }

    private static func preferredCookie(existing: StoredCookie, candidate: StoredCookie) -> StoredCookie {
        let existingExpiry = existing.cookie.expiresDate
        let candidateExpiry = candidate.cookie.expiresDate

        if let candidateExpiry, let existingExpiry {
            return candidateExpiry >= existingExpiry ? candidate : existing
        }

        if candidateExpiry != nil {
            return candidate
        }

        if existing.usesSyntheticExpiry && candidateExpiry == nil {
            return existing
        }

        return candidate
    }

    private struct CookieIdentity: Hashable {
        let name: String
        let domain: String
        let path: String

        init(cookie: HTTPCookie) {
            self.name = cookie.name
            self.domain = cookie.domain
            self.path = cookie.path
        }
    }
}

extension Notification.Name {
    static let lectraCanvasSessionUpdated = Notification.Name("lectraCanvasSessionUpdated")
}
