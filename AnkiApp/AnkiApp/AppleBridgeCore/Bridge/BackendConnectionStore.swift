import Foundation
import Observation

// swiftlint:disable type_body_length
@Observable
@MainActor
public final class BackendConnectionStore {
    private static let endpointDefaultsKey = "remoteBackendEndpoint"
    private static let executionPolicyDefaultsKey = "remoteBackendExecutionPolicy"

    public var endpointURLString: String
    public var deploymentKind: BackendDeploymentKind
    public var pairingCode: String = ""
    public var issuedPairingCode: PairingCodeResponse?
    public var connectionState: BackendConnectionState = .disconnected
    public var capabilities: BackendCapabilities?
    public var executionMode: BackendExecutionMode = .unavailable
    public var canServeBackend: Bool = false
    public var runtimeStatusMessage: String?
    public var lastVerifiedEndpoint: BackendEndpoint?
    public var lastErrorMessage: String?
    public var executionPolicy: ExecutionPolicy {
        didSet {
            guard executionPolicy != oldValue else { return }
            persistExecutionPolicy()
            Task { await reevaluateAvailability() }
        }
    }

    public let failoverCoordinator: FailoverCoordinator

    private let sessionProvider: any RemoteSessionManaging
    private let endpointDiscoverer: any BackendEndpointDiscovering
    private let localReplicaAvailability: @Sendable () async -> Bool
    private let supportsLocalReplicaTransport: Bool
    private let defaults: UserDefaults

    public init(
        sessionProvider: any RemoteSessionManaging,
        failoverCoordinator: FailoverCoordinator = FailoverCoordinator(),
        endpointDiscoverer: any BackendEndpointDiscovering = DefaultBackendEndpointDiscoverer(),
        localReplicaAvailability: @escaping @Sendable () async -> Bool = { false },
        supportsLocalReplicaTransport: Bool = false,
        defaults: UserDefaults = .standard
    ) {
        self.sessionProvider = sessionProvider
        self.failoverCoordinator = failoverCoordinator
        self.endpointDiscoverer = endpointDiscoverer
        self.localReplicaAvailability = localReplicaAvailability
        self.supportsLocalReplicaTransport = supportsLocalReplicaTransport
        self.defaults = defaults

        if let endpoint = defaults.data(forKey: Self.endpointDefaultsKey),
           let decoded = try? JSONDecoder().decode(BackendEndpoint.self, from: endpoint) {
            endpointURLString = decoded.baseURL.absoluteString
            deploymentKind = decoded.deploymentKind
        } else {
            endpointURLString = "http://127.0.0.1:8080/"
            deploymentKind = .companion
        }

        if let rawPolicy = defaults.string(forKey: Self.executionPolicyDefaultsKey),
           let decodedPolicy = ExecutionPolicy(rawValue: rawPolicy) {
            executionPolicy = decodedPolicy
        } else {
            executionPolicy = failoverCoordinator.executionPolicy
        }
        self.failoverCoordinator.executionPolicy = executionPolicy
    }

    public var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    public var supportsAtlas: Bool {
        capabilities?.supportsAtlas == true && canServeBackend && executionMode == .remote
    }

    public func restore() async {
        if let session = await sessionProvider.currentAuthSession() {
            do {
                capabilities = try await sessionProvider.refreshCapabilities()
                connectionState = .connected(
                    BackendConnectionAccount(
                        accountID: session.accountID,
                        displayName: session.accountDisplayName
                    )
                )
                lastErrorMessage = nil
            } catch {
                connectionState = .error(error.localizedDescription)
                lastErrorMessage = error.localizedDescription
            }
        } else {
            connectionState = .disconnected
            capabilities = nil
            lastErrorMessage = nil
        }
        await reevaluateAvailability()
    }

