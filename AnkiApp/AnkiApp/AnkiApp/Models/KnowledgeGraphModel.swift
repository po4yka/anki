import Foundation
import Observation

/// Knowledge graph requires KG infrastructure (knowledge_graph crate + kg_repo).
/// Implement after atlas_bridge exposes kg_see_also and kg_topic_neighborhood methods.
@Observable
@MainActor
final class KnowledgeGraphModel {
    var isLoading: Bool = false
    var error: String?

    private let atlas: any AtlasServiceProtocol

    init(atlas: any AtlasServiceProtocol) {
        self.atlas = atlas
    }
}
