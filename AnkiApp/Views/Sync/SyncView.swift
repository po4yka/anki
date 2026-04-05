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
                        Text(model.statusMessage)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Sync Now") {
                        Task { await model.sync() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)

                    if let lastSync = model.lastSyncDate {
                        Text("Last synced: \(lastSync.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .ankiErrorAlert($model?.error)
    }
}

#Preview {
    SyncView()
        .environment(AppState())
}
