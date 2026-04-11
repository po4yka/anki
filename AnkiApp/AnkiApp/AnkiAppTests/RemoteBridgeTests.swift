@testable import AppleBridgeCore
import Foundation
import SwiftProtobuf
import Testing

// swiftlint:disable type_body_length
@Suite(.serialized)
struct RemoteBridgeTests {
    @Test
    func sessionProviderPersistsExchangeAndCachesBackendSession() async throws {
        try await withRemoteSessionProvider(
            preferredLanguages: ["fr", "en"],
            deploymentKind: .companion
        ) { session, endpoint, provider, persistence in
            let exchangeExpiry = Date(timeIntervalSinceNow: 3600)
            RemoteBridgeURLProtocol.install { request in
                switch request.url?.path {
                case "/api/auth/pair/exchange":
                    return try jsonResponse(
                        for: request,
                        body: [
                            "access_token": "access-1",
                            "refresh_token": "refresh-1",
                            "expires_at": iso8601(exchangeExpiry),
                            "account_id": "acct-1",
                            "account_display_name": "Test Device",
                            "capabilities": capabilitiesPayload(supportsAtlas: true)
                        ]
                    )
                case "/api/anki/backend/init":
                    return try jsonResponse(for: request, body: ["backend_session_id": "backend-1"])
                default:
                    throw RemoteBridgeTestError.unexpectedRequest(request.url?.absoluteString ?? "<nil>")
                }
            }

            let authSession = try await provider.exchangePairingCode("PAIR1234")
            #expect(authSession.accessToken == "access-1")
            #expect(authSession.refreshToken == "refresh-1")
            #expect(authSession.accountID == "acct-1")
            #expect(authSession.capabilities.supportsAtlas)
            #expect(await provider.currentAuthSession()?.accessToken == "access-1")

            let restoredProvider = RemoteSessionProvider(
                session: session,
                preferredLanguages: ["fr", "en"],
                persistence: persistence
            )
            #expect(try await restoredProvider.endpoint() == BackendEndpoint(baseURL: endpoint, deploymentKind: .companion))
            #expect(await restoredProvider.currentAuthSession()?.accessToken == "access-1")

            let backendSession = try await provider.ensureBackendSession()
            #expect(backendSession == "backend-1")
            #expect(try await provider.ensureBackendSession() == "backend-1")

            let initRequest = try #require(RemoteBridgeURLProtocol.requests(matchingPath: "/api/anki/backend/init").first)
            #expect(initRequest.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
            let initMessage = try Anki_Backend_BackendInit(serializedBytes: requestBodyData(from: initRequest))
            #expect(initMessage.preferredLangs == ["fr", "en"])
            #expect(initMessage.server)
        }
    }

