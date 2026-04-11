@testable import AppleBridgeCore
import Foundation
import Testing

@Suite(.serialized)
struct BackendConnectionStoreTests {
    @Test
    @MainActor
    func preferRemoteRestoresUsableRemoteBackend() async throws {
        clearRemoteBridgeArtifacts()
        defer { clearRemoteBridgeArtifacts() }

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
        let defaults = makeIsolatedUserDefaults()
        let store = BackendConnectionStore(
            sessionProvider: sessionManager,
            failoverCoordinator: FailoverCoordinator(executionPolicy: .preferRemote),
            endpointDiscoverer: StubEndpointDiscoverer(),
            defaults: defaults
        )

        await store.restore()

        #expect(store.isConnected)
        #expect(store.canServeBackend)
        #expect(store.executionMode == .remote)
        #expect(store.supportsAtlas)
        #expect(store.runtimeStatusMessage == nil)
    }

    @Test
    @MainActor
    func localOnlyPolicyKeepsBackendUnavailableWithoutLocalTransport() async throws {
        clearRemoteBridgeArtifacts()
        defer { clearRemoteBridgeArtifacts() }

        let endpoint = try #require(URL(string: "http://remote.test/"))
        let capabilities = BackendCapabilities(
            supportsRemoteAnki: true,
            supportsAtlas: false,
            deploymentKind: .companion,
            executionMode: .remote
        )
        let session = RemoteAuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSinceNow: 3600),
            accountID: "acct-1",
            accountDisplayName: "Companion Account",
            capabilities: capabilities
        )
        let sessionManager = StubRemoteSessionManager(
            endpoint: BackendEndpoint(baseURL: endpoint, deploymentKind: .companion),
            currentSession: session,
            currentCapabilities: capabilities
        )
        let defaults = makeIsolatedUserDefaults()
        let store = BackendConnectionStore(
            sessionProvider: sessionManager,
            failoverCoordinator: FailoverCoordinator(executionPolicy: .localOnly),
            endpointDiscoverer: StubEndpointDiscoverer(),
            defaults: defaults
        )

        await store.restore()

        #expect(store.isConnected)
        #expect(!store.canServeBackend)
        #expect(store.executionMode == .unavailable)
        #expect(store.runtimeStatusMessage?.contains("local iOS replica") == true)
    }

    @Test
    @MainActor
    func discoverAndVerifyUpdateEndpointState() async throws {
        clearRemoteBridgeArtifacts()
        defer { clearRemoteBridgeArtifacts() }

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

    @Test
    @MainActor
    func changingExecutionPolicyReevaluatesAvailability() async throws {
        clearRemoteBridgeArtifacts()
        defer { clearRemoteBridgeArtifacts() }

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
        let defaults = makeIsolatedUserDefaults()
        let store = BackendConnectionStore(
            sessionProvider: sessionManager,
            endpointDiscoverer: StubEndpointDiscoverer(),
            defaults: defaults
        )

        await store.restore()
        #expect(store.canServeBackend)

        store.executionPolicy = .localOnly
        try await Task.sleep(for: .milliseconds(50))

        #expect(!store.canServeBackend)
        #expect(store.executionMode == .unavailable)
    }
}
