import Foundation
import Observation

enum SyncState: Equatable {
    case loggedOut
    case idle
    case syncing(String)
    case error(String)
    case fullSyncRequired(upload: Bool?, serverMediaUsn: Int32)
}

@Observable
@MainActor
final class SyncModel {
    var state: SyncState = .loggedOut
    var lastSyncError: AnkiError?
    var serverMessage: String?

    private let service: AnkiServiceProtocol
    private(set) var auth: Anki_Sync_SyncAuth?

    init(service: AnkiServiceProtocol) {
        self.service = service
        auth = KeychainHelper.loadAuth()
        if auth != nil {
            state = .idle
        }
    }

    var isAuthenticated: Bool {
        auth != nil
    }

    func login(username: String, password: String) async {
        state = .syncing("Logging in...")
        do {
            let authResponse = try await service.syncLogin(username: username, password: password)
            auth = authResponse
            KeychainHelper.saveAuth(authResponse)
            state = .idle
        } catch let ankiError as AnkiError {
            state = .loggedOut
            lastSyncError = ankiError
        } catch {
            state = .loggedOut
            state = .error(error.localizedDescription)
        }
    }

    func logout() {
        KeychainHelper.deleteAuth()
        auth = nil
        state = .loggedOut
        serverMessage = nil
    }

    func sync() async {
        guard var currentAuth = auth else {
            state = .loggedOut
            return
        }

        state = .syncing("Checking sync status...")
        do {
            let statusResponse = try await service.syncStatus(auth: currentAuth)
            if statusResponse.hasNewEndpoint {
                currentAuth.endpoint = statusResponse.newEndpoint
                auth = currentAuth
                KeychainHelper.saveAuth(currentAuth)
            }

            switch statusResponse.required {
                case .noChanges:
                    state = .idle
                    serverMessage = nil
                    return
                case .normalSync:
                    try await performNormalSync(auth: currentAuth)
                case .fullSync:
                    state = .fullSyncRequired(upload: nil, serverMediaUsn: 0)
                    return
                case .UNRECOGNIZED:
                    state = .error("Unrecognized sync status")
                    return
            }
        } catch let ankiError as AnkiError {
            state = .idle
            lastSyncError = ankiError
        } catch {
            state = .idle
            state = .error(error.localizedDescription)
        }
    }

    private func performNormalSync(auth: Anki_Sync_SyncAuth) async throws {
        state = .syncing("Syncing collection...")
        let response = try await service.syncCollection(auth: auth, syncMedia: true)

        var updatedAuth = auth
        if response.hasNewEndpoint {
            updatedAuth.endpoint = response.newEndpoint
            self.auth = updatedAuth
            KeychainHelper.saveAuth(updatedAuth)
        }

        if !response.serverMessage.isEmpty {
            serverMessage = response.serverMessage
        }

        switch response.required {
            case .noChanges, .normalSync:
                state = .idle
            case .fullSync:
                state = .fullSyncRequired(upload: nil, serverMediaUsn: response.serverMediaUsn)
            case .fullDownload:
                state = .fullSyncRequired(upload: false, serverMediaUsn: response.serverMediaUsn)
            case .fullUpload:
                state = .fullSyncRequired(upload: true, serverMediaUsn: response.serverMediaUsn)
            case .UNRECOGNIZED:
                state = .error("Unrecognized sync response")
        }
    }

    func performFullSync(upload: Bool, serverMediaUsn: Int32) async {
        guard let currentAuth = auth else {
            state = .loggedOut
            return
        }

        state = .syncing(upload ? "Uploading collection..." : "Downloading collection...")
        do {
            try await service.fullUploadOrDownload(
                auth: currentAuth,
                upload: upload,
                serverUsn: serverMediaUsn != 0 ? serverMediaUsn : nil
            )
            state = .syncing("Syncing media...")
            try await service.syncMedia(auth: currentAuth)
            state = .idle
        } catch let ankiError as AnkiError {
            state = .idle
            lastSyncError = ankiError
        } catch {
            state = .idle
            state = .error(error.localizedDescription)
        }
    }
}
