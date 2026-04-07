import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.ankitects.anki.sync"
    private static let hkeyAccount = "hkey"
    private static let endpointAccount = "endpoint"

    static func saveAuth(_ auth: Anki_Sync_SyncAuth) {
        saveString(auth.hkey, account: hkeyAccount)
        if auth.hasEndpoint {
            saveString(auth.endpoint, account: endpointAccount)
        } else {
            delete(account: endpointAccount)
        }
    }

    static func loadAuth() -> Anki_Sync_SyncAuth? {
        guard let hkey = loadString(account: hkeyAccount), !hkey.isEmpty else {
            return nil
        }
        var auth = Anki_Sync_SyncAuth()
        auth.hkey = hkey
        if let endpoint = loadString(account: endpointAccount) {
            auth.endpoint = endpoint
        }
        return auth
    }

    static func deleteAuth() {
        delete(account: hkeyAccount)
        delete(account: endpointAccount)
    }

    private static func saveString(_ value: String, account: String) {
        delete(account: account)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func loadString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
