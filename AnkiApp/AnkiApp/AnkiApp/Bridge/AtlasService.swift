import Foundation

private struct AtlasTopicTreeRequest: Encodable {
    let rootPath: String?

    enum CodingKeys: String, CodingKey {
        case rootPath = "root_path"
    }
}

private struct AtlasCoverageRequest: Encodable {
    let topicPath: String
    let includeSubtree: Bool

    enum CodingKeys: String, CodingKey {
        case topicPath = "topic_path"
        case includeSubtree = "include_subtree"
    }
}

struct AtlasConfig: Codable {
    var postgresUrl: String?
    var embeddingProvider: String?
    var embeddingModel: String?
    var embeddingDimension: UInt32?
    var embeddingApiKey: String?

    enum CodingKeys: String, CodingKey {
        case postgresUrl = "postgres_url"
        case embeddingProvider = "embedding_provider"
        case embeddingModel = "embedding_model"
        case embeddingDimension = "embedding_dimension"
        case embeddingApiKey = "embedding_api_key"
    }

    static func fromStoredSettings() -> AtlasConfig {
        let dim = UserDefaults.standard.integer(forKey: "atlasEmbeddingDimension")
        return AtlasConfig(
            postgresUrl: KeychainHelper.loadAtlasPostgresUrl(),
            embeddingProvider: UserDefaults.standard.string(forKey: "atlasEmbeddingProvider"),
            embeddingModel: UserDefaults.standard.string(forKey: "atlasEmbeddingModel"),
            embeddingDimension: dim > 0 ? UInt32(dim) : nil,
            embeddingApiKey: KeychainHelper.loadAtlasApiKey()
        )
    }
}

enum AtlasError: Error {
    case initFailed
    case commandFailed(String)
    case encodingFailed(Error)
    case decodingFailed(Error)
}

