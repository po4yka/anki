import SwiftUI

struct SyncSettingsView: View {
    @AppStorage("ankiwebUsername") private var username = ""
    @AppStorage("syncOnOpen") private var syncOnOpen = false
    @AppStorage("autoSyncInterval") private var autoSyncInterval = 0

    private let syncIntervals = [
        (0, "Never"),
        (15, "Every 15 minutes"),
        (30, "Every 30 minutes"),
        (60, "Every hour")
    ]

    var body: some View {
        Form {
            Section("AnkiWeb Account") {
                TextField("Email / Username", text: $username)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Sync Options") {
                Toggle("Sync on open", isOn: $syncOnOpen)

                Picker("Auto-sync interval", selection: $autoSyncInterval) {
                    ForEach(syncIntervals, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SyncSettingsView()
}
