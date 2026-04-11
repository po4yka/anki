import AppleBridgeCore
import AppleSharedUI
import SwiftUI

struct WeakNotesView: View {
    @Bindable var model: AnalyticsModel

    var body: some View {
        VStack {
            if model.weakNotes.isEmpty, !model.isLoading {
                ContentUnavailableView(
                    "No Weak Notes",
                    systemImage: "checkmark.seal",
                    description: Text("All notes have sufficient confidence.")
                )
            } else {
                List(model.weakNotes) { note in
                    WeakNoteRow(note: note)
                }
            }
        }
        .task {
            if model.weakNotes.isEmpty {
                await model.loadWeakNotes(topicPath: model.selectedTopicPath ?? "")
            }
        }
    }
}

private struct WeakNoteRow: View {
    let note: WeakNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.normalizedText)
                .lineLimit(2)
                .font(.body)
            HStack {
                ProgressView(value: note.confidence, total: 1.0)
                    .frame(width: 80)
                Text(String(format: "%.0f%%", note.confidence * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !note.topicPath.isEmpty {
                    Text(note.topicPath)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
