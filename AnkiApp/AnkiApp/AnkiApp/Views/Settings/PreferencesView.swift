import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environment(appState)
                .tabItem { Label("General", systemImage: "gear") }
            SchedulingPreferencesView()
                .environment(appState)
                .tabItem { Label("Scheduling", systemImage: "calendar") }
            ReviewPreferencesView()
                .environment(appState)
                .tabItem { Label("Review", systemImage: "rectangle.stack") }
            BackupSettingsView()
                .environment(appState)
                .tabItem { Label("Backups", systemImage: "externaldrive") }
            ProfilesSettingsView()
                .environment(appState)
                .tabItem { Label("Profiles", systemImage: "person.2") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            SyncSettingsView()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 400)
    }
}

struct SchedulingPreferencesView: View {
    @Environment(AppState.self) private var appState
    @State private var prefs: Anki_Config_Preferences?
    @State private var rollover: UInt32 = 4
    @State private var learnAheadSecs: UInt32 = 1200
    @State private var newReviewMix: Anki_Config_Preferences.Scheduling.NewReviewMix = .distribute
    @State private var dayLearnFirst: Bool = false

    var body: some View {
        Form {
            Section("Day Boundary") {
                Stepper("Next day starts at: \(rollover):00", value: $rollover, in: 0 ... 23)
                    .help("Hour at which the next day starts (default 4 AM)")
            }

            Section("Learn Ahead") {
                let minutes = learnAheadSecs / 60
                Stepper("Learn ahead limit: \(minutes) minutes", value: $learnAheadSecs, in: 0 ... 7200, step: 60)
            }

            Section("Card Order") {
                Picker("New/review order", selection: $newReviewMix) {
                    Text("Show mixed").tag(Anki_Config_Preferences.Scheduling.NewReviewMix.distribute)
                    Text("Show reviews first").tag(Anki_Config_Preferences.Scheduling.NewReviewMix.reviewsFirst)
                    Text("Show new first").tag(Anki_Config_Preferences.Scheduling.NewReviewMix.newFirst)
                }
                Toggle("Show learning cards before reviews", isOn: $dayLearnFirst)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save") { Task { await savePreferences() } }
                        .disabled(prefs == nil)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await loadPreferences() }
    }

    private func loadPreferences() async {
        do {
            let preferences = try await appState.service.getPreferences()
            prefs = preferences
            rollover = preferences.scheduling.rollover
            learnAheadSecs = preferences.scheduling.learnAheadSecs
            newReviewMix = preferences.scheduling.newReviewMix
            dayLearnFirst = preferences.scheduling.dayLearnFirst
        } catch {}
    }

    private func savePreferences() async {
        guard var preferences = prefs else { return }
        preferences.scheduling.rollover = rollover
        preferences.scheduling.learnAheadSecs = learnAheadSecs
        preferences.scheduling.newReviewMix = newReviewMix
        preferences.scheduling.dayLearnFirst = dayLearnFirst
        do {
            try await appState.service.setPreferences(prefs: preferences)
            prefs = preferences
        } catch {}
    }
}

struct ReviewPreferencesView: View {
    @Environment(AppState.self) private var appState
    @State private var prefs: Anki_Config_Preferences?
    @State private var showRemainingDueCounts: Bool = false
    @State private var showIntervalsOnButtons: Bool = false
    @State private var hideAudioPlayButtons: Bool = false
    @State private var interruptAudioWhenAnswering: Bool = false
    @State private var timeLimitSecs: UInt32 = 0

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Show remaining due counts", isOn: $showRemainingDueCounts)
                Toggle("Show intervals on answer buttons", isOn: $showIntervalsOnButtons)
            }

            Section("Audio") {
                Toggle("Hide audio play buttons", isOn: $hideAudioPlayButtons)
                Toggle("Interrupt audio when answering", isOn: $interruptAudioWhenAnswering)
            }

            Section("Time Limit") {
                let minutes = timeLimitSecs / 60
                Stepper("Time limit per card: \(minutes) min", value: $timeLimitSecs, in: 0 ... 3600, step: 60)
                    .help("0 means no limit")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save") { Task { await savePreferences() } }
                        .disabled(prefs == nil)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await loadPreferences() }
    }

    private func loadPreferences() async {
        do {
            let preferences = try await appState.service.getPreferences()
            prefs = preferences
            showRemainingDueCounts = preferences.reviewing.showRemainingDueCounts
            showIntervalsOnButtons = preferences.reviewing.showIntervalsOnButtons
            hideAudioPlayButtons = preferences.reviewing.hideAudioPlayButtons
            interruptAudioWhenAnswering = preferences.reviewing.interruptAudioWhenAnswering
            timeLimitSecs = preferences.reviewing.timeLimitSecs
        } catch {}
    }

    private func savePreferences() async {
        guard var preferences = prefs else { return }
        preferences.reviewing.showRemainingDueCounts = showRemainingDueCounts
        preferences.reviewing.showIntervalsOnButtons = showIntervalsOnButtons
        preferences.reviewing.hideAudioPlayButtons = hideAudioPlayButtons
        preferences.reviewing.interruptAudioWhenAnswering = interruptAudioWhenAnswering
        preferences.reviewing.timeLimitSecs = timeLimitSecs
        do {
            try await appState.service.setPreferences(prefs: preferences)
            prefs = preferences
        } catch {}
    }
}

struct ProfilesSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var profileManager = ProfileManager()
    @State private var newProfileName = ""
    @State private var newProfilePath = ""

    var body: some View {
        Form {
            Section("Profiles") {
                if profileManager.profiles.isEmpty {
                    Text("No profiles configured")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(profileManager.profiles) { profile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                        .fontWeight(profile.path == profileManager.activeProfilePath ? .bold : .regular)
                                    Text(profile.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if profile.path == profileManager.activeProfilePath {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Button("Switch") {
                                        Task {
                                            await profileManager.switchProfile(to: profile, appState: appState)
                                        }
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            profileManager.removeProfile(at: offsets)
                        }
                    }
                    .frame(minHeight: 80)
                }
            }

            Section("Add Profile") {
                TextField("Profile Name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Collection Path", text: $newProfilePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") { chooseProfilePath() }
                }
                Button("Add Profile") {
                    guard !newProfileName.isEmpty, !newProfilePath.isEmpty else { return }
                    profileManager.addProfile(name: newProfileName, path: newProfilePath)
                    newProfileName = ""
                    newProfilePath = ""
                }
                .disabled(newProfileName.isEmpty || newProfilePath.isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseProfilePath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "anki2")!]
        if panel.runModal() == .OK {
            newProfilePath = panel.url?.path ?? ""
        }
    }
}

#Preview {
    PreferencesView()
        .environment(AppState())
}
