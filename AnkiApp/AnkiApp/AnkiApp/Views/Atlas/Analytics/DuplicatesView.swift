import SwiftUI

struct DuplicatesView: View {
    @Bindable var model: AnalyticsModel

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
                    ClusterRow(cluster: cluster)
                }
            }
        }
        .task {
            if model.duplicateClusters.isEmpty {
                await model.loadDuplicates()
            }
        }
    }
}

private struct ClusterRow: View {
    let cluster: DuplicateCluster
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
