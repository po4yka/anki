import SwiftUI
import UniformTypeIdentifiers
import AppleBridgeCore
import AppleSharedUI

struct PreferencesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView(selection: Binding(
            get: { appState.selectedPreferencesTab },
            set: { appState.selectedPreferencesTab = $0 }
        )) {
            GeneralSettingsView()
                .environment(appState)
                .tabItem { Label("General", systemImage: "gear") }
                .tag(PreferencesTab.general)
            SchedulingPreferencesView()
                .environment(appState)
                .tabItem { Label("Scheduling", systemImage: "calendar") }
                .tag(PreferencesTab.scheduling)
            ReviewPreferencesView()
                .environment(appState)
                .tabItem { Label("Review", systemImage: "rectangle.stack") }
                .tag(PreferencesTab.review)
            BackupSettingsView()
                .environment(appState)
                .tabItem { Label("Backups", systemImage: "externaldrive") }
                .tag(PreferencesTab.backups)
            ProfilesSettingsView()
                .environment(appState)
                .tabItem { Label("Profiles", systemImage: "person.2") }
                .tag(PreferencesTab.profiles)
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(PreferencesTab.appearance)
            SyncSettingsView()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                .tag(PreferencesTab.sync)
            AtlasSettingsView()
                .environment(appState)
                .tabItem { Label("Atlas", systemImage: "brain") }
                .tag(PreferencesTab.atlas)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(PreferencesTab.about)
        }
        .frame(width: 500, height: 450)
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

            Section("Text-to-Speech") {
                Toggle("Enable TTS playback", isOn: Binding(
                    get: { appState.ttsSettings.isEnabled },
                    set: { appState.ttsSettings.isEnabled = $0 }
                ))
                Toggle("Auto-play TTS on card show", isOn: Binding(
                    get: { appState.ttsSettings.autoPlay },
                    set: { appState.ttsSettings.autoPlay = $0 }
                ))
                .disabled(!appState.ttsSettings.isEnabled)
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
            await appState.refreshReviewPreferences()
        } catch {}
    }
}

struct ProfilesSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var profileManager = ProfileManager()
    @State private var newProfileName = ""
    @State private var newProfilePath = ""
    @State private var showingProfilePicker = false

    var body: some View {
        Form {
            Section(isLocalIOSMode ? "Local Profiles" : "Profiles") {
                if profileManager.profiles.isEmpty {
                    Text("No profiles configured")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(profileManager.profiles) { profile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                        .fontWeight(profile.id == profileManager.activeProfileID ? .bold : .regular)
                                    Text(profile.displayPath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if profile.id == profileManager.activeProfileID {
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

            if isLocalIOSMode {
                Section("Import Local Profile") {
                    TextField("Profile Name", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                    Button("Import Collection") {
                        chooseProfilePath()
                    }
                }
            } else {
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
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(
            isPresented: $showingProfilePicker,
            // swiftlint:disable:next force_unwrapping
            allowedContentTypes: [.init(filenameExtension: "anki2")!],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                return
            }
            if isLocalIOSMode {
                do {
                    let trimmedName = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let profile = try profileManager.importLocalProfile(
                        from: url,
                        name: trimmedName.isEmpty ? nil : trimmedName
                    )
                    profileManager.setActive(profileID: profile.id)
                    newProfileName = ""
                } catch {
                    appState.error = .message("Failed to import local profile: \(error.localizedDescription)")
                }
            } else {
                newProfilePath = url.path
            }
        }
    }

    private var isLocalIOSMode: Bool {
        #if os(iOS)
        appState.connectionStore?.selectedExecutionMode == .local
        #else
        false
        #endif
    }

    private func chooseProfilePath() {
        showingProfilePicker = true
    }
}

#Preview {
    PreferencesView()
        .environment(AppState())
}