    public func saveEndpoint() async {
        do {
            _ = try await persistConfiguredEndpoint()
            lastErrorMessage = nil
            runtimeStatusMessage = "Saved backend endpoint."
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func verifyConnection() async {
        connectionState = .connecting
        do {
            let endpoint = try await persistConfiguredEndpoint()
            try await endpointDiscoverer.verify(endpoint: endpoint)
            lastVerifiedEndpoint = endpoint
            runtimeStatusMessage = "Verified backend endpoint at \(endpoint.baseURL.absoluteString)."
            lastErrorMessage = nil
            if let account = connectedAccount {
                connectionState = .connected(account)
            } else {
                connectionState = .disconnected
            }
        } catch {
            connectionState = .error(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    public func discoverCompanion() async {
        connectionState = .connecting
        do {
            guard let endpoint = try await endpointDiscoverer.discoverPreferredEndpoint(for: .companion) else {
                throw AnkiError.message("No reachable companion endpoint was found on this device.")
            }
            endpointURLString = endpoint.baseURL.absoluteString
            deploymentKind = endpoint.deploymentKind
            await sessionProvider.updateEndpoint(endpoint)
            lastVerifiedEndpoint = endpoint
            runtimeStatusMessage = "Discovered companion backend at \(endpoint.baseURL.absoluteString)."
            lastErrorMessage = nil
            if let account = connectedAccount {
                connectionState = .connected(account)
            } else {
                connectionState = .disconnected
            }
        } catch {
            connectionState = .error(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    public func refreshStatus() async {
        if isConnected {
            do {
                capabilities = try await sessionProvider.refreshCapabilities()
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
            await reevaluateAvailability()
            return
        }

        await verifyConnection()
    }

    public func connect() async {
        connectionState = .connecting
        do {
            _ = try await persistConfiguredEndpoint()
            let session = try await sessionProvider.exchangePairingCode(pairingCode)
            capabilities = try await sessionProvider.refreshCapabilities()
            connectionState = .connected(
                BackendConnectionAccount(
                    accountID: session.accountID,
                    displayName: session.accountDisplayName
                )
            )
            lastErrorMessage = nil
            await reevaluateAvailability()
        } catch {
            capabilities = nil
            executionMode = .unavailable
            canServeBackend = false
            runtimeStatusMessage = nil
            connectionState = .error(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    public func requestPairingCode() async {
        connectionState = .connecting
        do {
            _ = try await persistConfiguredEndpoint()
            issuedPairingCode = try await sessionProvider.issuePairingCode(deviceName: nil)
            if pairingCode.isEmpty {
                pairingCode = issuedPairingCode?.pairingCode ?? ""
            }
            if let account = connectedAccount {
                connectionState = .connected(account)
            } else {
                connectionState = .disconnected
            }
            lastErrorMessage = nil
        } catch {
            issuedPairingCode = nil
            connectionState = .error(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    public func signOut() async {
        await sessionProvider.signOut()
        capabilities = nil
        executionMode = .unavailable
        canServeBackend = false
        connectionState = .disconnected
        pairingCode = ""
        issuedPairingCode = nil
        runtimeStatusMessage = nil
        lastErrorMessage = nil
        lastVerifiedEndpoint = nil
    }

    private var connectedAccount: BackendConnectionAccount? {
        if case let .connected(account) = connectionState {
            return account
        }
        return nil
    }

    private func configuredEndpoint() throws -> BackendEndpoint {
        let trimmed = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else {
            throw AnkiError.message("Enter a valid backend URL.")
        }
        return BackendEndpoint(baseURL: url, deploymentKind: deploymentKind)
    }

    private func persistConfiguredEndpoint() async throws -> BackendEndpoint {
        let endpoint = try configuredEndpoint()
        await sessionProvider.updateEndpoint(endpoint)
        lastVerifiedEndpoint = nil
        return endpoint
    }

    private func persistExecutionPolicy() {
        failoverCoordinator.executionPolicy = executionPolicy
        defaults.set(executionPolicy.rawValue, forKey: Self.executionPolicyDefaultsKey)
    }

    private func reevaluateAvailability() async {
        let remoteSession = await sessionProvider.currentAuthSession()
        let remoteCapabilities: BackendCapabilities?
        if let capabilities {
            remoteCapabilities = capabilities
        } else {
            remoteCapabilities = await sessionProvider.currentCapabilities()
        }
        let localReplicaAvailable = await localReplicaAvailability()
        let decision = failoverCoordinator.resolveDecision(
            remoteCapabilities: remoteCapabilities,
            isRemoteConnected: remoteSession != nil,
            localReplicaAvailable: localReplicaAvailable
        )

        capabilities = remoteCapabilities
        runtimeStatusMessage = decision.message

        if decision.executionMode == .local && !supportsLocalReplicaTransport {
            executionMode = .unavailable
            canServeBackend = false
            runtimeStatusMessage =
                "A local replica is selected by policy, but this build does not include the local iOS backend transport yet."
            return
        }

        executionMode = decision.executionMode
        canServeBackend = decision.isBackendReachable && decision.executionMode == .remote
    }
}
// swiftlint:enable type_body_length
