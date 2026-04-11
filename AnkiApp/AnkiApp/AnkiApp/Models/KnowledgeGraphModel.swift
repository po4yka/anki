import AppleBridgeCore
import AppleSharedUI
import Foundation
import Observation

@Observable
@MainActor
final class KnowledgeGraphModel {
    var taxonomyTree: [TaxonomyNode] = []
    var status: KnowledgeGraphStatus?
    var selectedTopicId: Int64?
    var selectedTopicPath: String?
    var neighborhood: TopicNeighborhoodResponse?
    var isLoading: Bool = false
    var isLoadingNeighborhood: Bool = false
    var isRebuilding: Bool = false
    var error: String?

    private let atlas: any AtlasServiceProtocol

    init(atlas: any AtlasServiceProtocol) {
        self.atlas = atlas
    }

    var hasBuiltGraph: Bool {
        guard let status else { return false }
        return status.conceptEdgeCount > 0 || status.topicEdgeCount > 0
    }

    var isAtlasConfigured: Bool {
        if let error {
            return !error.localizedCaseInsensitiveContains("not configured")
        }
        return true
    }

    func load() async {
        isLoading = true
        error = nil

        async let statusTask = atlas.kgStatus()
        async let taxonomyTask = atlas.getTaxonomyTree(rootPath: nil)

        do {
            status = try await statusTask
            taxonomyTree = try await taxonomyTask
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func selectTopic(_ node: TaxonomyNode) async {
        selectedTopicId = node.topicId
        selectedTopicPath = node.path
        await loadNeighborhood()
    }

    func rebuild() async {
        isRebuilding = true
        error = nil
        do {
            _ = try await atlas.refreshKnowledgeGraph(RefreshKnowledgeGraphRequest())
            status = try await atlas.kgStatus()
            if selectedTopicId != nil {
                await loadNeighborhood()
            }
        } catch {
            self.error = error.localizedDescription
        }
        isRebuilding = false
    }

    func topicSummary(for topicId: Int64) -> TopicNodeSummary? {
        neighborhood?.topics.first(where: { $0.topicId == topicId })
    }

    func linkedTopic(for edge: TopicEdgeView) -> TopicNodeSummary? {
        guard let selectedTopicId else { return nil }
        let linkedTopicId = edge.sourceTopicId == selectedTopicId ? edge.targetTopicId : edge.sourceTopicId
        return topicSummary(for: linkedTopicId)
    }

    private func loadNeighborhood() async {
        guard let selectedTopicId else { return }
        isLoadingNeighborhood = true
        error = nil
        do {
            neighborhood = try await atlas.getTopicNeighborhood(
                topicId: selectedTopicId,
                maxHops: 2,
                limitPerHop: 20
            )
        } catch {
            self.error = error.localizedDescription
            neighborhood = nil
        }
        isLoadingNeighborhood = false
    }
}
