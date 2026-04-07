import SwiftUI

struct CsvImportView: View {
    @Environment(AppState.self) private var appState
    @State private var model: CsvImportModel?
    @State private var filePath: String?

    var body: some View {
        VStack(spacing: 20) {
            if let model {
                csvContent(model)
            } else {
                ProgressView()
                    .onAppear {
                        model = CsvImportModel(service: appState.service)
                    }
            }
        }
        .padding()
        .navigationTitle("Import CSV")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func csvContent(_ model: CsvImportModel) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "tablecells")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Import CSV File")
                .font(.title2)

            Button(action: { selectFile(model) }) {
                Label("Choose CSV File...", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isLoading || model.isImporting)

            if model.isLoading {
                ProgressView("Loading metadata...")
            }

            if let metadata = model.metadata, let path = filePath {
                metadataSection(model, metadata: metadata)
                previewSection(metadata)
                importButton(model, path: path)
            }

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

    @ViewBuilder
    private func metadataSection(_ model: CsvImportModel, metadata: Anki_ImportExport_CsvMetadata) -> some View {
        GroupBox("Options") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Delimiter", selection: Binding(
                    get: { model.selectedDelimiter },
                    set: { newValue in
                        model.selectedDelimiter = newValue
                        if let path = filePath {
                            Task { await model.reloadMetadata(path: path) }
                        }
                    }
                )) {
                    Text("Tab").tag(Anki_ImportExport_CsvMetadata.Delimiter.tab)
                    Text("Comma").tag(Anki_ImportExport_CsvMetadata.Delimiter.comma)
                    Text("Semicolon").tag(Anki_ImportExport_CsvMetadata.Delimiter.semicolon)
                    Text("Colon").tag(Anki_ImportExport_CsvMetadata.Delimiter.colon)
                    Text("Pipe").tag(Anki_ImportExport_CsvMetadata.Delimiter.pipe)
                    Text("Space").tag(Anki_ImportExport_CsvMetadata.Delimiter.space)
                }

                Toggle("HTML", isOn: Binding(
                    get: { model.isHtml },
                    set: { model.isHtml = $0 }
                ))

                Picker("Duplicate handling", selection: Binding(
                    get: { model.dupeResolution },
                    set: { model.dupeResolution = $0 }
                )) {
                    Text("Update existing").tag(Anki_ImportExport_CsvMetadata.DupeResolution.update)
                    Text("Preserve existing").tag(Anki_ImportExport_CsvMetadata.DupeResolution.preserve)
                    Text("Import as duplicate").tag(Anki_ImportExport_CsvMetadata.DupeResolution.duplicate)
                }

                if !metadata.columnLabels.isEmpty {
                    Text("Columns: \(metadata.columnLabels.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: 400)
    }

    @ViewBuilder
    private func previewSection(_ metadata: Anki_ImportExport_CsvMetadata) -> some View {
        if !metadata.preview.isEmpty {
            GroupBox("Preview") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(metadata.preview.prefix(5).enumerated()), id: \.offset) { _, row in
                        Text(row.vals.joined(separator: " | "))
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 400)
        }
    }

    private func importButton(_ model: CsvImportModel, path: String) -> some View {
        Button(action: {
            Task { await model.importCsv(path: path) }
        }) {
            Label("Import", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isImporting)
    }

    private func resultRow(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
        }
    }

    private func selectFile(_ model: CsvImportModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "csv")!,
            .init(filenameExtension: "tsv")!,
            .init(filenameExtension: "txt")!,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a CSV file to import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        filePath = url.path
        Task {
            await model.loadMetadata(path: url.path)
        }
    }
}

#Preview {
    CsvImportView()
        .environment(AppState())
}
