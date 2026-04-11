import Foundation
import Observation

// swiftlint:disable type_body_length
@Observable
@MainActor
public final class BackendConnectionStore {
    private static let endpointDefaultsKey = "remoteBackendEndpoint"
    private static let executionPolicyDefaultsKey = "remoteBackendExecutionPolicy"
    private static let selectedExecutionModeDefaultsKey = "selectedBackendExecutionMode"

    public var endpointURLString: String
    public var deploymentKind: BackendDeploymentKind
    public var pairingCode: String = ""
    public var issuedPairingCode: PairingCodeResponse?
    public var connectionState: BackendConnectionState = .disconnected
    public var capabilities: BackendCapabilities?
    public var executionMode: BackendExecutionMode = .unavailable
    public var selectedExecutionMode: BackendExecutionMode
    public var canServeBackend: Bool = false
    public var runtimeStatusMessage: String?
    public var localRuntimeStatus: LocalRuntimeStatus
    public var lastVerifiedEndpoint: BackendEndpoint?
    public var lastErrorMessage: String?
    public var executionPolicy: ExecutionPolicy {
        didSet {
            guard executionPolicy != oldValue else { return }
            persistExecutionPolicy()
        }
    }

    public let failoverCoordinator: FailoverCoordinator

    private let sessionProvider: any RemoteSessionManaging
    private let endpointDiscoverer: any BackendEndpointDiscovering
    private let localRuntimeProbe: @Sendable () async -> LocalRuntimeStatus
    private let defaults: UserDefaults
    @ObservationIgnored public var onAvailabilityChange: (@MainActor @Sendable () async -> Void)?

    public init(
        sessionProvider: any RemoteSessionManaging,
        failoverCoordinator: FailoverCoordinator = FailoverCoordinator(),
        endpointDiscoverer: any BackendEndpointDiscovering = DefaultBackendEndpointDiscoverer(),
        localRuntimeProbe: @escaping @Sendable () async -> LocalRuntimeStatus = {
            .unavailable(message: "Local iOS bridge support is not configured for this build.")
        },
        defaults: UserDefaults = .standard
    ) {
        self.sessionProvider = sessionProvider
        self.failoverCoordinator = failoverCoordinator
        self.endpointDiscoverer = endpointDiscoverer
        self.localRuntimeProbe = localRuntimeProbe
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

        if let rawMode = defaults.string(forKey: Self.selectedExecutionModeDefaultsKey),
           let decodedMode = BackendExecutionMode(rawValue: rawMode),
           decodedMode != .unavailable {
            selectedExecutionMode = decodedMode
        } else {
            selectedExecutionMode = .remote
        }

        localRuntimeStatus = .unavailable(message: "Local iOS backend has not been probed yet.")
        self.failoverCoordinator.executionPolicy = executionPolicy
    }

    public var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    public var supportsAtlas: Bool {
        guard canServeBackend else { return false }
        return switch executionMode {
            case .remote:
                capabilities?.supportsAtlas == true
            case .local:
                localRuntimeStatus.atlasAvailability == .available
            case .unavailable:
                false
        }
    }

    public var remoteBackendReady: Bool {
        isConnected && capabilities?.supportsRemoteAnki == true
    }

    public var localBackendReady: Bool {
        localRuntimeStatus.ankiAvailable
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
        await refreshLocalRuntimeStatus()
        await reevaluateAvailability()
    }

    public func refreshLocalRuntimeStatus() async {
        localRuntimeStatus = await localRuntimeProbe()
    }

    public func selectExecutionMode(_ mode: BackendExecutionMode) async {
        guard mode != .unavailable else { return }
        selectedExecutionMode = mode
        defaults.set(mode.rawValue, forKey: Self.selectedExecutionModeDefaultsKey)
        switch mode {
            case .remote:
                executionPolicy = .preferRemote
            case .local:
                executionPolicy = .preferLocal
            case .unavailable:
                break
        }
        await reevaluateAvailability()
    }

    public func saveEndpoint() async {
        var successMessage: String?
        do {
            _ = try await persistConfiguredEndpoint()
            lastErrorMessage = nil
            successMessage = "Saved backend endpoint."
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        await reevaluateAvailability()
        if let successMessage {
            runtimeStatusMessage = successMessage
        }
    }

    public func verifyConnection() async {
        connectionState = .connecting
        var successMessage: String?
        do {
            let endpoint = try await persistConfiguredEndpoint()
            try await endpointDiscoverer.verify(endpoint: endpoint)
            lastVerifiedEndpoint = endpoint
            successMessage = "Verified backend endpoint at \(endpoint.baseURL.absoluteString)."
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
        await reevaluateAvailability()
        if let successMessage {
            runtimeStatusMessage = successMessage
        }
    }

    public func discoverCompanion() async {
        connectionState = .connecting
        var successMessage: String?
        do {
            guard let endpoint = try await endpointDiscoverer.discoverPreferredEndpoint(for: .companion) else {
                throw AnkiError.message("No reachable companion endpoint was found on this device.")
            }
            endpointURLString = endpoint.baseURL.absoluteString
            deploymentKind = endpoint.deploymentKind
            await sessionProvider.updateEndpoint(endpoint)
            lastVerifiedEndpoint = endpoint
            successMessage = "Discovered companion backend at \(endpoint.baseURL.absoluteString)."
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
        await reevaluateAvailability()
        if let successMessage {
            runtimeStatusMessage = successMessage
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
            await refreshLocalRuntimeStatus()
            await reevaluateAvailability()
            return
        }

        await verifyConnection()
        await refreshLocalRuntimeStatus()
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
        } catch {
            capabilities = nil
            executionMode = .unavailable
            canServeBackend = false
            runtimeStatusMessage = nil
            connectionState = .error(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
        await reevaluateAvailability()
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
        await reevaluateAvailability()
    }

    public func signOut() async {
        await sessionProvider.signOut()
        capabilities = nil
        if selectedExecutionMode == .remote {
            executionMode = .unavailable
            canServeBackend = false
        }
        connectionState = .disconnected
        pairingCode = ""
        issuedPairingCode = nil
        lastErrorMessage = nil
        lastVerifiedEndpoint = nil
        await reevaluateAvailability()
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
        let previousExecutionMode = executionMode
        let previousReachability = canServeBackend
        let remoteCapabilities: BackendCapabilities?
        if let capabilities {
            remoteCapabilities = capabilities
        } else {
            remoteCapabilities = await sessionProvider.currentCapabilities()
        }
        capabilities = remoteCapabilities

        let decision = failoverCoordinator.resolveDecision(
            remoteCapabilities: remoteCapabilities,
            isRemoteConnected: isConnected,
            localReplicaAvailable: localBackendReady
        )
        executionMode = decision.executionMode
        canServeBackend = decision.isBackendReachable

        switch executionMode {
            case .remote:
                runtimeStatusMessage =
                    decision.message
                    ?? runtimeStatusMessage
                    ?? "Remote backend ready."
            case .local:
                runtimeStatusMessage =
                    localRuntimeStatus.detailMessage
                    ?? decision.message
                    ?? runtimeStatusMessage
                    ?? "Local iOS backend ready."
            case .unavailable:
                runtimeStatusMessage =
                    lastErrorMessage
                    ?? decision.message
                    ?? localRuntimeStatus.detailMessage
                    ?? runtimeStatusMessage
                    ?? "No backend is currently available."
        }

        if previousExecutionMode != executionMode || previousReachability != canServeBackend {
            await onAvailabilityChange?()
        }
    }
}
// swiftlint:enable type_body_length