    @Test
    // swiftlint:disable function_body_length
    func sessionProviderRefreshesExpiredTokensAndCapabilities() async throws {
        try await withRemoteSessionProvider(
            preferredLanguages: ["en"],
            deploymentKind: .cloud
        ) { _, _, provider, _ in
            RemoteBridgeURLProtocol.install { request in
                switch request.url?.path {
                case "/api/auth/pair/exchange":
                    return try jsonResponse(
                        for: request,
                        body: [
                            "access_token": "expired-access",
                            "refresh_token": "refresh-1",
                            "expires_at": iso8601(Date(timeIntervalSinceNow: -10)),
                            "account_id": "acct-1",
                            "account_display_name": "Expired Session",
                            "capabilities": capabilitiesPayload(supportsAtlas: false, deploymentKind: "cloud")
                        ]
                    )
                case "/api/auth/refresh":
                    return try jsonResponse(
                        for: request,
                        body: [
                            "access_token": "fresh-access",
                            "refresh_token": "refresh-2",
                            "expires_at": iso8601(Date(timeIntervalSinceNow: 3600)),
                            "account_id": "acct-1",
                            "account_display_name": "Fresh Session",
                            "capabilities": capabilitiesPayload(supportsAtlas: false, deploymentKind: "cloud")
                        ]
                    )
                case "/api/capabilities":
                    return try jsonResponse(
                        for: request,
                        body: capabilitiesPayload(supportsAtlas: true, deploymentKind: "cloud")
                    )
                default:
                    throw RemoteBridgeTestError.unexpectedRequest(request.url?.absoluteString ?? "<nil>")
                }
            }

            _ = try await provider.exchangePairingCode("PAIR1234")
            #expect(try await provider.authorizedAccessToken() == "fresh-access")

            let capabilities = try await provider.refreshCapabilities()
            #expect(capabilities.supportsAtlas)
            #expect(capabilities.deploymentKind == .cloud)
            #expect(await provider.currentAuthSession()?.accessToken == "fresh-access")
            #expect(await provider.currentAuthSession()?.refreshToken == "refresh-2")

            let refreshRequest = try #require(RemoteBridgeURLProtocol.requests(matchingPath: "/api/auth/refresh").first)
            #expect(refreshRequest.httpMethod == "POST")
            let capabilitiesRequest = try #require(RemoteBridgeURLProtocol.requests(matchingPath: "/api/capabilities").first)
            #expect(capabilitiesRequest.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-access")
        }
    }
    // swiftlint:enable function_body_length

    @Test
    func sessionProviderUsesCloudPairingSecretForCloudPairCreate() async throws {
        try await withRemoteSessionProvider(
            preferredLanguages: ["en"],
            deploymentKind: .cloud
        ) { _, _, provider, persistence in
            RemoteBridgeURLProtocol.install { request in
                guard request.url?.path == "/api/auth/pair/create" else {
                    throw RemoteBridgeTestError.unexpectedRequest(request.url?.absoluteString ?? "<nil>")
                }
                return try jsonResponse(
                    for: request,
                    body: [
                        "pairing_code": "PAIR9999",
                        "pairing_url": "ankiapp://pair?code=PAIR9999",
                        "expires_at": iso8601(Date(timeIntervalSinceNow: 300))
                    ]
                )
            }

            await provider.updateCloudPairingKey("cloud-secret-1")
            let response = try await provider.issuePairingCode(deviceName: "iPhone")
            #expect(response.pairingCode == "PAIR9999")
            #expect(await provider.currentCloudPairingKey() == "cloud-secret-1")

            let request = try #require(RemoteBridgeURLProtocol.requests(matchingPath: "/api/auth/pair/create").first)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer cloud-secret-1")

            let restoredProvider = RemoteSessionProvider(
                session: makeRemoteBridgeURLSession(),
                preferredLanguages: ["en"],
                persistence: persistence
            )
            #expect(await restoredProvider.currentCloudPairingKey() == "cloud-secret-1")
        }
    }

    @Test
    func remoteTransportEncodesRpcRequestsAndDecodesResponses() async throws {
        RemoteBridgeURLProtocol.reset()
        defer { RemoteBridgeURLProtocol.reset() }

        let endpoint = try #require(URL(string: "http://remote.test/"))
        let session = makeRemoteBridgeURLSession()
        let sessionProvider = StubRemoteSessionProvider(
            endpoint: BackendEndpoint(baseURL: endpoint, deploymentKind: .companion),
            accessToken: "access-1",
            backendSessions: ["backend-1"]
        )
        let transport = RemoteHTTPCommandTransport(sessionProvider: sessionProvider, session: session)

        RemoteBridgeURLProtocol.install { request in
            guard request.url?.path == "/api/anki/rpc/7/9" else {
                throw RemoteBridgeTestError.unexpectedRequest(request.url?.absoluteString ?? "<nil>")
            }
            var response = Anki_Generic_String()
            response.val = "pong"
            return try protobufResponse(for: request, body: response.serializedData(), isBackendError: false)
        }

        var input = Anki_Generic_String()
        input.val = "ping"
        let output: Anki_Generic_String = try await transport.sendCommand(service: 7, method: 9, input: input)
        #expect(output.val == "pong")

        let rpcRequest = try #require(RemoteBridgeURLProtocol.requests(matchingPath: "/api/anki/rpc/7/9").first)
        #expect(rpcRequest.httpMethod == "POST")
        #expect(rpcRequest.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(rpcRequest.value(forHTTPHeaderField: "X-Anki-Backend-Session") == "backend-1")
        let sentMessage = try Anki_Generic_String(serializedBytes: requestBodyData(from: rpcRequest))
        #expect(sentMessage.val == "ping")
    }

