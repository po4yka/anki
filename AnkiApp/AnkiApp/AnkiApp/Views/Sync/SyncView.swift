import SwiftUI

struct SyncView: View {
    @Environment(AppState.self) private var appState
    @State private var model: SyncModel?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Sync with AnkiWeb")
                .font(.title2.bold())

            if let model {
                if model.isSyncing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Syncing...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Sync Now") {
                        Task { await model.loadTags() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)

                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Sync")
        .onAppear {
            if model == nil {
                model = SyncModel(service: appState.service)
            }
        }
        .ankiErrorAlert(Binding(
            get: { model?.lastSyncError },
            set: { model?.lastSyncError = $0 }
        ))
    }
}

#Preview {
    SyncView()
        .environment(AppState())
}
