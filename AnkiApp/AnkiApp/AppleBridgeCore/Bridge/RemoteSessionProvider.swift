import Foundation
import SwiftProtobuf

// swiftlint:disable file_length type_body_length
public struct RemoteSessionPersistence: Sendable {
    public var saveEndpoint: @Sendable (BackendEndpoint) -> Void
    public var loadEndpoint: @Sendable () -> BackendEndpoint?
    public var saveAuthSessionJSON: @Sendable (String) -> Void
    public var loadAuthSessionJSON: @Sendable () -> String?
    public var deleteAuthSession: @Sendable () -> Void
    public var saveRemoteCollectionJSON: @Sendable (String) -> Void
    public var loadRemoteCollectionJSON: @Sendable () -> String?
    public var deleteRemoteCollection: @Sendable () -> Void
    public var saveCloudPairingKey: @Sendable (String) -> Void
    public var loadCloudPairingKey: @Sendable () -> String?
    public var deleteCloudPairingKey: @Sendable () -> Void

    public init(
        saveEndpoint: @escaping @Sendable (BackendEndpoint) -> Void,
        loadEndpoint: @escaping @Sendable () -> BackendEndpoint?,
        saveAuthSessionJSON: @escaping @Sendable (String) -> Void,
        loadAuthSessionJSON: @escaping @Sendable () -> String?,
        deleteAuthSession: @escaping @Sendable () -> Void,
        saveRemoteCollectionJSON: @escaping @Sendable (String) -> Void,
        loadRemoteCollectionJSON: @escaping @Sendable () -> String?,
        deleteRemoteCollection: @escaping @Sendable () -> Void,
        saveCloudPairingKey: @escaping @Sendable (String) -> Void,
        loadCloudPairingKey: @escaping @Sendable () -> String?,
        deleteCloudPairingKey: @escaping @Sendable () -> Void
    ) {
        self.saveEndpoint = saveEndpoint
        self.loadEndpoint = loadEndpoint
        self.saveAuthSessionJSON = saveAuthSessionJSON
        self.loadAuthSessionJSON = loadAuthSessionJSON
        self.deleteAuthSession = deleteAuthSession
        self.saveRemoteCollectionJSON = saveRemoteCollectionJSON
        self.loadRemoteCollectionJSON = loadRemoteCollectionJSON
        self.deleteRemoteCollection = deleteRemoteCollection
        self.saveCloudPairingKey = saveCloudPairingKey
        self.loadCloudPairingKey = loadCloudPairingKey
        self.deleteCloudPairingKey = deleteCloudPairingKey
    }

    public static let live = RemoteSessionPersistence(
        saveEndpoint: { endpoint in
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(endpoint) else { return }
            UserDefaults.standard.set(data, forKey: "remoteBackendEndpoint")
        },
        loadEndpoint: {
            let decoder = JSONDecoder()
            guard let data = UserDefaults.standard.data(forKey: "remoteBackendEndpoint") else {
                return nil
            }
            return try? decoder.decode(BackendEndpoint.self, from: data)
        },
        saveAuthSessionJSON: { json in
            KeychainHelper.saveRemoteAuthSessionJSON(json)
        },
        loadAuthSessionJSON: {
            KeychainHelper.loadRemoteAuthSessionJSON()
        },
        deleteAuthSession: {
            KeychainHelper.deleteRemoteAuthSession()
        },
        saveRemoteCollectionJSON: { json in
            UserDefaults.standard.set(json, forKey: "remoteBackendCollectionState")
        },
        loadRemoteCollectionJSON: {
            UserDefaults.standard.string(forKey: "remoteBackendCollectionState")
        },
        deleteRemoteCollection: {
            UserDefaults.standard.removeObject(forKey: "remoteBackendCollectionState")
        },
        saveCloudPairingKey: { key in
            KeychainHelper.saveRemoteCloudPairingKey(key)
        },
        loadCloudPairingKey: {
            KeychainHelper.loadRemoteCloudPairingKey()
        },
        deleteCloudPairingKey: {
            KeychainHelper.deleteRemoteCloudPairingKey()
        }
    )
}

public protocol RemoteSessionProviding: Sendable {
    func endpoint() async throws -> BackendEndpoint
    func authorizedAccessToken() async throws -> String
    func ensureBackendSession() async throws -> String
    func invalidateAuth() async
    func invalidateBackendSession() async
    func recoverBackendSessionAfterNotFound() async throws
}

public protocol RemoteSessionManaging: RemoteSessionProviding {
    func updateEndpoint(_ endpoint: BackendEndpoint) async
    func updateCloudPairingKey(_ key: String?) async
    func currentCloudPairingKey() async -> String?
    func currentAuthSession() async -> RemoteAuthSession?
    func currentCapabilities() async -> BackendCapabilities?
    func currentRemoteCollectionState() async -> RemoteCollectionState?
    func issuePairingCode(deviceName: String?) async throws -> PairingCodeResponse
    func exchangePairingCode(_ code: String) async throws -> RemoteAuthSession
    func refreshCapabilities() async throws -> BackendCapabilities
    func recordRemoteCollectionState(path: String, mediaFolder: String, mediaDb: String) async
    func clearRemoteCollectionState() async
    func signOut() async
}

