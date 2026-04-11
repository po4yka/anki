import AppleBridgeCore
import AppleSharedUI
import SwiftUI

struct DuplicatesView: View {
    @Bindable var model: AnalyticsModel
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack {
            if model.duplicateClusters.isEmpty, !model.isLoading {
                ContentUnavailableView(
                    "No Duplicates Found",
                    systemImage: "doc.on.doc",
                    description: Text("No duplicate notes detected above the similarity threshold.")
                )
            } else {
                List(model.duplicateClusters) { cluster in
                    ClusterRow(cluster: cluster) { noteId in
                        await deleteNote(noteId)
                    }
                }
            }
        }
        .task {
            if model.duplicateClusters.isEmpty {
                await model.loadDuplicates()
            }
        }
    }

    private func deleteNote(_ noteId: Int64) async {
        do {
            _ = try await appState.service.removeNotes(noteIds: [noteId], cardIds: [])
            await model.loadDuplicates()
        } catch {
            model.error = error.localizedDescription
        }
    }
}

private struct ClusterRow: View {
    let cluster: DuplicateCluster
    let onDelete: (Int64) async -> Void
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(cluster.duplicates) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.text)
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.0f%%", item.similarity * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await onDelete(item.noteId) }
                    } label: {
                        Label("Delete Note", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await onDelete(item.noteId) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } label: {
            HStack {
                Text(cluster.representativeText)
                    .lineLimit(1)
                Spacer()
                Text("\(cluster.duplicates.count) duplicates")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
