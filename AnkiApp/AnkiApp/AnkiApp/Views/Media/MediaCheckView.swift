import SwiftUI

struct MediaCheckView: View {
    @Environment(AppState.self) private var appState
    @State private var model: MediaCheckModel?

    var body: some View {
        VStack(spacing: 20) {
            if let model {
                mediaContent(model)
            } else {
                ProgressView()
                    .onAppear {
                        model = MediaCheckModel(service: appState.service)
                    }
            }
        }
        .padding()
        .navigationTitle("Media Check")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func mediaContent(_ model: MediaCheckModel) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Check Media Files")
                .font(.title2)

            Button(action: {
                Task { await model.checkMedia() }
            }) {
                Label("Check Media", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isChecking || model.isProcessing)

            if model.isChecking {
                ProgressView("Checking media...")
            }

            if model.isProcessing {
                ProgressView("Processing...")
            }

            if let result = model.checkResult {
                resultsSection(model, result: result)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func resultsSection(_ model: MediaCheckModel, result: MediaCheckModel.CheckResult) -> some View {
        GroupBox("Results") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Unused files")
                    Spacer()
                    Text("\(result.unused.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Missing files")
                    Spacer()
                    Text("\(result.missing.count)")
                        .foregroundStyle(.secondary)
                }

                if !result.report.isEmpty {
                    Divider()
                    Text(result.report)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: 400)

        HStack(spacing: 12) {
            if !result.unused.isEmpty {
                Button(action: {
                    Task { await model.trashUnused() }
                }) {
                    Label("Trash Unused", systemImage: "trash")
                }
                .disabled(model.isProcessing)
            }

            if result.haveTrash {
                Button(action: {
                    Task { await model.restoreTrash() }
                }) {
                    Label("Restore Trash", systemImage: "arrow.uturn.backward")
                }
                .disabled(model.isProcessing)

                Button(role: .destructive, action: {
                    Task { await model.emptyTrash() }
                }) {
                    Label("Empty Trash", systemImage: "trash.slash")
                }
                .disabled(model.isProcessing)
            }
        }
    }
}

#Preview {
    MediaCheckView()
        .environment(AppState())
}
