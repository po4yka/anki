import Foundation
import Observation

@Observable
@MainActor
final class AnalyticsModel {
    var taxonomyTree: [TaxonomyNode] = []
    var selectedTopicPath: String? = nil
    var coverage: TopicCoverage? = nil
    var gaps: [TopicGap] = []
    var weakNotes: [WeakNote] = []
    var duplicateClusters: [DuplicateCluster] = []
    var isLoading: Bool = false
    var error: String? = nil

    private let atlas: AtlasService

    init(atlas: AtlasService) {
        self.atlas = atlas
    }

    func loadTaxonomyTree() async {
        isLoading = true
        error = nil
        do {
            let nodes: [TaxonomyNode] = try await atlas.command(method: "get_taxonomy_tree", request: EmptyRequest())
            taxonomyTree = nodes
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadCoverage(topicPath: String) async {
        isLoading = true
        error = nil
        do {
            let req = TopicPathRequest(topicPath: topicPath)
            let result: TopicCoverage? = try await atlas.command(method: "get_coverage", request: req)
            coverage = result
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadGaps(topicPath: String, minCoverage: Int = 1) async {
        isLoading = true
        error = nil
        do {
            let req = GapsRequest(topicPath: topicPath, minCoverage: minCoverage)
            let result: [TopicGap] = try await atlas.command(method: "get_gaps", request: req)
            gaps = result
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadWeakNotes(topicPath: String) async {
        isLoading = true
        error = nil
        do {
            let req = TopicPathRequest(topicPath: topicPath)
            let result: [WeakNote] = try await atlas.command(method: "get_weak_notes", request: req)
            weakNotes = result
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadDuplicates(threshold: Double = 0.9) async {
        isLoading = true
        error = nil
        do {
            let req = DuplicatesRequest(threshold: threshold)
            let result: [DuplicateCluster] = try await atlas.command(method: "find_duplicates", request: req)
            duplicateClusters = result
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Request helpers

private struct EmptyRequest: Encodable {}

private struct TopicPathRequest: Encodable {
    let topicPath: String
    enum CodingKeys: String, CodingKey {
        case topicPath = "topic_path"
    }
}

private struct GapsRequest: Encodable {
    let topicPath: String
    let minCoverage: Int
    enum CodingKeys: String, CodingKey {
        case topicPath = "topic_path"
        case minCoverage = "min_coverage"
    }
}

private struct DuplicatesRequest: Encodable {
    let threshold: Double
}
