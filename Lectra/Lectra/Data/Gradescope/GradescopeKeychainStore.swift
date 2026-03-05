import Foundation
import Security

final class GradescopeKeychainStore {
    private let service = "com.canvascope.lectra.gradescope"
    private let account = "session_snapshot"

    func save(snapshot: GSSessionSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertQuery = query
            insertQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: "GradescopeKeychainStore", code: Int(addStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to save Gradescope session."])
            }
            return
        }

        guard status == errSecSuccess else {
            throw NSError(domain: "GradescopeKeychainStore", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to update Gradescope session."])
        }
    }

    func load() -> GSSessionSnapshot? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let snapshot = try? JSONDecoder().decode(GSSessionSnapshot.self, from: data) else {
            return nil
        }

        return snapshot
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
