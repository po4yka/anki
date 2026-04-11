@testable import AppleBridgeCore
import Foundation
import SwiftProtobuf
import Testing

// swiftlint:disable file_length
enum RemoteBridgeTestError: Error {
    case unexpectedRequest(String)
}

final class RemoteBridgeURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var recordedRequests: [URLRequest] = []

    static func install(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        self.handler = handler
        recordedRequests = []
        lock.unlock()
    }

    static func requests(matchingPath path: String) -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests.filter { $0.url?.path == path }
    }

    static func reset() {
        lock.lock()
        handler = nil
        recordedRequests = []
        lock.unlock()
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.recordedRequests.append(request)
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: RemoteBridgeTestError.unexpectedRequest("No handler installed"))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

actor StubRemoteSessionProvider: RemoteSessionProviding {
    private let endpointValue: BackendEndpoint
    private let accessTokenValue: String
    private var backendSessions: [String]
    private var currentBackendSession: String?
    private var backendSessionCalls = 0
    private var backendSessionInvalidations = 0
    private var recoveries = 0

    init(endpoint: BackendEndpoint, accessToken: String, backendSessions: [String]) {
        self.endpointValue = endpoint
        accessTokenValue = accessToken
        self.backendSessions = backendSessions
    }

    func endpoint() async throws -> BackendEndpoint {
        endpointValue
    }

    func authorizedAccessToken() async throws -> String {
        accessTokenValue
    }

    func ensureBackendSession() async throws -> String {
        if let currentBackendSession {
            return currentBackendSession
        }
        guard !backendSessions.isEmpty else {
            throw AnkiError.message("No backend sessions remaining for test provider.")
        }
        backendSessionCalls += 1
        let next = backendSessions.removeFirst()
        currentBackendSession = next
        return next
    }

    func invalidateAuth() async {}

    func invalidateBackendSession() async {
        backendSessionInvalidations += 1
        currentBackendSession = nil
    }

    func recoverBackendSessionAfterNotFound() async throws {
        recoveries += 1
        backendSessionInvalidations += 1
        currentBackendSession = nil
        _ = try await ensureBackendSession()
    }

    func invalidatedBackendSessionCount() -> Int {
        backendSessionInvalidations
    }

    func ensureBackendSessionCallCount() -> Int {
        backendSessionCalls
    }

    func recoveryCount() -> Int {
        recoveries
    }
}

actor RecordingBackendTransport: BackendCommandTransport {
    struct Invocation: Sendable {
        let service: UInt32
        let method: UInt32
        let payload: Data
    }

    private var invocations: [Invocation] = []
    private var queuedResponses: [BackendCommandResponse] = []

    func enqueueResponse<Message: SwiftProtobuf.Message>(
        _ message: Message,
        isBackendError: Bool = false
    ) throws {
        queuedResponses.append(
            BackendCommandResponse(
                payload: try message.serializedData(),
                isBackendError: isBackendError
            )
        )
    }

    func send(service: UInt32, method: UInt32, payload: Data) async throws -> BackendCommandResponse {
        invocations.append(Invocation(service: service, method: method, payload: payload))
        guard !queuedResponses.isEmpty else {
            throw AnkiError.message("No queued backend response for test transport.")
        }
        return queuedResponses.removeFirst()
    }

    func allInvocations() -> [Invocation] {
        invocations
    }
}

