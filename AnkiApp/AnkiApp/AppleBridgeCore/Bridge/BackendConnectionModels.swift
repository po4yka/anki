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

public final class FailoverCoordinator: @unchecked Sendable {
    public var executionPolicy: ExecutionPolicy

    public init(executionPolicy: ExecutionPolicy = .preferRemote) {
        self.executionPolicy = executionPolicy
    }
}
