import SwiftUI
import AppleBridgeCore
import AppleSharedUI

struct SyncView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("ankiwebUsername") private var storedUsername = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showFullSyncAlert: Bool = false

    var body: some View {
        let model = appState.syncModel
        Group {
            if !appState.isCollectionOpen {
                ContentUnavailableView {
                    Label("No Collection Open", systemImage: "folder.badge.plus")
                } description: {
                    Text("Open a collection from Preferences to sync with AnkiWeb.")
                } actions: {
                    Button("Open Preferences") {
                        appState.showPreferences()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                if model.isAuthenticated {
                    authenticatedView(model: model)
                } else {
                    loginView(model: model)
                }
            }
        }
        .navigationTitle("Sync")
        .onAppear {
            if username.isEmpty {
                username = storedUsername
            }
        }
        .ankiErrorAlert(Binding(
            get: { model.lastSyncError },
            set: { model.lastSyncError = $0 }
        ))
    }

    private func loginView(model: SyncModel) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "person.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Sign in to AnkiWeb")
                .font(.title2.bold())

            Text("Enter your AnkiWeb credentials to sync your collection across devices.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            VStack(spacing: 12) {
                TextField("Email", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .onSubmit {
                        Task { await performLogin(model: model) }
                    }
            }
            .frame(maxWidth: 280)

            if case let .syncing(message) = model.state {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(message)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else {
                Button("Sign In") {
                    Task { await performLogin(model: model) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(username.isEmpty || password.isEmpty)
            }

            if case let .error(message) = model.state {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func authenticatedView(model: SyncModel) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Sync with AnkiWeb")
                .font(.title2.bold())

            syncStateView(model: model)

            if let message = model.serverMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Button("Sign Out", role: .destructive) {
                model.logout()
                password = ""
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Full Sync Required", isPresented: $showFullSyncAlert) {
            fullSyncAlertActions(model: model)
        } message: {
            Text(
                "Your collection has diverged from the server. Would you like to upload your local collection or download the server's version?"
            )
        }
        .onChange(of: model.state) { _, newState in
            if case .fullSyncRequired = newState {
                showFullSyncAlert = true
            }
        }
    }

    @ViewBuilder
    private func syncStateView(model: SyncModel) -> some View {
        switch model.state {
            case let .syncing(message):
                VStack(spacing: 12) {
                    ProgressView()
                    Text(message)
                        .foregroundStyle(.secondary)
                }
                .animation(.default, value: message)
            case let .error(message):
                VStack(spacing: 8) {
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.caption)
                    syncButton(model: model)
                }
            default:
                syncButton(model: model)
        }
    }

    private func syncButton(model: SyncModel) -> some View {
        Button("Sync Now") {
            Task { await model.sync() }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("s", modifiers: .command)
    }

    @ViewBuilder
    private func fullSyncAlertActions(model: SyncModel) -> some View {
        if case let .fullSyncRequired(upload, serverMediaUsn) = model.state {
            if upload == nil {
                Button("Upload to AnkiWeb") {
                    Task { await model.performFullSync(upload: true, serverMediaUsn: serverMediaUsn) }
                }
                Button("Download from AnkiWeb") {
                    Task { await model.performFullSync(upload: false, serverMediaUsn: serverMediaUsn) }
                }
                Button("Cancel", role: .cancel) {
                    model.state = .idle
                }
            } else if let upload {
                Button(upload ? "Upload" : "Download") {
                    Task { await model.performFullSync(upload: upload, serverMediaUsn: serverMediaUsn) }
                }
                Button("Cancel", role: .cancel) {
                    model.state = .idle
                }
            }
        }
    }

    private func performLogin(model: SyncModel) async {
        guard !username.isEmpty, !password.isEmpty else { return }
        await model.login(username: username, password: password)
        if model.isAuthenticated {
            storedUsername = username
            password = ""
            appState.refreshSyncSchedule()
        }
    }
}

#Preview {
    SyncView()
        .environment(AppState())
}
