import SwiftUI

struct BackupSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isBackingUp = false
    @State private var backupResult: String?
    @State private var prefs: Anki_Config_Preferences?
    @State private var dailyLimit: UInt32 = 5
    @State private var weeklyLimit: UInt32 = 4
    @State private var monthlyLimit: UInt32 = 12
    @State private var minimumIntervalMins: UInt32 = 30

    var body: some View {
        Form {
            Section("Manual Backup") {
                HStack {
                    Button("Create Backup Now") {
                        Task { await createBackup() }
                    }
                    .disabled(!appState.isCollectionOpen || isBackingUp)

                    if isBackingUp {
                        ProgressView()
                            .controlSize(.small)
                        Text("Backing up...")
                            .foregroundStyle(.secondary)
                    }
                }

                if let backupResult {
                    Text(backupResult)
                        .foregroundStyle(backupResult.contains("Error") ? .red : .green)
                        .font(.caption)
                }
            }

            Section("Backup Limits") {
                Stepper("Daily backups: \(dailyLimit)", value: $dailyLimit, in: 0...30)
                Stepper("Weekly backups: \(weeklyLimit)", value: $weeklyLimit, in: 0...30)
                Stepper("Monthly backups: \(monthlyLimit)", value: $monthlyLimit, in: 0...30)
                Stepper("Minimum interval (minutes): \(minimumIntervalMins)", value: $minimumIntervalMins, in: 5...1440, step: 5)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save Backup Settings") {
                        Task { await saveBackupSettings() }
                    }
                    .disabled(prefs == nil)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await loadPreferences() }
    }

    private func createBackup() async {
        guard appState.isCollectionOpen else { return }
        isBackingUp = true
        backupResult = nil
        do {
            let backupFolder = (appState.collectionPath as NSString).deletingLastPathComponent + "/backups"
            let _ = try await appState.service.createBackup(
                backupFolder: backupFolder,
                force: true,
                waitForCompletion: true
            )
            backupResult = "Backup created successfully."
        } catch {
            backupResult = "Error: \(error.localizedDescription)"
        }
        isBackingUp = false
    }

    private func loadPreferences() async {
        do {
            let p = try await appState.service.getPreferences()
            prefs = p
            dailyLimit = p.backups.daily
            weeklyLimit = p.backups.weekly
            monthlyLimit = p.backups.monthly
            minimumIntervalMins = p.backups.minimumIntervalMins
        } catch {}
    }

    private func saveBackupSettings() async {
        guard var p = prefs else { return }
        p.backups.daily = dailyLimit
        p.backups.weekly = weeklyLimit
        p.backups.monthly = monthlyLimit
        p.backups.minimumIntervalMins = minimumIntervalMins
        do {
            try await appState.service.setPreferences(prefs: p)
            prefs = p
        } catch {}
    }
}

#Preview {
    BackupSettingsView()
        .environment(AppState())
}