    @Test
    func remoteTransportRetriesExpiredBackendSessionsAndDecodesBackendErrors() async throws {
        RemoteBridgeURLProtocol.reset()
        defer { RemoteBridgeURLProtocol.reset() }

        let endpoint = try #require(URL(string: "http://remote.test/"))
        let session = makeRemoteBridgeURLSession()
        let sessionProvider = StubRemoteSessionProvider(
            endpoint: BackendEndpoint(baseURL: endpoint, deploymentKind: .companion),
            accessToken: "access-1",
            backendSessions: ["stale-session", "fresh-session"]
        )
        let transport = RemoteHTTPCommandTransport(sessionProvider: sessionProvider, session: session)

        RemoteBridgeURLProtocol.install { request in
            guard request.url?.path == "/api/anki/rpc/5/2" else {
                throw RemoteBridgeTestError.unexpectedRequest(request.url?.absoluteString ?? "<nil>")
            }

            if request.value(forHTTPHeaderField: "X-Anki-Backend-Session") == "stale-session" {
                return try protobufResponse(for: request, status: 404, body: Data(), isBackendError: false)
            }

            var backendError = Anki_Backend_BackendError()
            backendError.message = "backend boom"
            return try protobufResponse(
                for: request,
                body: backendError.serializedData(),
                isBackendError: true
            )
        }

        do {
            let _: Anki_Generic_Empty = try await transport.sendCommand(
                service: 5,
                method: 2,
                input: Anki_Generic_Empty()
            )
            Issue.record("Expected backend error response")
        } catch let error as AnkiError {
            guard case let .backend(backendError) = error else {
                Issue.record("Expected AnkiError.backend, got \(error)")
                return
            }
            #expect(backendError.message == "backend boom")
        }

        #expect(await sessionProvider.invalidatedBackendSessionCount() == 1)
        #expect(await sessionProvider.recoveryCount() == 1)
        #expect(await sessionProvider.ensureBackendSessionCallCount() == 2)
        let retriedRequest = try #require(RemoteBridgeURLProtocol.requests(matchingPath: "/api/anki/rpc/5/2").last)
        #expect(retriedRequest.value(forHTTPHeaderField: "X-Anki-Backend-Session") == "fresh-session")
    }

