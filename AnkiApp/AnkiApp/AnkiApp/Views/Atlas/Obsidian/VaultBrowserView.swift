import AppKit
import SwiftUI

struct VaultBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var model: ObsidianModel?

    var body: some View {
        guard let atlas = appState.atlasService else {
            return AnyView(ContentUnavailableView(
                "Atlas Not Configured",
                systemImage: "folder.badge.questionmark",
                description: Text("Configure Atlas in Settings to use Obsidian integration.")
            ))
        }
        let obsidianModel = model ?? ObsidianModel(atlas: atlas)
        return AnyView(VaultBrowserContentView(model: obsidianModel)
            .onAppear {
                if model == nil { model = obsidianModel }
            })
    }
}

private struct VaultBrowserContentView: View {
    @State var model: ObsidianModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let path = model.vaultPath {
                    Text(path.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No vault selected")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select Vault") {
                    selectVault()
                }
            }
            .padding()

            if model.isScanning {
                ProgressView("Scanning vault...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let preview = model.scanPreview {
                List(preview.notes) { note in
                    ObsidianNoteRow(note: note)
                }
            } else {
                ContentUnavailableView(
                    "Select a Vault",
                    systemImage: "folder",
                    description: Text("Choose an Obsidian vault folder to scan its notes.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Obsidian Vault")
    }

    private func selectVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Vault"

        if panel.runModal() == .OK, let url = panel.url {
            model.vaultPath = url
            Task { await model.scan() }
        }
    }
}

private struct ObsidianNoteRow: View {
    let note: ObsidianNotePreview

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.body)
                Text("\(note.sectionCount) sections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(note.generatedCardCount) cards")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}
