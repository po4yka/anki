import SwiftUI

struct PreferencesView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("collectionPath") private var collectionPath = ""

    var body: some View {
        Form {
            Section("Collection") {
                HStack {
                    TextField("Collection Path", text: $collectionPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose...") {
                        chooseCollectionPath()
                    }
                }
                .padding(.vertical, 4)

                Button("Open Collection") {
                    guard !collectionPath.isEmpty else { return }
                    Task { await appState.openCollection(at: collectionPath) }
                }
                .disabled(collectionPath.isEmpty)

                if appState.isCollectionOpen {
                    Button("Close Collection", role: .destructive) {
                        Task { await appState.closeCollection() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Preferences")
        .frame(minWidth: 450, minHeight: 200)
    }

    private func chooseCollectionPath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "anki2")!]
        if panel.runModal() == .OK {
            collectionPath = panel.url?.path ?? ""
        }
    }
}

#Preview {
    PreferencesView()
        .environment(AppState())
}
