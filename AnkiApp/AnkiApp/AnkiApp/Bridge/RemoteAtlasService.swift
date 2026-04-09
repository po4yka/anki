import Foundation

/// Remote HTTP implementation of AtlasServiceProtocol for iOS clients.
/// Connects to an atlas sync server running on the user's desktop or cloud.
actor RemoteAtlasService: AtlasServiceProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let apiKey: String?

    init(baseURL: URL, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: .default)
        self.apiKey = apiKey
    }

    // MARK: - Generic request

    private func request<Req: Encodable, Resp: Decodable>(
        method: String,
        body: Req
    ) async throws -> Resp {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/\(method)"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AtlasRemoteError.httpError(
                statusCode: statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return try JSONDecoder().decode(Resp.self, from: data)
    }

    // MARK: - AtlasServiceProtocol

    func search(_ req: SearchRequest) async throws -> SearchResponse {
        try await request(method: "search", body: req)
    }

    func searchChunks(_ req: ChunkSearchRequest) async throws -> ChunkSearchResponse {
        try await request(method: "search_chunks", body: req)
    }

    func generatePreview(filePath: String) async throws -> GeneratePreview {
        try await request(method: "generate_preview", body: GeneratePreviewFromFileRequest(filePath: filePath))
    }

    func generatePreviewFromText(_ req: GeneratePreviewRequest) async throws -> GeneratePreview {
        try await request(method: "generate_preview", body: req)
    }

    func getTaxonomyTree(rootPath: String? = nil) async throws -> [TaxonomyNode] {
        struct Input: Encodable {
            let rootPath: String?
            enum CodingKeys: String, CodingKey { case rootPath = "root_path" }
        }
        return try await request(method: "get_taxonomy_tree", body: Input(rootPath: rootPath))
    }

    func getCoverage(topicPath: String, includeSubtree: Bool = false) async throws -> TopicCoverage? {
        struct Input: Encodable {
            let topicPath: String
            let includeSubtree: Bool
            enum CodingKeys: String, CodingKey {
                case topicPath = "topic_path"
                case includeSubtree = "include_subtree"
            }
        }
        return try await request(method: "get_coverage", body: Input(topicPath: topicPath, includeSubtree: includeSubtree))
    }

    func getGaps(topicPath: String, minCoverage: Int = 0) async throws -> [TopicGap] {
        try await request(method: "get_gaps", body: GapsRequest(topicPath: topicPath, minCoverage: minCoverage))
    }

    func getWeakNotes(topicPath: String) async throws -> [WeakNote] {
        try await request(method: "get_weak_notes", body: TopicPathRequest(topicPath: topicPath))
    }

    func findDuplicates(threshold: Double = 0.95) async throws -> FindDuplicatesResponse {
        try await request(method: "find_duplicates", body: DuplicatesRequest(threshold: threshold))
    }

    func obsidianScan(_ req: ObsidianScanRequest) async throws -> ObsidianScanPreview {
        try await request(method: "obsidian_scan", body: req)
    }
}

enum AtlasRemoteError: Error, LocalizedError {
    case httpError(statusCode: Int, body: String)
    case connectionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return "Atlas server error (\(code)): \(body)"
        case .connectionFailed(let error):
            return "Cannot connect to Atlas server: \(error.localizedDescription)"
        }
    }
}