actor StubRemoteSessionManager: RemoteSessionManaging {
    var endpointValue: BackendEndpoint
    var accessTokenValue: String
    var currentSessionValue: RemoteAuthSession?
    var currentCapabilitiesValue: BackendCapabilities?
    var issuedPairingCodeValue: PairingCodeResponse
    var exchangedSessionValue: RemoteAuthSession
    var refreshedCapabilitiesValue: BackendCapabilities
    var currentRemoteCollectionStateValue: RemoteCollectionState?
    private(set) var endpointUpdates: [BackendEndpoint] = []
    private(set) var signOutCallCount = 0

    init(
        endpoint: BackendEndpoint,
        accessToken: String = "access-token",
        currentSession: RemoteAuthSession? = nil,
        currentCapabilities: BackendCapabilities? = nil,
        issuedPairingCode: PairingCodeResponse? = nil,
        exchangedSession: RemoteAuthSession? = nil,
        refreshedCapabilities: BackendCapabilities? = nil
    ) {
        endpointValue = endpoint
        accessTokenValue = accessToken
        currentSessionValue = currentSession
        currentCapabilitiesValue = currentCapabilities

        let defaultCapabilities = refreshedCapabilities
            ?? currentCapabilities
            ?? BackendCapabilities(
                supportsRemoteAnki: true,
                supportsAtlas: true,
                deploymentKind: endpoint.deploymentKind,
                executionMode: .remote
            )
        let defaultSession = exchangedSession
            ?? currentSession
            ?? RemoteAuthSession(
                accessToken: accessToken,
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSinceNow: 3600),
                accountID: "acct-1",
                accountDisplayName: "Test Account",
                capabilities: defaultCapabilities
            )

        issuedPairingCodeValue = issuedPairingCode
            ?? PairingCodeResponse(
                pairingCode: "PAIR1234",
                pairingURL: URL(string: "ankiapp://pair?code=PAIR1234"),
                expiresAt: Date(timeIntervalSinceNow: 300)
            )
        exchangedSessionValue = defaultSession
        refreshedCapabilitiesValue = defaultCapabilities
    }

    func endpoint() async throws -> BackendEndpoint {
        endpointValue
    }

    func authorizedAccessToken() async throws -> String {
        accessTokenValue
    }

    func ensureBackendSession() async throws -> String {
        "backend-session"
    }

    func invalidateAuth() async {
        currentSessionValue = nil
    }

    func invalidateBackendSession() async {}

    func recoverBackendSessionAfterNotFound() async throws {}

    func updateEndpoint(_ endpoint: BackendEndpoint) async {
        endpointValue = endpoint
        endpointUpdates.append(endpoint)
    }

    func currentAuthSession() async -> RemoteAuthSession? {
        currentSessionValue
    }

    func currentCapabilities() async -> BackendCapabilities? {
        currentCapabilitiesValue
    }

    func currentRemoteCollectionState() async -> RemoteCollectionState? {
        currentRemoteCollectionStateValue
    }

    func issuePairingCode(deviceName: String?) async throws -> PairingCodeResponse {
        issuedPairingCodeValue
    }

    func exchangePairingCode(_ code: String) async throws -> RemoteAuthSession {
        currentSessionValue = exchangedSessionValue
        currentCapabilitiesValue = exchangedSessionValue.capabilities
        return exchangedSessionValue
    }

    func refreshCapabilities() async throws -> BackendCapabilities {
        currentCapabilitiesValue = refreshedCapabilitiesValue
        return refreshedCapabilitiesValue
    }

    func recordRemoteCollectionState(path: String, mediaFolder: String, mediaDb: String) async {
        currentRemoteCollectionStateValue = RemoteCollectionState(
            path: path,
            mediaFolder: mediaFolder,
            mediaDb: mediaDb
        )
    }

    func clearRemoteCollectionState() async {
        currentRemoteCollectionStateValue = nil
    }

    func signOut() async {
        signOutCallCount += 1
        currentSessionValue = nil
        currentCapabilitiesValue = nil
    }
}

actor StubEndpointDiscoverer: BackendEndpointDiscovering {
    var verificationError: Error?
    var discoveredEndpoint: BackendEndpoint?
    private(set) var verifiedEndpoints: [BackendEndpoint] = []

    func setDiscoveredEndpoint(_ endpoint: BackendEndpoint?) {
        discoveredEndpoint = endpoint
    }

    func setVerificationError(_ error: Error?) {
        verificationError = error
    }

    func verify(endpoint: BackendEndpoint) async throws {
        verifiedEndpoints.append(endpoint)
        if let verificationError {
            throw verificationError
        }
    }

    func discoverPreferredEndpoint(for deploymentKind: BackendDeploymentKind) async throws -> BackendEndpoint? {
        discoveredEndpoint
    }

    func allVerifiedEndpoints() -> [BackendEndpoint] {
        verifiedEndpoints
    }
}

func makeRemoteBridgeURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RemoteBridgeURLProtocol.self]
    return URLSession(configuration: configuration)
}

final class RemoteSessionPersistenceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var endpoint: BackendEndpoint?
    private var authSessionJSON: String?
    private var remoteCollectionJSON: String?

    func saveEndpoint(_ endpoint: BackendEndpoint) {
        lock.lock()
        self.endpoint = endpoint
        lock.unlock()
    }

    func loadEndpoint() -> BackendEndpoint? {
        lock.lock()
        defer { lock.unlock() }
        return endpoint
    }

    func saveAuthSessionJSON(_ json: String) {
        lock.lock()
        authSessionJSON = json
        lock.unlock()
    }

    func loadAuthSessionJSON() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return authSessionJSON
    }

    func deleteAuthSession() {
        lock.lock()
        authSessionJSON = nil
        lock.unlock()
    }

    func saveRemoteCollectionJSON(_ json: String) {
        lock.lock()
        remoteCollectionJSON = json
        lock.unlock()
    }

    func loadRemoteCollectionJSON() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return remoteCollectionJSON
    }

    func deleteRemoteCollection() {
        lock.lock()
        remoteCollectionJSON = nil
        lock.unlock()
    }
}

func makeInMemoryRemoteSessionPersistence() -> RemoteSessionPersistence {
    let box = RemoteSessionPersistenceBox()
    return RemoteSessionPersistence(
        saveEndpoint: { endpoint in box.saveEndpoint(endpoint) },
        loadEndpoint: { box.loadEndpoint() },
        saveAuthSessionJSON: { json in box.saveAuthSessionJSON(json) },
        loadAuthSessionJSON: { box.loadAuthSessionJSON() },
        deleteAuthSession: { box.deleteAuthSession() },
        saveRemoteCollectionJSON: { json in box.saveRemoteCollectionJSON(json) },
        loadRemoteCollectionJSON: { box.loadRemoteCollectionJSON() },
        deleteRemoteCollection: { box.deleteRemoteCollection() }
    )
}

func makeIsolatedUserDefaults(suiteName: String = UUID().uuidString) -> UserDefaults {
    let suiteName = "AnkiAppTests.\(suiteName)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

func clearRemoteBridgeArtifacts() {
    UserDefaults.standard.removeObject(forKey: "remoteBackendEndpoint")
    UserDefaults.standard.removeObject(forKey: "remoteBackendCollectionState")
    UserDefaults.standard.removeObject(forKey: "remoteBackendExecutionPolicy")
    KeychainHelper.deleteRemoteAuthSession()
}

func requestBodyData(from request: URLRequest) -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return Data()
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let readCount = stream.read(buffer, maxLength: 1024)
        guard readCount > 0 else {
            break
        }
        data.append(buffer, count: readCount)
    }

    return data
}

func jsonResponse(for request: URLRequest, body: Any, status: Int = 200) throws -> (HTTPURLResponse, Data) {
    let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    let response = try #require(
        HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"),
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
    )
    return (response, data)
}

func protobufResponse(
    for request: URLRequest,
    status: Int = 200,
    body: Data,
    isBackendError: Bool
) throws -> (HTTPURLResponse, Data) {
    let response = try #require(
        HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"),
            statusCode: status,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "application/x-protobuf",
                "X-Anki-Error": isBackendError ? "1" : "0"
            ]
        )
    )
    return (response, body)
}

func capabilitiesPayload(
    supportsAtlas: Bool,
    deploymentKind: String = "companion",
    executionMode: String = "remote"
) -> [String: Any] {
    [
        "supports_remote_anki": true,
        "supports_atlas": supportsAtlas,
        "deployment_kind": deploymentKind,
        "execution_mode": executionMode
    ]
}

func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}
// swiftlint:enable file_length
