import Foundation
import Security

enum LegacyThirdPartyIntegrationData {
    static let plaintextCookieDefaultsKey = "LectraCanvasPersistedCookies"
    static let primaryHostDefaultsKey = "LectraCanvasPrimaryHost"
    static let linkedSubmissionDefaultsKey = "lectra_gradescope_links_v1"

    static func clearFromDevice() {
        let defaults = UserDefaults.standard
        [
            plaintextCookieDefaultsKey,
            primaryHostDefaultsKey,
            linkedSubmissionDefaultsKey,
        ].forEach { defaults.removeObject(forKey: $0) }

        deleteKeychainItem(service: "com.canvascope.lectra.canvas", account: "session_cookies")
        deleteKeychainItem(service: "com.canvascope.lectra.gradescope", account: "session_snapshot")
    }

    private static func deleteKeychainItem(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
