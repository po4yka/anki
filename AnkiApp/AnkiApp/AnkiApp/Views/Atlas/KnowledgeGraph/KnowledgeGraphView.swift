import SwiftUI

struct KnowledgeGraphView: View {
    @Environment(AppState.self) private var appState
    @State private var concepts: [Concept] = []
    @State private var selectedConcept: Concept?
    @State private var isLoading = false
    @State private var searchText = ""

    struct Concept: Identifiable, Hashable {
        let id: Int64
        let name: String
        let tags: [String]
        var relatedIds: [Int64] = []
    }

    var filteredConcepts: [Concept] {
        if searchText.isEmpty { return concepts }
        return concepts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        HSplitView {
            conceptListView
                .frame(minWidth: 200, idealWidth: 250)

            detailView
                .frame(minWidth: 300)
        }
        .task { await loadConcepts() }
    }

    private var conceptListView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search concepts...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading concepts...")
                Spacer()
            } else if filteredConcepts.isEmpty {
                Spacer()
                Text("No concepts found")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filteredConcepts, selection: $selectedConcept) { concept in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(concept.name)
                            .font(.body)
                        if !concept.tags.isEmpty {
                            Text(concept.tags.prefix(3).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(concept)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var detailView: some View {
        VStack {
            if let concept = selectedConcept {
                VStack(alignment: .leading, spacing: 12) {
                    Text(concept.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    if !concept.tags.isEmpty {
                        Section {
                            FlowLayout(spacing: 4) {
                                ForEach(concept.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.fill.tertiary)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        } header: {
                            Text("Tags")
                                .font(.headline)
                        }
                    }

                    let related = concepts.filter { concept.relatedIds.contains($0.id) }
                    if !related.isEmpty {
                        Section {
                            ForEach(related) { rel in
                                Button {
                                    selectedConcept = rel
                                } label: {
                                    HStack {
                                        Image(systemName: "link")
                                        Text(rel.name)
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)
                            }
                        } header: {
                            Text("Related Concepts")
                                .font(.headline)
                        }
                    }

                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Select a concept to view details")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadConcepts() async {
        guard appState.isCollectionOpen else { return }
        isLoading = true
        do {
            let tags = try await appState.service.allTags()
            var builtConcepts: [Concept] = []
            let allTags = tags.vals
            let topLevelTags = Set(allTags.map { $0.components(separatedBy: "::").first ?? $0 })

            for (index, tagName) in topLevelTags.sorted().enumerated() {
                let childTags = allTags.filter { $0.hasPrefix(tagName + "::") || $0 == tagName }
                let relatedIndices = builtConcepts.indices.filter { i in
                    builtConcepts[i].tags.contains(where: { childTags.contains($0) })
                }
                builtConcepts.append(Concept(
                    id: Int64(index),
                    name: tagName,
                    tags: childTags.sorted(),
                    relatedIds: relatedIndices.map { Int64($0) }
                ))
            }
            concepts = builtConcepts
        } catch {}
        isLoading = false
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}

#Preview {
    KnowledgeGraphView()
        .environment(AppState())
        .frame(width: 600, height: 400)
}
