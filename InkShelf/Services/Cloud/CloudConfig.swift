import Foundation
import Security

enum CloudConfig {
    static let apiBaseKey = "inkshelf.cloud.apiBase"
    static let syncEnabledKey = "inkshelf.cloud.syncEnabled"
    static let lastSyncKey = "inkshelf.cloud.lastSync"
    static let syncTxtKey = "inkshelf.cloud.syncLocalTxt"

    /// Default points at local wrangler; override in Settings after deploy.
    static var apiBaseURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: apiBaseKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored, !stored.isEmpty { return stored }
            return "http://127.0.0.1:8787"
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: apiBaseKey)
        }
    }

    static var syncEnabled: Bool {
        get { UserDefaults.standard.object(forKey: syncEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: syncEnabledKey) }
    }

    static var syncLocalTxt: Bool {
        get { UserDefaults.standard.bool(forKey: syncTxtKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncTxtKey) }
    }

    static var lastSyncAt: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncKey) }
    }
}

enum CloudAuthStore {
    private static let service = "com.inkshelf.app.cloud"
    private static let tokenAccount = "jwt"
    private static let emailAccount = "email"
    private static let userIdAccount = "userId"

    static var token: String? {
        get { read(account: tokenAccount) }
        set { write(account: tokenAccount, value: newValue) }
    }

    static var email: String? {
        get { read(account: emailAccount) }
        set { write(account: emailAccount, value: newValue) }
    }

    static var userId: String? {
        get { read(account: userIdAccount) }
        set { write(account: userIdAccount, value: newValue) }
    }

    static var isLoggedIn: Bool { !(token ?? "").isEmpty }

    static func clear() {
        token = nil
        email = nil
        userId = nil
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(account: String, value: String?) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }
}
