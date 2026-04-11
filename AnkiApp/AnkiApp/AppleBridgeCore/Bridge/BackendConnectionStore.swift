import Foundation
import Observation

@Observable
@MainActor
public final class BackendConnectionStore {
    public var endpointURLString: String
    public var deploymentKind: BackendDeploymentKind
    public var pairingCode: String = ""
    public var issuedPairingCode: PairingCodeResponse?
    public var connectionState: BackendConnectionState = .disconnected
    public var capabilities: BackendCapabilities?
    public var executionMode: BackendExecutionMode = .unavailable
    public var lastErrorMessage: String?

    public let failoverCoordinator: FailoverCoordinator

    private let sessionProvider: RemoteSessionProvider

    public init(
        sessionProvider: RemoteSessionProvider,
        failoverCoordinator: FailoverCoordinator = FailoverCoordinator()
    ) {
        self.sessionProvider = sessionProvider
        self.failoverCoordinator = failoverCoordinator

        if let endpoint = UserDefaults.standard.data(forKey: "remoteBackendEndpoint"),
           let decoded = try? JSONDecoder().decode(BackendEndpoint.self, from: endpoint) {
            endpointURLString = decoded.baseURL.absoluteString
            deploymentKind = decoded.deploymentKind
        } else {
            endpointURLString = "http://127.0.0.1:8080/"
            deploymentKind = .companion
        }
    }

    public var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    public var supportsAtlas: Bool {
        capabilities?.supportsAtlas == true && isConnected
    }

    public func restore() async {
        if let session = await sessionProvider.currentAuthSession() {
            do {
                capabilities = try await sessionProvider.refreshCapabilities()
                executionMode = capabilities?.executionMode ?? .remote
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
            executionMode = .unavailable
        }
    }

    public func saveEndpoint() async {
        let trimmed = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else {
            lastErrorMessage = "Enter a valid backend URL."
            return
        }
        await sessionProvider.updateEndpoint(BackendEndpoint(baseURL: url, deploymentKind: deploymentKind))
        lastErrorMessage = nil
    }

    public func requestPairingCode() async {
        connectionState = .connecting
        do {
            await saveEndpoint()
            issuedPairingCode = try await sessionProvider.issuePairingCode()
            if pairingCode.isEmpty {
                pairingCode = issuedPairingCode?.pairingCode ?? ""
            }
            connectionState = .disconnected
            lastErrorMessage = nil
        } catch {
            issuedPairingCode = nil
            connectionState = .error(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    public func connect() async {
        connectionState = .connecting
        do {
            await saveEndpoint()
            let session = try await sessionProvider.exchangePairingCode(pairingCode)
            capabilities = try await sessionProvider.refreshCapabilities()
            executionMode = capabilities?.executionMode ?? .remote
            connectionState = .connected(
                BackendConnectionAccount(
                    accountID: session.accountID,
                    displayName: session.accountDisplayName
                )
            )
            lastErrorMessage = nil
        } catch {
            executionMode = .unavailable
            connectionState = .error(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    public func signOut() async {
        await sessionProvider.signOut()
        capabilities = nil
        executionMode = .unavailable
        connectionState = .disconnected
        pairingCode = ""
        issuedPairingCode = nil
        lastErrorMessage = nil
    }
}
