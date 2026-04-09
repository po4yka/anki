import Foundation

/// Protocol for Atlas service access, enabling both local FFI (macOS)
/// and remote HTTP (iOS) implementations.
protocol AtlasServiceProtocol: Sendable {
    func search(_ request: SearchRequest) async throws -> SearchResponse
    func searchChunks(_ request: ChunkSearchRequest) async throws -> ChunkSearchResponse
    func generatePreview(filePath: String) async throws -> GeneratePreview
    func generatePreviewFromText(_ request: GeneratePreviewRequest) async throws -> GeneratePreview
    func getTaxonomyTree(rootPath: String?) async throws -> [TaxonomyNode]
    func getCoverage(topicPath: String, includeSubtree: Bool) async throws -> TopicCoverage?
    func getGaps(topicPath: String, minCoverage: Int) async throws -> [TopicGap]
    func getWeakNotes(topicPath: String) async throws -> [WeakNote]
    func findDuplicates(threshold: Double) async throws -> FindDuplicatesResponse
    func obsidianScan(_ request: ObsidianScanRequest) async throws -> ObsidianScanPreview
}
