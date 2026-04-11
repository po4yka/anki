import Foundation
import Security

public enum KeychainHelper {
    private static let syncService = "com.ankitects.anki.sync"
    private static let atlasService = "com.ankitects.anki.atlas"
    private static let remoteService = "com.ankitects.anki.remote"
    private static let hkeyAccount = "hkey"
    private static let endpointAccount = "endpoint"
    private static let embeddingApiKeyAccount = "embedding_api_key"
    private static let postgresUrlAccount = "postgres_url"
    private static let remoteAuthSessionAccount = "auth_session"

    // MARK: - Sync Auth

    public static func saveAuth(_ auth: Anki_Sync_SyncAuth) {
        saveString(auth.hkey, account: hkeyAccount, service: syncService)
        if auth.hasEndpoint {
            saveString(auth.endpoint, account: endpointAccount, service: syncService)
        } else {
            delete(account: endpointAccount, service: syncService)
        }
    }

    public static func loadAuth() -> Anki_Sync_SyncAuth? {
        guard let hkey = loadString(account: hkeyAccount, service: syncService), !hkey.isEmpty else {
            return nil
        }
        var auth = Anki_Sync_SyncAuth()
        auth.hkey = hkey
        if let endpoint = loadString(account: endpointAccount, service: syncService) {
            auth.endpoint = endpoint
        }
        return auth
    }

    public static func deleteAuth() {
        delete(account: hkeyAccount, service: syncService)
        delete(account: endpointAccount, service: syncService)
    }

    // MARK: - Atlas Secrets

    public static func saveAtlasApiKey(_ key: String) {
        if key.isEmpty {
            delete(account: embeddingApiKeyAccount, service: atlasService)
        } else {
            saveString(key, account: embeddingApiKeyAccount, service: atlasService)
        }
    }

    public static func loadAtlasApiKey() -> String? {
        loadString(account: embeddingApiKeyAccount, service: atlasService)
    }

    public static func deleteAtlasApiKey() {
        delete(account: embeddingApiKeyAccount, service: atlasService)
    }

    public static func saveAtlasPostgresUrl(_ url: String) {
        if url.isEmpty {
            delete(account: postgresUrlAccount, service: atlasService)
        } else {
            saveString(url, account: postgresUrlAccount, service: atlasService)
        }
    }

    public static func loadAtlasPostgresUrl() -> String? {
        loadString(account: postgresUrlAccount, service: atlasService)
    }

    public static func deleteAtlasPostgresUrl() {
        delete(account: postgresUrlAccount, service: atlasService)
    }

    // MARK: - Remote Auth Session

    public static func saveRemoteAuthSessionJSON(_ json: String) {
        if json.isEmpty {
            delete(account: remoteAuthSessionAccount, service: remoteService)
        } else {
            saveString(json, account: remoteAuthSessionAccount, service: remoteService)
        }
    }

    public static func loadRemoteAuthSessionJSON() -> String? {
        loadString(account: remoteAuthSessionAccount, service: remoteService)
    }

    public static func deleteRemoteAuthSession() {
        delete(account: remoteAuthSessionAccount, service: remoteService)
    }

    // MARK: - Private Helpers

    private static func saveString(_ value: String, account: String, service: String) {
        delete(account: account, service: service)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func loadString(account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
