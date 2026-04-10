import Foundation
import Observation

@Observable
@MainActor
final class AnalyticsModel {
    var taxonomyTree: [TaxonomyNode] = []
    var selectedTopicPath: String?
    var coverage: TopicCoverage?
    var gaps: [TopicGap] = []
    var weakNotes: [WeakNote] = []
    var duplicateClusters: [DuplicateCluster] = []
    var isLoading: Bool = false
    var error: String?

    private let atlas: any AtlasServiceProtocol

    init(atlas: any AtlasServiceProtocol) {
        self.atlas = atlas
    }

    func loadTaxonomyTree() async {
        isLoading = true
        error = nil
        do {
            let nodes = try await atlas.getTaxonomyTree(rootPath: nil)
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
            let result = try await atlas.getCoverage(topicPath: topicPath, includeSubtree: true)
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
            let result = try await atlas.getGaps(topicPath: topicPath, minCoverage: minCoverage)
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
            let result = try await atlas.getWeakNotes(topicPath: topicPath)
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
            let response = try await atlas.findDuplicates(threshold: threshold)
            duplicateClusters = response.clusters
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
