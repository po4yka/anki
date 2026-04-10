import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("collectionPath") private var collectionPath = ""
    @AppStorage("language") private var language = "en"

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
    }

    private func chooseCollectionPath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // swiftlint:disable:next force_unwrapping
        panel.allowedContentTypes = [.init(filenameExtension: "anki2")!]
        if panel.runModal() == .OK {
            collectionPath = panel.url?.path ?? ""
        }
    }
}

#Preview {
    GeneralSettingsView()
        .environment(AppState())
}
