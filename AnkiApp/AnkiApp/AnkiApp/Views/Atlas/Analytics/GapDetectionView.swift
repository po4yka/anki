import SwiftUI
import AppleBridgeCore
import AppleSharedUI

struct GapDetectionView: View {
    @Bindable var model: AnalyticsModel

    var body: some View {
        VStack {
            if model.gaps.isEmpty, !model.isLoading {
                ContentUnavailableView(
                    "No Gaps Detected",
                    systemImage: "checkmark.circle",
                    description: Text("Your knowledge coverage looks complete.")
                )
            } else {
                List(model.gaps) { gap in
                    GapRow(gap: gap)
                }
            }
        }
        .task {
            if model.gaps.isEmpty {
                await model.loadGaps(topicPath: model.selectedTopicPath ?? "")
            }
        }
    }
}

private struct GapRow: View {
    let gap: TopicGap

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(gap.path)
                    .font(.body)
                Text("\(gap.noteCount) notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            GapKindBadge(kind: gap.gapType.rawValue)
        }
        .padding(.vertical, 4)
    }
}

private struct GapKindBadge: View {
    let kind: String

    var color: Color {
        switch kind.lowercased() {
            case "missing": .red
            case "undercovered": .orange
            default: .secondary
        }
    }

    var body: some View {
        Text(kind)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
