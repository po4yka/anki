import Foundation

struct AtlasConfig: Codable {
    // Placeholder for future configuration (database URL, Qdrant URL, etc.)
}

enum AtlasError: Error {
    case initFailed
    case commandFailed(String)
    case encodingFailed(Error)
    case decodingFailed(Error)
}

actor AtlasService {
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

    func getTaxonomyTree(rootPath: String? = nil) async throws -> [TaxonomyNode] {
        struct Input: Encodable { let rootPath: String?; enum CodingKeys: String, CodingKey { case rootPath = "root_path" } }
        return try command(method: "get_taxonomy_tree", request: Input(rootPath: rootPath))
    }

    func getCoverage(topicPath: String, includeSubtree: Bool = false) async throws -> TopicCoverage? {
        struct Input: Encodable {
            let topicPath: String; let includeSubtree: Bool
            enum CodingKeys: String, CodingKey { case topicPath = "topic_path"; case includeSubtree = "include_subtree" }
        }
        return try command(method: "get_coverage", request: Input(topicPath: topicPath, includeSubtree: includeSubtree))
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

    func obsidianScan(_ request: ObsidianScanRequest) async throws -> ObsidianScanPreview {
        try command(method: "obsidian_scan", request: request)
    }

    deinit {
        atlas_free(handle)
    }
}
