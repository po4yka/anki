import SwiftUI

struct ExportView: View {
    @Environment(AppState.self) private var appState
    @State private var exportModel: ExportModel?

    var body: some View {
        VStack(spacing: 20) {
            if let model = exportModel {
                exportContent(model)
            } else {
                ProgressView()
                    .onAppear {
                        exportModel = ExportModel(service: appState.service)
                    }
            }
        }
        .padding()
        .navigationTitle("Export")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // swiftlint:disable:next function_body_length
    private func exportContent(_ model: ExportModel) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Export Anki Package")
                .font(.title2)

            VStack(alignment: .leading, spacing: 12) {
                Text("Scope")
                    .font(.headline)

                Picker("Export scope", selection: Binding(
                    get: { model.exportScope == .wholeCollection },
                    set: { isWholeCollection in
                        if isWholeCollection {
                            model.exportScope = .wholeCollection
                        } else {
                            let id = model.selectedDeckId
                            let name = model.availableDecks.first { $0.id == id }?.name ?? ""
                            model.exportScope = .deck(id: id, name: name)
                        }
                    }
                )) {
                    Text("Whole Collection").tag(true)
                    Text("Single Deck").tag(false)
                }
                .pickerStyle(.segmented)

                if model.exportScope != .wholeCollection {
                    Picker("Deck", selection: Binding(
                        get: { model.selectedDeckId },
                        set: { id in
                            model.selectedDeckId = id
                            let name = model.availableDecks.first { $0.id == id }?.name ?? ""
                            model.exportScope = .deck(id: id, name: name)
                        }
                    )) {
                        ForEach(model.availableDecks, id: \.id) { deck in
                            Text(deck.name).tag(deck.id)
                        }
                    }
                }

                Text("Options")
                    .font(.headline)
                    .padding(.top, 8)

                Toggle("Include scheduling", isOn: Binding(
                    get: { model.options.withScheduling },
                    set: { model.options.withScheduling = $0 }
                ))

                Toggle("Include deck configs", isOn: Binding(
                    get: { model.options.withDeckConfigs },
                    set: { model.options.withDeckConfigs = $0 }
                ))

                Toggle("Include media", isOn: Binding(
                    get: { model.options.withMedia },
                    set: { model.options.withMedia = $0 }
                ))

                Toggle("Legacy format (.anki2)", isOn: Binding(
                    get: { model.options.legacy },
                    set: { model.options.legacy = $0 }
                ))
            }
            .frame(maxWidth: 400)

            Button(action: { selectAndExport(model) }, label: {
                Label("Export .apkg File...", systemImage: "square.and.arrow.up")
            })
            .buttonStyle(.borderedProminent)
            .disabled(model.isExporting)

            if model.isExporting {
                ProgressView("Exporting...")
            }

            if let count = model.exportedCount {
                Label("Exported \(count) cards", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    private func selectAndExport(_ model: ExportModel) {
        let panel = NSSavePanel()
        // swiftlint:disable:next force_unwrapping
        panel.allowedContentTypes = [.init(filenameExtension: "apkg")!]
        panel.nameFieldStringValue = "collection.apkg"
        panel.message = "Choose where to save the exported package"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await model.exportPackage(outPath: url.path)
        }
    }
}

#Preview {
    ExportView()
        .environment(AppState())
}
