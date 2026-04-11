import Foundation

public enum BackendDeploymentKind: String, Codable, Sendable, CaseIterable {
    case companion
    case cloud
}

public enum BackendExecutionMode: String, Codable, Sendable {
    case local
    case remote
    case unavailable
}

public enum ExecutionPolicy: String, Codable, Sendable, CaseIterable {
    case preferRemote
    case preferLocal
    case remoteOnly
    case localOnly
}

public struct BackendEndpoint: Codable, Equatable, Sendable {
    public var baseURL: URL
    public var deploymentKind: BackendDeploymentKind

    public init(baseURL: URL, deploymentKind: BackendDeploymentKind) {
        self.baseURL = baseURL
        self.deploymentKind = deploymentKind
    }
}

public struct BackendCapabilities: Codable, Equatable, Sendable {
    public var supportsRemoteAnki: Bool
    public var supportsAtlas: Bool
    public var deploymentKind: BackendDeploymentKind
    public var executionMode: BackendExecutionMode

    public init(
        supportsRemoteAnki: Bool,
        supportsAtlas: Bool,
        deploymentKind: BackendDeploymentKind,
        executionMode: BackendExecutionMode
    ) {
        self.supportsRemoteAnki = supportsRemoteAnki
        self.supportsAtlas = supportsAtlas
        self.deploymentKind = deploymentKind
        self.executionMode = executionMode
    }

    enum CodingKeys: String, CodingKey {
        case supportsRemoteAnki = "supports_remote_anki"
        case supportsAtlas = "supports_atlas"
        case deploymentKind = "deployment_kind"
        case executionMode = "execution_mode"
    }
}

public struct RemoteAuthSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var accountID: String
    public var accountDisplayName: String
    public var capabilities: BackendCapabilities

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        accountID: String,
        accountDisplayName: String,
        capabilities: BackendCapabilities
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountID = accountID
        self.accountDisplayName = accountDisplayName
        self.capabilities = capabilities
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case accountID = "account_id"
        case accountDisplayName = "account_display_name"
        case capabilities
    }
}

public struct PairingCodeResponse: Codable, Equatable, Sendable {
    public var pairingCode: String
    public var pairingURL: URL?
    public var expiresAt: Date

    public init(pairingCode: String, pairingURL: URL?, expiresAt: Date) {
        self.pairingCode = pairingCode
        self.pairingURL = pairingURL
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case pairingCode = "pairing_code"
        case pairingURL = "pairing_url"
        case expiresAt = "expires_at"
    }
}

public struct BackendConnectionAccount: Equatable, Sendable {
    public var accountID: String
    public var displayName: String

    public init(accountID: String, displayName: String) {
        self.accountID = accountID
        self.displayName = displayName
    }
}

public enum BackendConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected(BackendConnectionAccount)
    case error(String)
}

public struct FailoverDecision: Equatable, Sendable {
    public var executionMode: BackendExecutionMode
    public var isBackendReachable: Bool
    public var message: String?

    public init(
        executionMode: BackendExecutionMode,
        isBackendReachable: Bool,
        message: String?
    ) {
        self.executionMode = executionMode
        self.isBackendReachable = isBackendReachable
        self.message = message
    }
}

public final class FailoverCoordinator: @unchecked Sendable {
    public var executionPolicy: ExecutionPolicy

    public init(executionPolicy: ExecutionPolicy = .preferRemote) {
        self.executionPolicy = executionPolicy
    }

    public func resolveDecision(
        remoteCapabilities: BackendCapabilities?,
        isRemoteConnected: Bool,
        localReplicaAvailable: Bool
    ) -> FailoverDecision {
        let remoteAvailable = isRemoteConnected && remoteCapabilities?.supportsRemoteAnki == true

        switch executionPolicy {
            case .preferRemote:
                return preferRemoteDecision(
                    remoteAvailable: remoteAvailable,
                    localReplicaAvailable: localReplicaAvailable
                )
            case .preferLocal:
                return preferLocalDecision(
                    remoteAvailable: remoteAvailable,
                    localReplicaAvailable: localReplicaAvailable
                )
            case .remoteOnly:
                return remoteOnlyDecision(remoteAvailable: remoteAvailable)
            case .localOnly:
                return localOnlyDecision(localReplicaAvailable: localReplicaAvailable)
        }
    }

    private func preferRemoteDecision(
        remoteAvailable: Bool,
        localReplicaAvailable: Bool
    ) -> FailoverDecision {
        if remoteAvailable {
            return FailoverDecision(executionMode: .remote, isBackendReachable: true, message: nil)
        }
        if localReplicaAvailable {
            return FailoverDecision(
                executionMode: .local,
                isBackendReachable: true,
                message: "Remote backend unavailable; falling back to the local replica."
            )
        }
        return FailoverDecision(
            executionMode: .unavailable,
            isBackendReachable: false,
            message: "No remote backend connection is active, and no local replica is available."
        )
    }

    private func preferLocalDecision(
        remoteAvailable: Bool,
        localReplicaAvailable: Bool
    ) -> FailoverDecision {
        if localReplicaAvailable {
            return FailoverDecision(
                executionMode: .local,
                isBackendReachable: true,
                message: remoteAvailable ? "Local replica preferred; remote backend kept available as fallback." : nil
            )
        }
        if remoteAvailable {
            return FailoverDecision(
                executionMode: .remote,
                isBackendReachable: true,
                message: "Local replica unavailable; continuing with the remote backend."
            )
        }
        return FailoverDecision(
            executionMode: .unavailable,
            isBackendReachable: false,
            message: "Neither a local replica nor a remote backend is available."
        )
    }

    private func remoteOnlyDecision(remoteAvailable: Bool) -> FailoverDecision {
        FailoverDecision(
            executionMode: remoteAvailable ? .remote : .unavailable,
            isBackendReachable: remoteAvailable,
            message: remoteAvailable ? nil : "Execution policy requires a remote backend connection."
        )
    }

    private func localOnlyDecision(localReplicaAvailable: Bool) -> FailoverDecision {
        FailoverDecision(
            executionMode: localReplicaAvailable ? .local : .unavailable,
            isBackendReachable: localReplicaAvailable,
            message: localReplicaAvailable ? nil : "Execution policy requires a local iOS replica."
        )
    }
}
