import SwiftUI
import AppleBridgeCore
import AppleSharedUI

private extension TaxonomyNode {
    var childrenOrNil: [TaxonomyNode]? {
        children.isEmpty ? nil : children
    }
}

struct KnowledgeGraphView: View {
    @Environment(AppState.self) private var appState
    @State private var model: KnowledgeGraphModel?

    var body: some View {
        guard let atlas = appState.atlasService else {
            return AnyView(AtlasUnavailableView(
                featureName: "Knowledge Graph",
                systemImage: "point.3.connected.trianglepath.dotted"
            ))
        }

        let knowledgeGraphModel = model ?? KnowledgeGraphModel(atlas: atlas)
        return AnyView(KnowledgeGraphContentView(model: knowledgeGraphModel)
            .onAppear {
                if model == nil {
                    model = knowledgeGraphModel
                    Task { await knowledgeGraphModel.load() }
                }
            })
    }
}

private struct KnowledgeGraphContentView: View {
    @State var model: KnowledgeGraphModel

    var body: some View {
        Group {
#if os(macOS)
            HSplitView {
                List(model.taxonomyTree, children: \.childrenOrNil) { node in
                    KnowledgeGraphTaxonomyRow(
                        node: node,
                        isSelected: model.selectedTopicId == node.topicId
                    )
                    .onTapGesture {
                        Task { await model.selectTopic(node) }
                    }
                }
                .frame(minWidth: 240)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerCard

                        if model.error != nil, !model.isAtlasConfigured {
                            AtlasUnavailableView(
                                featureName: "Knowledge Graph",
                                systemImage: "point.3.connected.trianglepath.dotted"
                            )
                        } else if model.isLoading {
                            ProgressView("Loading knowledge graph...")
                                .frame(maxWidth: .infinity, minHeight: 280)
                        } else if !model.hasBuiltGraph {
                            ContentUnavailableView(
                                "No Graph Built Yet",
                                systemImage: "square.stack.3d.up",
                                description: Text(
                                    "Build the knowledge graph to discover related notes and topic neighborhoods."
                                )
                            )
                        } else if model.selectedTopicId == nil {
                            ContentUnavailableView(
                                "Select a Topic",
                                systemImage: "list.bullet.indent",
                                description: Text("Choose a topic from the taxonomy tree to inspect its neighborhood.")
                            )
                        } else if model.isLoadingNeighborhood {
                            ProgressView("Loading topic neighborhood...")
                                .frame(maxWidth: .infinity, minHeight: 280)
                        } else if let neighborhood = model.neighborhood {
                            TopicNeighborhoodDetails(model: model, neighborhood: neighborhood)
                        } else {
                            ContentUnavailableView(
                                "No Topic Data",
                                systemImage: "point.3.connected.trianglepath.dotted",
                                description: Text("The selected topic does not have any graph data yet.")
                            )
                        }
                    }
                    .padding()
                }
                .frame(minWidth: 420)
            }
#else
            ScrollView {
                VStack(spacing: 0) {
                    List(model.taxonomyTree, children: \.childrenOrNil) { node in
                        KnowledgeGraphTaxonomyRow(
                            node: node,
                            isSelected: model.selectedTopicId == node.topicId
                        )
                        .onTapGesture {
                            Task { await model.selectTopic(node) }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 16) {
                        headerCard

                        if model.error != nil, !model.isAtlasConfigured {
                            AtlasUnavailableView(
                                featureName: "Knowledge Graph",
                                systemImage: "point.3.connected.trianglepath.dotted"
                            )
                        } else if model.isLoading {
                            ProgressView("Loading knowledge graph...")
                                .frame(maxWidth: .infinity, minHeight: 280)
                        } else if !model.hasBuiltGraph {
                            ContentUnavailableView(
                                "No Graph Built Yet",
                                systemImage: "square.stack.3d.up",
                                description: Text(
                                    "Build the knowledge graph to discover related notes and topic neighborhoods."
                                )
                            )
                        } else if model.selectedTopicId == nil {
                            ContentUnavailableView(
                                "Select a Topic",
                                systemImage: "list.bullet.indent",
                                description: Text("Choose a topic from the taxonomy tree to inspect its neighborhood.")
                            )
                        } else if model.isLoadingNeighborhood {
                            ProgressView("Loading topic neighborhood...")
                                .frame(maxWidth: .infinity, minHeight: 280)
                        } else if let neighborhood = model.neighborhood {
                            TopicNeighborhoodDetails(model: model, neighborhood: neighborhood)
                        } else {
                            ContentUnavailableView(
                                "No Topic Data",
                                systemImage: "point.3.connected.trianglepath.dotted",
                                description: Text("The selected topic does not have any graph data yet.")
                            )
                        }
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
        }
        .navigationTitle("Knowledge Graph")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(model.hasBuiltGraph ? "Rebuild Graph" : "Build Graph") {
                    Task { await model.rebuild() }
                }
                .disabled(model.isRebuilding)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                statusBadge
                Spacer()
                if let status = model.status, let lastRefreshedAt = status.lastRefreshedAt {
                    Text("Updated \(lastRefreshedAt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let status = model.status {
                HStack(spacing: 12) {
                    StatPill(label: "Concept Edges", value: "\(status.conceptEdgeCount)")
                    StatPill(label: "Topic Edges", value: "\(status.topicEdgeCount)")
                    StatPill(
                        label: "Similarity",
                        value: status.similarityAvailable ? "Available" : "Unavailable"
                    )
                }

                if !status.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(status.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusBadge: some View {
        let text = model.hasBuiltGraph ? "Graph Ready" : "Build Required"
        let color: Color = model.hasBuiltGraph ? .green : .orange

        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

private struct KnowledgeGraphTaxonomyRow: View {
    let node: TaxonomyNode
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(node.label)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            Text("\(node.noteCount)")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
        }
        .contentShape(Rectangle())
    }
}

private struct TopicNeighborhoodDetails: View {
    let model: KnowledgeGraphModel
    let neighborhood: TopicNeighborhoodResponse

    private var groupedEdges: [(KnowledgeGraphEdgeType, [TopicEdgeView])] {
        let groups = Dictionary(grouping: neighborhood.edges, by: \.edgeType)
        return groups
            .map { ($0.key, $0.value.sorted { $0.weight > $1.weight }) }
            .sorted { $0.0.rawValue < $1.0.rawValue }
    }

    var body: some View {
        if neighborhood.edges.isEmpty {
            ContentUnavailableView(
                "No Connections Yet",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("The selected topic does not have any graph edges yet.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if let selectedTopicId = model.selectedTopicId,
                   let summary = model.topicSummary(for: selectedTopicId) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary.label)
                            .font(.title2.weight(.semibold))
                        Text(summary.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(summary.noteCount) linked notes in taxonomy coverage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(groupedEdges, id: \.0) { edgeType, edges in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(sectionTitle(for: edgeType))
                            .font(.headline)

                        ForEach(edges) { edge in
                            TopicEdgeRow(edge: edge, linkedTopic: model.linkedTopic(for: edge))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionTitle(for edgeType: KnowledgeGraphEdgeType) -> String {
        edgeType.rawValue
            .split(separator: "_")
            .map(\.capitalized)
            .joined(separator: " ")
    }
}

private struct TopicEdgeRow: View {
    let edge: TopicEdgeView
    let linkedTopic: TopicNodeSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(linkedTopic?.label ?? "Unknown Topic")
                        .font(.subheadline.weight(.medium))
                    Text(linkedTopic?.path ?? "No path available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(String(format: "%.2f", edge.weight))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(edge.weight), total: 1.0)

            HStack(spacing: 6) {
                MetadataBadge(text: edge.edgeSource.rawValue.replacingOccurrences(of: "_", with: " "), color: .green)
                if let linkedTopic {
                    MetadataBadge(text: "\(linkedTopic.noteCount) notes", color: .blue)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