    @Test
    // swiftlint:disable function_body_length
    func sessionProviderRecoversLostBackendAndReplaysOpenCollection() async throws {
        try await withRemoteSessionProvider(
            preferredLanguages: ["en"],
            deploymentKind: .companion
        ) { session, _, provider, persistence in
            let exchangeExpiry = Date(timeIntervalSinceNow: 3600)
            RemoteBridgeURLProtocol.install { request in
                switch request.url?.path {
                case "/api/auth/pair/exchange":
                    return try jsonResponse(
                        for: request,
                        body: [
                            "access_token": "access-1",
                            "refresh_token": "refresh-1",
                            "expires_at": iso8601(exchangeExpiry),
                            "account_id": "acct-1",
                            "account_display_name": "Test Device",
                            "capabilities": capabilitiesPayload(supportsAtlas: true)
                        ]
                    )
                case "/api/anki/backend/init":
                    return try jsonResponse(for: request, body: ["backend_session_id": "backend-2"])
                case "/api/anki/rpc/3/0":
                    return try protobufResponse(
                        for: request,
                        body: try Anki_Generic_Empty().serializedData(),
                        isBackendError: false
                    )
                case "/api/anki/rpc/7/9":
                    var response = Anki_Generic_String()
                    response.val = "pong"
                    return try protobufResponse(for: request, body: response.serializedData(), isBackendError: false)
                default:
                    throw RemoteBridgeTestError.unexpectedRequest(request.url?.absoluteString ?? "<nil>")
                }
            }

            _ = try await provider.exchangePairingCode("PAIR1234")
            await provider.recordRemoteCollectionState(
                path: "/tmp/collection.anki2",
                mediaFolder: "/tmp/collection.media",
                mediaDb: "/tmp/collection.media.db2"
            )
            await provider.invalidateBackendSession()
            try await provider.recoverBackendSessionAfterNotFound()

            let initRequest = try #require(RemoteBridgeURLProtocol.requests(matchingPath: "/api/anki/backend/init").last)
            #expect(initRequest.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")

            let openRequest = try #require(RemoteBridgeURLProtocol.requests(matchingPath: "/api/anki/rpc/3/0").last)
            #expect(openRequest.value(forHTTPHeaderField: "X-Anki-Backend-Session") == "backend-2")
            let openMessage = try Anki_Collection_OpenCollectionRequest(serializedBytes: requestBodyData(from: openRequest))
            #expect(openMessage.collectionPath == "/tmp/collection.anki2")
            #expect(openMessage.mediaFolderPath == "/tmp/collection.media")
            #expect(openMessage.mediaDbPath == "/tmp/collection.media.db2")

            let restoredProvider = RemoteSessionProvider(
                session: session,
                preferredLanguages: ["en"],
                persistence: persistence
            )
            #expect(await restoredProvider.currentRemoteCollectionState()?.path == "/tmp/collection.anki2")
        }
    }
    // swiftlint:enable function_body_length

    @Test
    func remoteOpenAndCloseCollectionPersistRemoteCollectionState() async throws {
        let transport = RecordingBackendTransport()
        try await transport.enqueueResponse(Anki_Generic_Empty())
        try await transport.enqueueResponse(Anki_Generic_Empty())
        let endpoint = try #require(URL(string: "http://remote.test/"))
        let sessionManager = StubRemoteSessionManager(endpoint: BackendEndpoint(baseURL: endpoint, deploymentKind: .companion))
        let service = RemoteAnkiService(transport: transport, sessionManager: sessionManager)

        try await service.openCollection(
            path: "/tmp/collection.anki2",
            mediaFolder: "/tmp/collection.media",
            mediaDb: "/tmp/collection.media.db2"
        )
        let recordedState = await sessionManager.currentRemoteCollectionState()
        #expect(recordedState?.path == "/tmp/collection.anki2")
        #expect(recordedState?.mediaFolder == "/tmp/collection.media")
        #expect(recordedState?.mediaDb == "/tmp/collection.media.db2")

        try await service.closeCollection(downgrade: false)
        #expect(await sessionManager.currentRemoteCollectionState() == nil)
    }
}
// swiftlint:enable type_body_length

private func withRemoteSessionProvider(
    preferredLanguages: [String],
    deploymentKind: BackendDeploymentKind,
    _ body: (URLSession, URL, RemoteSessionProvider, RemoteSessionPersistence) async throws -> Void
) async throws {
    RemoteBridgeURLProtocol.reset()
    defer {
        RemoteBridgeURLProtocol.reset()
    }

    let endpoint = try #require(URL(string: "http://remote.test/"))
    let session = makeRemoteBridgeURLSession()
    let persistence = makeInMemoryRemoteSessionPersistence()
    let provider = RemoteSessionProvider(
        session: session,
        preferredLanguages: preferredLanguages,
        persistence: persistence
    )
    await provider.updateEndpoint(BackendEndpoint(baseURL: endpoint, deploymentKind: deploymentKind))
    try await body(session, endpoint, provider, persistence)
}
