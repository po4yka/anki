import SwiftUI

struct SeeAlsoNotesView: View {
    let atlas: any AtlasServiceProtocol
    let noteId: Int64
    let onOpenNote: (Int64) -> Void

    @State private var model: NoteLinksModel

    init(
        atlas: any AtlasServiceProtocol,
        noteId: Int64,
        onOpenNote: @escaping (Int64) -> Void
    ) {
        self.atlas = atlas
        self.noteId = noteId
        self.onOpenNote = onOpenNote
        _model = State(initialValue: NoteLinksModel(atlas: atlas))
    }

    var body: some View {
        Group {
            if model.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading related notes...")
                        .foregroundStyle(.secondary)
                }
            } else if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else if model.relatedNotes.isEmpty {
                Text("No related notes yet.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(model.relatedNotes) { link in
                    Button {
                        onOpenNote(link.noteId)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top) {
                                Text(link.textPreview)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Text(String(format: "%.2f", link.weight))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 6) {
                                if let deckName = link.deckNames.first, !deckName.isEmpty {
                                    MetadataBadge(text: deckName, color: .blue)
                                }
                                MetadataBadge(text: link.edgeSource.rawValue.replacingOccurrences(of: "_", with: " "), color: .green)
                                if let tag = link.tags.first, !tag.isEmpty {
                                    MetadataBadge(text: "#\(tag)", color: .orange)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: noteId) {
            await model.load(noteId: noteId)
        }
    }
}

struct MetadataBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
