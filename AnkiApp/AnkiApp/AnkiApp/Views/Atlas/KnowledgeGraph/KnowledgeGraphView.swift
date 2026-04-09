import SwiftUI

// MARK: - Data types

struct GraphNode: Identifiable, Equatable {
    let id: String
    let label: String
    let noteCount: Int
    let childTags: [String]
}

struct GraphEdge: Identifiable {
    var id: String { "\(source)-\(target)" }
    let source: String
    let target: String
    let weight: CGFloat
}

// MARK: - Main view

struct KnowledgeGraphView: View {
    @Environment(AppState.self) private var appState
    @State private var nodes: [GraphNode] = []
    @State private var edges: [GraphEdge] = []
    @State private var selectedNode: GraphNode?
    @State private var isLoading = false
    @State private var searchText = ""

    var body: some View {
        HSplitView {
            graphPanel
                .frame(minWidth: 300, idealWidth: 500)
            detailPanel
                .frame(minWidth: 240, idealWidth: 280)
        }
        .task { await loadGraph() }
    }

    // MARK: - Graph panel

    private var graphPanel: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if isLoading {
                loadingView
            } else if nodes.isEmpty {
                emptyView
            } else {
                GraphCanvasView(
                    nodes: filteredNodes,
                    edges: filteredEdges,
                    selectedNodeId: selectedNode?.id,
                    onSelectNode: { id in
                        selectedNode = nodes.first { $0.id == id }
                    }
                )
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            TextField("Filter concepts...", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Building knowledge graph...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No Concepts",
            systemImage: "brain",
            description: Text("Add tags to your notes to build a knowledge graph.")
        )
    }

    // MARK: - Detail panel

