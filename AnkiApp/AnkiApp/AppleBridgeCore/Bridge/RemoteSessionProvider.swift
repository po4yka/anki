import Foundation
import SwiftProtobuf

public protocol RemoteSessionProviding: Sendable {
    func endpoint() async throws -> BackendEndpoint
    func authorizedAccessToken() async throws -> String
    func ensureBackendSession() async throws -> String
    func invalidateAuth() async
    func invalidateBackendSession() async
}

public actor RemoteSessionProvider: RemoteSessionProviding {
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

    private var storedEndpoint: BackendEndpoint?
    private var authSession: RemoteAuthSession?
    private var backendSessionID: String?

    public init(
        session: URLSession = .shared,
        preferredLanguages: [String] = Locale.preferredLanguages.isEmpty ? ["en"] : Locale.preferredLanguages
    ) {
        self.session = session
        self.preferredLanguages = preferredLanguages
        storedEndpoint = Self.loadEndpoint()
        authSession = Self.loadAuthSession()
    }

    public func endpoint() async throws -> BackendEndpoint {
        guard let storedEndpoint else {
            throw AnkiError.message("Configure a remote backend endpoint first.")
        }
        return storedEndpoint
    }

    public func updateEndpoint(_ endpoint: BackendEndpoint) async {
        storedEndpoint = endpoint
        Self.saveEndpoint(endpoint)
        backendSessionID = nil
    }

    public func currentAuthSession() async -> RemoteAuthSession? {
        authSession
    }

    public func currentCapabilities() async -> BackendCapabilities? {
        authSession?.capabilities
    }

    public func issuePairingCode(deviceName: String? = nil) async throws -> PairingCodeResponse {
        let endpoint = try await endpoint()
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("api/auth/pair/create"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        let initResponse = try JSONDecoder().decode(BackendSessionInitResponse.self, from: data)
        backendSessionID = initResponse.backendSessionID
        return initResponse.backendSessionID
    }

    public func invalidateAuth() async {
        clearAuthState()
    }

    public func invalidateBackendSession() async {
        backendSessionID = nil
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
        KeychainHelper.saveRemoteAuthSessionJSON(json)
    }

    private func clearAuthState() {
        authSession = nil
        backendSessionID = nil
        KeychainHelper.deleteRemoteAuthSession()
    }

    private static func saveEndpoint(_ endpoint: BackendEndpoint) {
        guard let data = try? endpointEncoder.encode(endpoint) else { return }
        UserDefaults.standard.set(data, forKey: endpointDefaultsKey)
    }

    private static func loadEndpoint() -> BackendEndpoint? {
        guard let data = UserDefaults.standard.data(forKey: endpointDefaultsKey) else {
            return nil
        }
        return try? endpointDecoder.decode(BackendEndpoint.self, from: data)
    }

    private static func loadAuthSession() -> RemoteAuthSession? {
        guard let json = KeychainHelper.loadRemoteAuthSessionJSON(),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? authDecoder.decode(RemoteAuthSession.self, from: data)
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
