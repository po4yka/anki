import SwiftUI

struct ImportView: View {
    @Environment(AppState.self) private var appState
    @State private var importModel: ImportModel?

    var body: some View {
        VStack(spacing: 20) {
            if let model = importModel {
                importContent(model)
            } else {
                ProgressView()
                    .onAppear {
                        importModel = ImportModel(service: appState.service)
                    }
            }
        }
        .padding()
        .navigationTitle("Import")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func importContent(_ model: ImportModel) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Import Anki Package")
                .font(.title2)

            VStack(alignment: .leading, spacing: 12) {
                Text("Options")
                    .font(.headline)

                Toggle("Merge notetypes", isOn: Binding(
                    get: { model.options.mergeNotetypes },
                    set: { model.options.mergeNotetypes = $0 }
                ))

                Toggle("Include scheduling", isOn: Binding(
                    get: { model.options.withScheduling },
                    set: { model.options.withScheduling = $0 }
                ))

                Toggle("Include deck configs", isOn: Binding(
                    get: { model.options.withDeckConfigs },
                    set: { model.options.withDeckConfigs = $0 }
                ))

                Picker("Update notes", selection: Binding(
                    get: { model.options.updateNotes },
                    set: { model.options.updateNotes = $0 }
                )) {
                    Text("If newer").tag(Anki_ImportExport_ImportAnkiPackageUpdateCondition.ifNewer)
                    Text("Always").tag(Anki_ImportExport_ImportAnkiPackageUpdateCondition.always)
                    Text("Never").tag(Anki_ImportExport_ImportAnkiPackageUpdateCondition.never)
                }

                Picker("Update notetypes", selection: Binding(
                    get: { model.options.updateNotetypes },
                    set: { model.options.updateNotetypes = $0 }
                )) {
                    Text("If newer").tag(Anki_ImportExport_ImportAnkiPackageUpdateCondition.ifNewer)
                    Text("Always").tag(Anki_ImportExport_ImportAnkiPackageUpdateCondition.always)
                    Text("Never").tag(Anki_ImportExport_ImportAnkiPackageUpdateCondition.never)
                }
            }
            .frame(maxWidth: 400)

            Button(action: { selectAndImport(model) }, label: {
                Label("Choose .apkg File...", systemImage: "doc.badge.plus")
            })
            .buttonStyle(.borderedProminent)
            .disabled(model.isImporting)

            if model.isImporting {
                ProgressView("Importing...")
            }

            if let result = model.importResult {
                GroupBox("Import Results") {
                    VStack(alignment: .leading, spacing: 6) {
                        resultRow("Found notes", count: Int(result.foundNotes))
                        resultRow("New", count: result.newNotes)
                        resultRow("Updated", count: result.updatedNotes)
                        resultRow("Duplicates", count: result.duplicateNotes)
                        resultRow("Conflicting", count: result.conflictingNotes)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: 400)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    private func resultRow(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
        }
    }

    private func selectAndImport(_ model: ImportModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "apkg")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an Anki package to import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await model.importPackage(path: url.path)
        }
    }
}

#Preview {
    ImportView()
        .environment(AppState())
}
