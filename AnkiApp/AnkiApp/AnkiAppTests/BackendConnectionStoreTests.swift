@testable import AppleBridgeCore
import Foundation
import Testing

@Suite(.serialized)
struct BackendConnectionStoreTests {
    @Test
    @MainActor
    func restoreKeepsRemoteModeUsableWhenSessionIsConnected() async throws {
        let endpoint = try #require(URL(string: "http://remote.test/"))
        let capabilities = BackendCapabilities(
            supportsRemoteAnki: true,
            supportsAtlas: true,
            deploymentKind: .cloud,
            executionMode: .remote
        )
        let session = RemoteAuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSinceNow: 3600),
            accountID: "acct-1",
            accountDisplayName: "Cloud Account",
            capabilities: capabilities
        )
        let sessionManager = StubRemoteSessionManager(
            endpoint: BackendEndpoint(baseURL: endpoint, deploymentKind: .cloud),
            currentSession: session,
            currentCapabilities: capabilities
        )
        let store = BackendConnectionStore(
            sessionProvider: sessionManager,
            endpointDiscoverer: StubEndpointDiscoverer(),
            localRuntimeProbe: { .unavailable(message: "No local runtime") },
            defaults: makeIsolatedUserDefaults()
        )

        await store.restore()

        #expect(store.selectedExecutionMode == .remote)
        #expect(store.isConnected)
        #expect(store.canServeBackend)
        #expect(store.executionMode == .remote)
        #expect(store.supportsAtlas)
    }

    @Test
    @MainActor
    func selectingLocalModeUsesAvailableRuntime() async throws {
        let endpoint = try #require(URL(string: "http://remote.test/"))
        let store = BackendConnectionStore(
            sessionProvider: StubRemoteSessionManager(
                endpoint: BackendEndpoint(baseURL: endpoint, deploymentKind: .companion)
            ),
            endpointDiscoverer: StubEndpointDiscoverer(),
            localRuntimeProbe: {
                .ready(
                    atlasAvailability: .configurationMissing,
                    atlasMessage: "Atlas needs additional configuration."
                )
            },
            defaults: makeIsolatedUserDefaults()
        )

        await store.restore()
        await store.selectExecutionMode(.local)

        #expect(store.canServeBackend)
        #expect(store.executionMode == .local)
        #expect(!store.supportsAtlas)
        #expect(store.localRuntimeStatus.atlasAvailability == .configurationMissing)
    }

    @Test
    @MainActor
    func selectingLocalModeWithoutRuntimeLeavesBackendUnavailable() async throws {
        let endpoint = try #require(URL(string: "http://remote.test/"))
        let store = BackendConnectionStore(
            sessionProvider: StubRemoteSessionManager(
                endpoint: BackendEndpoint(baseURL: endpoint, deploymentKind: .companion)
            ),
            endpointDiscoverer: StubEndpointDiscoverer(),
            localRuntimeProbe: {
                .unavailable(message: "Local bridge support is missing.")
            },
            defaults: makeIsolatedUserDefaults()
        )

        await store.restore()
        await store.selectExecutionMode(.local)

        #expect(!store.canServeBackend)
        #expect(store.executionMode == .unavailable)
        #expect(store.runtimeStatusMessage == "Local bridge support is missing.")
    }

    @Test
    @MainActor
    func discoverAndVerifyUpdateEndpointState() async throws {
        let originalEndpoint = try #require(URL(string: "http://127.0.0.1:8080/"))
        let discoveredURL = try #require(URL(string: "http://localhost:8080/"))
        let sessionManager = StubRemoteSessionManager(
            endpoint: BackendEndpoint(baseURL: originalEndpoint, deploymentKind: .companion)
        )
        let discoverer = StubEndpointDiscoverer()
        await discoverer.setDiscoveredEndpoint(BackendEndpoint(
            baseURL: discoveredURL,
            deploymentKind: .companion
        ))

        let store = BackendConnectionStore(
            sessionProvider: sessionManager,
            endpointDiscoverer: discoverer,
            defaults: makeIsolatedUserDefaults()
        )

        await store.discoverCompanion()
        #expect(store.endpointURLString == discoveredURL.absoluteString)
        #expect(store.lastVerifiedEndpoint?.baseURL == discoveredURL)

        await store.verifyConnection()
        let verified = await discoverer.allVerifiedEndpoints()
        #expect(verified.last?.baseURL == discoveredURL)
        #expect(store.runtimeStatusMessage?.contains("Verified backend endpoint") == true)
    }
}
