import Foundation

private struct RemoteTopicTreeRequest: Encodable {
    let rootPath: String?

    enum CodingKeys: String, CodingKey {
        case rootPath = "root_path"
    }
}

private struct RemoteCoverageRequest: Encodable {
    let topicPath: String
    let includeSubtree: Bool

    enum CodingKeys: String, CodingKey {
        case topicPath = "topic_path"
        case includeSubtree = "include_subtree"
    }
}

/// Remote HTTP implementation of AtlasServiceProtocol for iOS clients.
/// Connects to an atlas sync server running on the user's desktop or cloud.
public actor RemoteAtlasService: AtlasServiceProtocol {
    private let session: URLSession
    private let sessionProvider: any RemoteSessionProviding

    public init(
        sessionProvider: any RemoteSessionProviding,
        session: URLSession = .shared
    ) {
        self.sessionProvider = sessionProvider
        self.session = session
    }

    // MARK: - Generic request

    private func request<Resp: Decodable>(
        method: String,
        body: some Encodable
    ) async throws -> Resp {
        let endpoint = try await sessionProvider.endpoint()
        let accessToken = try await sessionProvider.authorizedAccessToken()

        var urlRequest = URLRequest(url: endpoint.baseURL.appendingPathComponent("api/\(method)"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AtlasRemoteError.httpError(
                statusCode: statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return try JSONDecoder().decode(Resp.self, from: data)
    }

    // MARK: - AtlasServiceProtocol

    public func search(_ req: SearchRequest) async throws -> SearchResponse {
        try await request(method: "search", body: req)
    }

    public func searchChunks(_ req: ChunkSearchRequest) async throws -> ChunkSearchResponse {
        try await request(method: "search_chunks", body: req)
    }

    public func generatePreview(filePath: String) async throws -> GeneratePreview {
        try await request(method: "generate_preview", body: GeneratePreviewFromFileRequest(filePath: filePath))
    }

    public func generatePreviewFromText(_ req: GeneratePreviewRequest) async throws -> GeneratePreview {
        try await request(method: "generate_preview", body: req)
    }

    public func getTaxonomyTree(rootPath: String? = nil) async throws -> [TaxonomyNode] {
        try await request(method: "get_taxonomy_tree", body: RemoteTopicTreeRequest(rootPath: rootPath))
    }

    public func getCoverage(topicPath: String, includeSubtree: Bool = false) async throws -> TopicCoverage? {
        try await request(
            method: "get_coverage",
            body: RemoteCoverageRequest(topicPath: topicPath, includeSubtree: includeSubtree)
        )
    }

    public func getGaps(topicPath: String, minCoverage: Int = 0) async throws -> [TopicGap] {
        try await request(method: "get_gaps", body: GapsRequest(topicPath: topicPath, minCoverage: minCoverage))
    }

    public func getWeakNotes(topicPath: String) async throws -> [WeakNote] {
        try await request(method: "get_weak_notes", body: TopicPathRequest(topicPath: topicPath))
    }

    public func findDuplicates(threshold: Double = 0.95) async throws -> FindDuplicatesResponse {
        try await request(method: "find_duplicates", body: DuplicatesRequest(threshold: threshold))
    }

    public func kgStatus() async throws -> KnowledgeGraphStatus {
        try await request(method: "kg_status", body: EmptyRequest())
    }

    public func refreshKnowledgeGraph(_ req: RefreshKnowledgeGraphRequest) async throws -> RefreshKnowledgeGraphResponse {
        try await request(method: "kg_refresh", body: req)
    }

    public func getNoteLinks(noteId: Int64, limit: Int = 12) async throws -> NoteLinksResponse {
        try await request(method: "kg_note_links", body: NoteLinksRequest(noteId: noteId, limit: limit))
    }

    public func getTopicNeighborhood(
        topicId: Int64,
        maxHops: Int = 2,
        limitPerHop: Int = 20
    ) async throws -> TopicNeighborhoodResponse {
        try await request(
            method: "kg_topic_neighborhood",
            body: TopicNeighborhoodRequest(topicId: topicId, maxHops: maxHops, limitPerHop: limitPerHop)
        )
    }

    public func obsidianScan(_ req: ObsidianScanRequest) async throws -> ObsidianScanPreview {
        try await request(method: "obsidian_scan", body: req)
    }
}

public enum AtlasRemoteError: Error, LocalizedError {
    case httpError(statusCode: Int, body: String)
    case connectionFailed(Error)

    public var errorDescription: String? {
        switch self {
            case let .httpError(code, body):
                "Atlas server error (\(code)): \(body)"
            case let .connectionFailed(error):
                "Cannot connect to Atlas server: \(error.localizedDescription)"
        }
    }
}