public actor RemoteSessionProvider: RemoteSessionManaging {
    private static let endpointDefaultsKey = "remoteBackendEndpoint"
    private static let endpointEncoder = JSONEncoder()
    private static let endpointDecoder = JSONDecoder()
    private static let authEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let authDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let session: URLSession
    private let preferredLanguages: [String]
    private let persistence: RemoteSessionPersistence

    private var storedEndpoint: BackendEndpoint?
    private var authSession: RemoteAuthSession?
    private var backendSessionID: String?
    private var remoteCollectionState: RemoteCollectionState?
    private var cloudPairingKey: String?

    public init(
        session: URLSession = .shared,
        preferredLanguages: [String] = Locale.preferredLanguages.isEmpty ? ["en"] : Locale.preferredLanguages,
        persistence: RemoteSessionPersistence = .live
    ) {
        self.session = session
        self.preferredLanguages = preferredLanguages
        self.persistence = persistence
        storedEndpoint = persistence.loadEndpoint()
        authSession = Self.loadAuthSession(using: persistence)
        remoteCollectionState = Self.loadRemoteCollectionState(using: persistence)
        cloudPairingKey = persistence.loadCloudPairingKey()
    }

    public func endpoint() async throws -> BackendEndpoint {
        guard let storedEndpoint else {
            throw AnkiError.message("Configure a remote backend endpoint first.")
        }
        return storedEndpoint
    }

    public func updateEndpoint(_ endpoint: BackendEndpoint) async {
        storedEndpoint = endpoint
        persistence.saveEndpoint(endpoint)
        backendSessionID = nil
    }

    public func updateCloudPairingKey(_ key: String?) async {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed?.isEmpty == false ? trimmed : nil
        cloudPairingKey = normalized
        if let normalized {
            persistence.saveCloudPairingKey(normalized)
        } else {
            persistence.deleteCloudPairingKey()
        }
    }

    public func currentCloudPairingKey() async -> String? {
        cloudPairingKey
    }

    public func currentAuthSession() async -> RemoteAuthSession? {
        authSession
    }

    public func currentCapabilities() async -> BackendCapabilities? {
        authSession?.capabilities
    }

    public func currentRemoteCollectionState() async -> RemoteCollectionState? {
        remoteCollectionState
    }

    public func issuePairingCode(deviceName: String? = nil) async throws -> PairingCodeResponse {
        let endpoint = try await endpoint()
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("api/auth/pair/create"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if endpoint.deploymentKind == .cloud {
            guard let cloudPairingKey, !cloudPairingKey.isEmpty else {
                throw AnkiError.message("Enter the cloud pairing secret before requesting a pairing code.")
            }
            request.setValue("Bearer \(cloudPairingKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(PairingCreateRequest(deviceName: deviceName))
        let (data, response) = try await session.data(for: request)
        try validateJSON(response: response, data: data)
        return try Self.authDecoder.decode(PairingCodeResponse.self, from: data)
    }

    public func exchangePairingCode(_ code: String) async throws -> RemoteAuthSession {
        let endpoint = try await endpoint()
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("api/auth/pair/exchange"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PairingExchangeRequest(pairingCode: code))
        let (data, response) = try await session.data(for: request)
        try validateJSON(response: response, data: data)
        let authSession = try Self.authDecoder.decode(RemoteAuthSession.self, from: data)
        self.authSession = authSession
        backendSessionID = nil
        persistAuthSession(authSession)
        return authSession
    }

    public func refreshCapabilities() async throws -> BackendCapabilities {
        let endpoint = try await endpoint()
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("api/capabilities"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(try await authorizedAccessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try validateJSON(response: response, data: data)
        let capabilities = try Self.authDecoder.decode(BackendCapabilities.self, from: data)
        if var current = authSession {
            current.capabilities = capabilities
            authSession = current
            persistAuthSession(current)
        }
        return capabilities
    }

    public func signOut() async {
        guard let endpoint = storedEndpoint, let authSession else {
            clearAuthState()
            return
        }

        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("api/auth/logout"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(RefreshRequest(refreshToken: authSession.refreshToken))
        _ = try? await session.data(for: request)
        clearAuthState()
    }

    public func authorizedAccessToken() async throws -> String {
        guard let authSession else {
            throw AnkiError.message("Pair with a remote backend before using the iOS transport.")
        }
        if authSession.expiresAt.timeIntervalSinceNow > 60 {
            return authSession.accessToken
        }
        return try await refreshAuthSession().accessToken
    }

    public func ensureBackendSession() async throws -> String {
        if let backendSessionID {
            return backendSessionID
        }

        let initResponse = try await performBackendInit()
        backendSessionID = initResponse.backendSessionID
        return initResponse.backendSessionID
    }

    public func recoverBackendSessionAfterNotFound() async throws {
        backendSessionID = nil
        let initResponse = try await performBackendInit()
        backendSessionID = initResponse.backendSessionID
        if let remoteCollectionState {
            try await replayRemoteCollectionOpen(remoteCollectionState)
        }
    }

    public func recordRemoteCollectionState(
        path: String,
        mediaFolder: String,
        mediaDb: String
    ) async {
        let state = RemoteCollectionState(path: path, mediaFolder: mediaFolder, mediaDb: mediaDb)
        remoteCollectionState = state
        persistRemoteCollectionState(state)
    }

    public func clearRemoteCollectionState() async {
        remoteCollectionState = nil
        persistence.deleteRemoteCollection()
    }

    public func invalidateAuth() async {
        clearAuthState()
    }

    public func invalidateBackendSession() async {
        backendSessionID = nil
    }

    private func performBackendInit() async throws -> BackendSessionInitResponse {
        let endpoint = try await endpoint()
        let accessToken = try await authorizedAccessToken()
        var initMsg = Anki_Backend_BackendInit()
        initMsg.preferredLangs = preferredLanguages
        initMsg.server = true

        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("api/anki/backend/init"))
        request.httpMethod = "POST"
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try initMsg.serializedData()

        let (data, response) = try await session.data(for: request)
        try validateJSON(response: response, data: data)
        return try JSONDecoder().decode(BackendSessionInitResponse.self, from: data)
    }

    private func refreshAuthSession() async throws -> RemoteAuthSession {
        guard let endpoint = storedEndpoint, let authSession else {
            throw AnkiError.message("Pair with a remote backend before using the iOS transport.")
        }
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("api/auth/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RefreshRequest(refreshToken: authSession.refreshToken))

        let (data, response) = try await session.data(for: request)
        do {
            try validateJSON(response: response, data: data)
            let refreshed = try Self.authDecoder.decode(RemoteAuthSession.self, from: data)
            self.authSession = refreshed
            backendSessionID = nil
            persistAuthSession(refreshed)
            return refreshed
        } catch {
            clearAuthState()
            throw error
        }
    }

    private func validateJSON(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnkiError.message("The remote backend did not return a valid HTTP response.")
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw decodeServerError(data: data, statusCode: httpResponse.statusCode)
        }
    }

    private func decodeServerError(data: Data, statusCode: Int) -> AnkiError {
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = payload["error"] as? String {
            return .message(error)
        }
        return .message("Remote backend request failed with HTTP \(statusCode).")
    }

    private func persistAuthSession(_ session: RemoteAuthSession) {
        guard let data = try? Self.authEncoder.encode(session),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        persistence.saveAuthSessionJSON(json)
    }

    private func persistRemoteCollectionState(_ state: RemoteCollectionState) {
        guard let data = try? Self.authEncoder.encode(state),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        persistence.saveRemoteCollectionJSON(json)
    }

    private func clearAuthState() {
        authSession = nil
        backendSessionID = nil
        persistence.deleteAuthSession()
    }

    private static func loadAuthSession(using persistence: RemoteSessionPersistence) -> RemoteAuthSession? {
        guard let json = persistence.loadAuthSessionJSON(),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? authDecoder.decode(RemoteAuthSession.self, from: data)
    }

    private static func loadRemoteCollectionState(
        using persistence: RemoteSessionPersistence
    ) -> RemoteCollectionState? {
        guard let json = persistence.loadRemoteCollectionJSON(),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? authDecoder.decode(RemoteCollectionState.self, from: data)
    }

    private func replayRemoteCollectionOpen(_ state: RemoteCollectionState) async throws {
        let endpoint = try await endpoint()
        let accessToken = try await authorizedAccessToken()
        let backendSessionID = try await ensureBackendSession()
        var request = URLRequest(
            url: endpoint.baseURL
                .appendingPathComponent("api")
                .appendingPathComponent("anki")
                .appendingPathComponent("rpc")
                .appendingPathComponent(String(ServiceIndex.collection))
                .appendingPathComponent(String(CollectionMethod.openCollection))
        )
        request.httpMethod = "POST"
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(backendSessionID, forHTTPHeaderField: "X-Anki-Backend-Session")

        var openRequest = Anki_Collection_OpenCollectionRequest()
        openRequest.collectionPath = state.path
        openRequest.mediaFolderPath = state.mediaFolder
        openRequest.mediaDbPath = state.mediaDb
        request.httpBody = try openRequest.serializedData()

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnkiError.message("The remote backend did not return a valid HTTP response.")
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw decodeServerError(data: data, statusCode: httpResponse.statusCode)
        }
        if httpResponse.value(forHTTPHeaderField: "X-Anki-Error") == "1" {
            let backendError = try Anki_Backend_BackendError(serializedBytes: data)
            throw AnkiError.backend(backendError)
        }
    }
}

private struct BackendSessionInitResponse: Decodable {
    let backendSessionID: String

    enum CodingKeys: String, CodingKey {
        case backendSessionID = "backend_session_id"
    }
}

private struct PairingCreateRequest: Encodable {
    let deviceName: String?

    enum CodingKeys: String, CodingKey {
        case deviceName = "device_name"
    }
}

private struct PairingExchangeRequest: Encodable {
    let pairingCode: String

    enum CodingKeys: String, CodingKey {
        case pairingCode = "pairing_code"
    }
}

private struct RefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}
// swiftlint:enable file_length type_body_length
