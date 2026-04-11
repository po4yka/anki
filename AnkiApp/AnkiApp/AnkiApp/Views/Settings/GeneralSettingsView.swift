import SwiftUI
import UniformTypeIdentifiers
import AppleBridgeCore
import AppleSharedUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("collectionPath") private var collectionPath = ""
    @AppStorage("language") private var language = "en"
    @State private var showingCollectionPicker = false
    @State private var profileManager = ProfileManager()

    private let languages = [
        ("en", "English"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("fr", "Français"),
        ("it", "Italiano"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("nl", "Nederlands"),
        ("pl", "Polski"),
        ("pt", "Português"),
        ("ru", "Русский"),
        ("zh", "中文")
    ]

    var body: some View {
        Form {
            Section("Collection") {
                if isLocalIOSMode {
                    if let activeProfile = profileManager.activeProfile {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(activeProfile.name)
                                .font(.headline)
                            Text(activeProfile.displayPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Import a collection to create an on-device local profile.")
                            .foregroundStyle(.secondary)
                    }

                    Button("Import Local Collection") {
                        chooseCollectionPath()
                    }

                    if appState.isCollectionOpen {
                        Button("Close Collection", role: .destructive) {
                            Task { await appState.closeCollection() }
                        }
                    } else {
                        Button("Open Active Local Profile") {
                            guard let activeProfile = profileManager.activeProfile else { return }
                            Task { await profileManager.switchProfile(to: activeProfile, appState: appState) }
                        }
                        .disabled(profileManager.activeProfile == nil)
                    }
                } else {
                    HStack {
                        TextField("Collection Path", text: $collectionPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            chooseCollectionPath()
                        }
                    }

                    if appState.isCollectionOpen {
                        Button("Close Collection", role: .destructive) {
                            Task { await appState.closeCollection() }
                        }
                    } else {
                        Button("Open Collection") {
                            guard !collectionPath.isEmpty else { return }
                            Task { await appState.openCollection(path: collectionPath) }
                        }
                        .disabled(collectionPath.isEmpty)
                    }
                }
            }

            Section("Language") {
                Picker("Interface Language", selection: $language) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                Text("Language changes apply the next time the app starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(
            isPresented: $showingCollectionPicker,
            // swiftlint:disable:next force_unwrapping
            allowedContentTypes: [.init(filenameExtension: "anki2")!],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                return
            }
            if isLocalIOSMode {
                do {
                    let profile = try profileManager.importLocalProfile(from: url)
                    profileManager.setActive(profileID: profile.id)
                } catch {
                    appState.error = .message("Failed to import local collection: \(error.localizedDescription)")
                }
            } else {
                collectionPath = url.path
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

    private func chooseCollectionPath() {
        showingCollectionPicker = true
    }
}

#Preview {
    GeneralSettingsView()
        .environment(AppState())
}