    private var detailPanel: some View {
        Group {
            if let node = selectedNode {
                NodeDetailView(
                    node: node,
                    relatedNodes: relatedNodes(for: node),
                    onSelectRelated: { related in
                        selectedNode = related
                    }
                )
            } else {
                ContentUnavailableView(
                    "Select a Concept",
                    systemImage: "arrow.left",
                    description: Text("Click a node in the graph to view details.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filtering

    private var filteredNodes: [GraphNode] {
        guard !searchText.isEmpty else { return nodes }
        return nodes.filter { $0.label.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredEdges: [GraphEdge] {
        guard !searchText.isEmpty else { return edges }
        let ids = Set(filteredNodes.map { $0.id })
        return edges.filter { ids.contains($0.source) && ids.contains($0.target) }
    }

    private func relatedNodes(for node: GraphNode) -> [GraphNode] {
        let connectedIds = edges
            .filter { $0.source == node.id || $0.target == node.id }
            .flatMap { [$0.source, $0.target] }
        let ids = Set(connectedIds).subtracting([node.id])
        return nodes.filter { ids.contains($0.id) }
    }

    // MARK: - Data loading

    private func loadGraph() async {
        guard appState.isCollectionOpen else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let tagList = try await appState.service.allTags()
            let allTags = tagList.vals
            let topLevel = Set(allTags.map { $0.components(separatedBy: "::").first ?? $0 })
            var builtNodes: [GraphNode] = []
            for tagName in topLevel.sorted() {
                let children = allTags.filter { $0.hasPrefix(tagName + "::") || $0 == tagName }
                builtNodes.append(GraphNode(
                    id: tagName,
                    label: tagName,
                    noteCount: children.count,
                    childTags: children.sorted()
                ))
            }
            // Build edges: nodes that share child tags are related
            var builtEdges: [GraphEdge] = []
            for i in builtNodes.indices {
                for j in builtNodes.indices where j > i {
                    let setA = Set(builtNodes[i].childTags)
                    let setB = Set(builtNodes[j].childTags)
                    let shared = setA.intersection(setB).count
                    if shared > 0 {
                        let weight = CGFloat(shared) / CGFloat(max(setA.count, setB.count))
                        builtEdges.append(GraphEdge(
                            source: builtNodes[i].id,
                            target: builtNodes[j].id,
                            weight: min(1.0, weight)
                        ))
                    }
                }
            }
            nodes = builtNodes
            edges = builtEdges
        } catch {}
    }
}

// MARK: - Canvas graph view

struct GraphCanvasView: View {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let selectedNodeId: String?
    let onSelectNode: (String) -> Void

    @State private var positions: [String: CGPoint] = [:]
    @State private var canvasSize: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureDrag: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let effectiveScale = scale * gestureScale
                let tx = offset.width + gestureDrag.width
                let ty = offset.height + gestureDrag.height
                var ctx = context
                ctx.translateBy(x: tx, y: ty)
                ctx.scaleBy(x: effectiveScale, y: effectiveScale)

                drawEdges(context: &ctx)
                drawNodes(context: &ctx)
            }
            .gesture(panGesture.simultaneously(with: magnifyGesture))
            .onTapGesture { location in
                handleTap(at: location)
            }
            .onChange(of: nodes) { _, _ in
                layoutNodes(in: geo.size)
            }
            .onAppear {
                canvasSize = geo.size
                layoutNodes(in: geo.size)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            zoomControls
                .padding(12)
        }
        .overlay(alignment: .topLeading) {
            graphLegend
                .padding(12)
        }
    }

    // MARK: - Drawing

    private func drawEdges(context: inout GraphicsContext) {
        for edge in edges {
            guard let from = positions[edge.source],
                  let to = positions[edge.target] else { continue }
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            let alpha = 0.15 + Double(edge.weight) * 0.35
            context.stroke(
                path,
                with: .color(.secondary.opacity(alpha)),
                lineWidth: 1 + edge.weight * 2
            )
        }
    }

    private func drawNodes(context: inout GraphicsContext) {
        for node in nodes {
            guard let pos = positions[node.id] else { continue }
            let isSelected = node.id == selectedNodeId
            let radius: CGFloat = nodeRadius(for: node, selected: isSelected)
            let rect = CGRect(
                x: pos.x - radius, y: pos.y - radius,
                width: radius * 2, height: radius * 2
            )

            // Shadow
            var shadowCtx = context
            shadowCtx.opacity = 0.15
            shadowCtx.fill(
                Path(ellipseIn: rect.insetBy(dx: -2, dy: -2).offsetBy(dx: 0, dy: 2)),
                with: .color(.black)
            )

            // Fill
            let fillColor: Color = isSelected ? .accentColor : nodeColor(for: node)
            context.fill(Path(ellipseIn: rect), with: .color(fillColor))

            // Stroke
            let strokeColor: Color = isSelected ? .accentColor : .white.opacity(0.4)
            context.stroke(Path(ellipseIn: rect), with: .color(strokeColor), lineWidth: isSelected ? 2.5 : 1)

            // Label
            let labelY = pos.y + radius + 10
            let resolved = context.resolve(
                Text(node.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            )
            context.draw(resolved, at: CGPoint(x: pos.x, y: labelY))
        }
    }

    private func nodeRadius(for node: GraphNode, selected: Bool) -> CGFloat {
        let base: CGFloat = selected ? 22 : 14
        return base + CGFloat(min(node.noteCount, 10)) * 0.8
    }

    private func nodeColor(for node: GraphNode) -> Color {
        let hue = CGFloat(abs(node.id.hashValue) % 360) / 360.0
        return Color(hue: Double(hue), saturation: 0.55, brightness: 0.75)
    }

    // MARK: - Layout

    private func layoutNodes(in size: CGSize) {
        guard !nodes.isEmpty else { return }
        canvasSize = size
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let count = nodes.count
        let radius: CGFloat = count == 1 ? 0 : min(size.width, size.height) * 0.35
        var newPositions: [String: CGPoint] = [:]
        for (i, node) in nodes.enumerated() {
            let angle = CGFloat(i) / CGFloat(count) * .pi * 2 - .pi / 2
            newPositions[node.id] = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
        positions = newPositions
        // Reset transform so layout is centered
        offset = .zero
        scale = 1.0
    }

    // MARK: - Interaction

    private func handleTap(at location: CGPoint) {
        let effectiveScale = scale * gestureScale
        let tx = offset.width + gestureDrag.width
        let ty = offset.height + gestureDrag.height
        // Convert tap location to canvas space
        let canvasX = (location.x - tx) / effectiveScale
        let canvasY = (location.y - ty) / effectiveScale
        let tappedPoint = CGPoint(x: canvasX, y: canvasY)

        for node in nodes {
            guard let pos = positions[node.id] else { continue }
            let radius = nodeRadius(for: node, selected: node.id == selectedNodeId)
            let dist = hypot(tappedPoint.x - pos.x, tappedPoint.y - pos.y)
            if dist <= radius + 4 {
                onSelectNode(node.id)
                return
            }
        }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .updating($gestureDrag) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($gestureScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                scale = max(0.3, min(3.0, scale * value.magnification))
            }
    }

    // MARK: - Overlay controls

    private var zoomControls: some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(.spring(duration: 0.3)) { scale = min(3.0, scale * 1.3) }
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .accessibilityLabel("Zoom in")

            Button {
                withAnimation(.spring(duration: 0.3)) { scale = max(0.3, scale / 1.3) }
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .accessibilityLabel("Zoom out")

            Button {
                withAnimation(.spring(duration: 0.3)) {
                    scale = 1.0
                    offset = .zero
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .accessibilityLabel("Reset view")
        }
        .buttonStyle(.accessoryBar)
        .controlSize(.small)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var graphLegend: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text("\(nodes.count) concepts")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.tertiary)
            Image(systemName: "line.diagonal")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text("\(edges.count) connections")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Node detail view

private struct NodeDetailView: View {
    let node: GraphNode
    let relatedNodes: [GraphNode]
    let onSelectRelated: (GraphNode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.label)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Label("\(node.childTags.count) tag\(node.childTags.count == 1 ? "" : "s")", systemImage: "tag")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                // Tags
                if !node.childTags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags")
                            .font(.headline)
                        FlowLayout(spacing: 4) {
                            ForEach(node.childTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.fill.tertiary)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                }

                // Related
                if !relatedNodes.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Related Concepts")
                            .font(.headline)
                        ForEach(relatedNodes) { related in
                            Button {
                                onSelectRelated(related)
                            } label: {
                                Label(related.label, systemImage: "arrow.triangle.branch")
                                    .font(.body)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel("Navigate to \(related.label)")
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

// MARK: - Flow layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }
        return (positions, CGSize(width: maxX, height: currentY + rowHeight))
    }
}

#Preview {
    KnowledgeGraphView()
        .environment(AppState())
        .frame(width: 700, height: 500)
}
