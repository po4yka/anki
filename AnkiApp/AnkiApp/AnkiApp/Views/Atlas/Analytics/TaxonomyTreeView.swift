import AppleBridgeCore
import AppleSharedUI
import SwiftUI

private extension TaxonomyNode {
    var childrenOrNil: [TaxonomyNode]? {
        children.isEmpty ? nil : children
    }
}

struct TaxonomyTreeView: View {
    @Bindable var model: AnalyticsModel

    var body: some View {
        #if os(macOS)
            HSplitView {
                List(model.taxonomyTree, children: \.childrenOrNil) { node in
                    TaxonomyNodeRow(node: node, isSelected: model.selectedTopicPath == node.path)
                        .onTapGesture {
                            model.selectedTopicPath = node.path
                            Task { await model.loadCoverage(topicPath: node.path) }
                        }
                }
                .frame(minWidth: 200)

                if let coverage = model.coverage {
                    CoverageView(coverage: coverage)
                        .frame(minWidth: 300)
                } else if model.selectedTopicPath != nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "Select a Topic",
                        systemImage: "list.bullet.indent",
                        description: Text("Choose a topic from the tree to view coverage details.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        #else
            VStack(spacing: 0) {
                List(model.taxonomyTree, children: \.childrenOrNil) { node in
                    TaxonomyNodeRow(node: node, isSelected: model.selectedTopicPath == node.path)
                        .onTapGesture {
                            model.selectedTopicPath = node.path
                            Task { await model.loadCoverage(topicPath: node.path) }
                        }
                }

                Divider()

                Group {
                    if let coverage = model.coverage {
                        CoverageView(coverage: coverage)
                    } else if model.selectedTopicPath != nil {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "Select a Topic",
                            systemImage: "list.bullet.indent",
                            description: Text("Choose a topic from the tree to view coverage details.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        #endif
    }
}

private struct TaxonomyNodeRow: View {
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
