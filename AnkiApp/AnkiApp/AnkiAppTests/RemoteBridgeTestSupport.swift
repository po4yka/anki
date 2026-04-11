@testable import AppleBridgeCore
import Foundation
import Testing

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

    func invalidatedBackendSessionCount() -> Int {
        backendSessionInvalidations
    }

    func ensureBackendSessionCallCount() -> Int {
        backendSessionCalls
    }
}

func makeRemoteBridgeURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RemoteBridgeURLProtocol.self]
    return URLSession(configuration: configuration)
}

func clearRemoteBridgeArtifacts() {
    UserDefaults.standard.removeObject(forKey: "remoteBackendEndpoint")
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