#if os(macOS)
actor AtlasService: AtlasServiceProtocol {
    private let handle: UnsafeMutableRawPointer

    init(config: AtlasConfig = AtlasConfig()) throws {
        let json = try JSONEncoder().encode(config)
        let ptr = json.withUnsafeBytes { bytes -> UnsafeMutableRawPointer? in
            atlas_init(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count)
        }
        guard let ptr else { throw AtlasError.initFailed }
        handle = ptr
    }

    func command<Resp: Decodable>(
        method: String, request: some Encodable
    ) throws -> Resp {
        let input: Data
        do {
            input = try JSONEncoder().encode(request)
        } catch {
            throw AtlasError.encodingFailed(error)
        }

        var isError = false
        let buf = input.withUnsafeBytes { bytes in
            method.withCString { methodPtr in
                atlas_command(
                    handle,
                    methodPtr,
                    bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    bytes.count,
                    &isError
                )
            }
        }
        defer { atlas_free_buffer(buf) }

        let data = Data(bytes: buf.data, count: buf.len)
        if isError {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown atlas error"
            throw AtlasError.commandFailed(msg)
        }
        do {
            return try JSONDecoder().decode(Resp.self, from: data)
        } catch {
            throw AtlasError.decodingFailed(error)
        }
    }

    // MARK: - Type-Safe API

    func search(_ request: SearchRequest) async throws -> SearchResponse {
        try command(method: "search", request: request)
    }

    func searchChunks(_ request: ChunkSearchRequest) async throws -> ChunkSearchResponse {
        try command(method: "search_chunks", request: request)
    }

    func generatePreview(filePath: String) async throws -> GeneratePreview {
        try command(method: "generate_preview", request: GeneratePreviewFromFileRequest(filePath: filePath))
    }

    func generatePreviewFromText(_ request: GeneratePreviewRequest) async throws -> GeneratePreview {
        try command(method: "generate_preview", request: request)
    }

    func getTaxonomyTree(rootPath: String? = nil) async throws -> [TaxonomyNode] {
        try command(method: "get_taxonomy_tree", request: AtlasTopicTreeRequest(rootPath: rootPath))
    }

    func getCoverage(topicPath: String, includeSubtree: Bool = false) async throws -> TopicCoverage? {
        try command(
            method: "get_coverage",
            request: AtlasCoverageRequest(topicPath: topicPath, includeSubtree: includeSubtree)
        )
    }

    func getGaps(topicPath: String, minCoverage: Int = 0) async throws -> [TopicGap] {
        try command(method: "get_gaps", request: GapsRequest(topicPath: topicPath, minCoverage: minCoverage))
    }

    func getWeakNotes(topicPath: String) async throws -> [WeakNote] {
        try command(method: "get_weak_notes", request: TopicPathRequest(topicPath: topicPath))
    }

    func findDuplicates(threshold: Double = 0.95) async throws -> FindDuplicatesResponse {
        try command(method: "find_duplicates", request: DuplicatesRequest(threshold: threshold))
    }

    func kgStatus() async throws -> KnowledgeGraphStatus {
        try command(method: "kg_status", request: EmptyRequest())
    }

    func refreshKnowledgeGraph(_ request: RefreshKnowledgeGraphRequest) async throws -> RefreshKnowledgeGraphResponse {
        try command(method: "kg_refresh", request: request)
    }

    func getNoteLinks(noteId: Int64, limit: Int = 12) async throws -> NoteLinksResponse {
        try command(method: "kg_note_links", request: NoteLinksRequest(noteId: noteId, limit: limit))
    }

    func getTopicNeighborhood(
        topicId: Int64,
        maxHops: Int = 2,
        limitPerHop: Int = 20
    ) async throws -> TopicNeighborhoodResponse {
        try command(
            method: "kg_topic_neighborhood",
            request: TopicNeighborhoodRequest(
                topicId: topicId,
                maxHops: maxHops,
                limitPerHop: limitPerHop
            )
        )
    }

    func obsidianScan(_ request: ObsidianScanRequest) async throws -> ObsidianScanPreview {
        try command(method: "obsidian_scan", request: request)
    }

    deinit {
        atlas_free(handle)
    }
}
#else
actor AtlasService: AtlasServiceProtocol {
    init(config _: AtlasConfig = AtlasConfig()) throws {
        throw AtlasError.initFailed
    }

    func search(_ request: SearchRequest) async throws -> SearchResponse {
        throw AtlasError.initFailed
    }

    func searchChunks(_ request: ChunkSearchRequest) async throws -> ChunkSearchResponse {
        throw AtlasError.initFailed
    }

    func generatePreview(filePath: String) async throws -> GeneratePreview {
        throw AtlasError.initFailed
    }

    func generatePreviewFromText(_ request: GeneratePreviewRequest) async throws -> GeneratePreview {
        throw AtlasError.initFailed
    }

    func getTaxonomyTree(rootPath: String?) async throws -> [TaxonomyNode] {
        throw AtlasError.initFailed
    }

    func getCoverage(topicPath: String, includeSubtree: Bool) async throws -> TopicCoverage? {
        throw AtlasError.initFailed
    }

    func getGaps(topicPath: String, minCoverage: Int) async throws -> [TopicGap] {
        throw AtlasError.initFailed
    }

    func getWeakNotes(topicPath: String) async throws -> [WeakNote] {
        throw AtlasError.initFailed
    }

    func findDuplicates(threshold: Double) async throws -> FindDuplicatesResponse {
        throw AtlasError.initFailed
    }

    func kgStatus() async throws -> KnowledgeGraphStatus {
        throw AtlasError.initFailed
    }

    func refreshKnowledgeGraph(_ request: RefreshKnowledgeGraphRequest) async throws -> RefreshKnowledgeGraphResponse {
        throw AtlasError.initFailed
    }

    func getNoteLinks(noteId: Int64, limit: Int) async throws -> NoteLinksResponse {
        throw AtlasError.initFailed
    }

    func getTopicNeighborhood(
        topicId: Int64,
        maxHops: Int,
        limitPerHop: Int
    ) async throws -> TopicNeighborhoodResponse {
        throw AtlasError.initFailed
    }

    func obsidianScan(_ request: ObsidianScanRequest) async throws -> ObsidianScanPreview {
        throw AtlasError.initFailed
    }
}
#endif
