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

public struct AtlasConfig: Codable {
    public var postgresUrl: String?
    public var embeddingProvider: String?
    public var embeddingModel: String?
    public var embeddingDimension: UInt32?
    public var embeddingApiKey: String?

    enum CodingKeys: String, CodingKey {
        case postgresUrl = "postgres_url"
        case embeddingProvider = "embedding_provider"
        case embeddingModel = "embedding_model"
        case embeddingDimension = "embedding_dimension"
        case embeddingApiKey = "embedding_api_key"
    }

    public static func fromStoredSettings() -> AtlasConfig {
        let dim = UserDefaults.standard.integer(forKey: "atlasEmbeddingDimension")
        return AtlasConfig(
            postgresUrl: KeychainHelper.loadAtlasPostgresUrl(),
            embeddingProvider: UserDefaults.standard.string(forKey: "atlasEmbeddingProvider"),
            embeddingModel: UserDefaults.standard.string(forKey: "atlasEmbeddingModel"),
            embeddingDimension: dim > 0 ? UInt32(dim) : nil,
            embeddingApiKey: KeychainHelper.loadAtlasApiKey()
        )
    }

    public init(
        postgresUrl: String? = nil,
        embeddingProvider: String? = nil,
        embeddingModel: String? = nil,
        embeddingDimension: UInt32? = nil,
        embeddingApiKey: String? = nil
    ) {
        self.postgresUrl = postgresUrl
        self.embeddingProvider = embeddingProvider
        self.embeddingModel = embeddingModel
        self.embeddingDimension = embeddingDimension
        self.embeddingApiKey = embeddingApiKey
    }
}

public enum AtlasError: Error {
    case initFailed
    case commandFailed(String)
    case encodingFailed(Error)
    case decodingFailed(Error)
}

public actor AtlasService: AtlasServiceProtocol {
    private let handle: UnsafeMutableRawPointer

    public init(config: AtlasConfig = AtlasConfig()) throws {
        let json = try JSONEncoder().encode(config)
        let ptr = json.withUnsafeBytes { bytes -> UnsafeMutableRawPointer? in
            atlas_init(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count)
        }
        guard let ptr else { throw AtlasError.initFailed }
        handle = ptr
    }

    public func command<Resp: Decodable>(
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

    public func search(_ request: SearchRequest) async throws -> SearchResponse {
        try command(method: "search", request: request)
    }

    public func searchChunks(_ request: ChunkSearchRequest) async throws -> ChunkSearchResponse {
        try command(method: "search_chunks", request: request)
    }

    public func generatePreview(filePath: String) async throws -> GeneratePreview {
        try command(method: "generate_preview", request: GeneratePreviewFromFileRequest(filePath: filePath))
    }

    public func generatePreviewFromText(_ request: GeneratePreviewRequest) async throws -> GeneratePreview {
        try command(method: "generate_preview", request: request)
    }

    public func getTaxonomyTree(rootPath: String? = nil) async throws -> [TaxonomyNode] {
        try command(method: "get_taxonomy_tree", request: AtlasTopicTreeRequest(rootPath: rootPath))
    }

    public func getCoverage(topicPath: String, includeSubtree: Bool = false) async throws -> TopicCoverage? {
        try command(
            method: "get_coverage",
            request: AtlasCoverageRequest(topicPath: topicPath, includeSubtree: includeSubtree)
        )
    }

    public func getGaps(topicPath: String, minCoverage: Int = 0) async throws -> [TopicGap] {
        try command(method: "get_gaps", request: GapsRequest(topicPath: topicPath, minCoverage: minCoverage))
    }

    public func getWeakNotes(topicPath: String) async throws -> [WeakNote] {
        try command(method: "get_weak_notes", request: TopicPathRequest(topicPath: topicPath))
    }

    public func findDuplicates(threshold: Double = 0.95) async throws -> FindDuplicatesResponse {
        try command(method: "find_duplicates", request: DuplicatesRequest(threshold: threshold))
    }

    public func kgStatus() async throws -> KnowledgeGraphStatus {
        try command(method: "kg_status", request: EmptyRequest())
    }

    public func refreshKnowledgeGraph(_ request: RefreshKnowledgeGraphRequest) async throws
        -> RefreshKnowledgeGraphResponse {
        try command(method: "kg_refresh", request: request)
    }

    public func getNoteLinks(noteId: Int64, limit: Int = 12) async throws -> NoteLinksResponse {
        try command(method: "kg_note_links", request: NoteLinksRequest(noteId: noteId, limit: limit))
    }

    public func getTopicNeighborhood(
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

    public func obsidianScan(_ request: ObsidianScanRequest) async throws -> ObsidianScanPreview {
        try command(method: "obsidian_scan", request: request)
    }

    deinit {
        atlas_free(handle)
    }
}
