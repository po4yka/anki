import Foundation

public protocol BackendEndpointDiscovering: Sendable {
    func verify(endpoint: BackendEndpoint) async throws
    func discoverCompanionEndpoints() async throws -> [DiscoveredBackendCandidate]
    func discoverPreferredEndpoint(for deploymentKind: BackendDeploymentKind) async throws -> BackendEndpoint?
}

public actor DefaultBackendEndpointDiscoverer: BackendEndpointDiscovering {
    private let session: URLSession
    private let companionCandidates: [CompanionCandidate]

    public init(
        session: URLSession = .shared,
        companionCandidates: [CompanionCandidate]? = nil
    ) {
        self.session = session
        self.companionCandidates = companionCandidates ?? Self.defaultCompanionCandidates
    }

    public func verify(endpoint: BackendEndpoint) async throws {
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("health"))
        request.httpMethod = "GET"

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AnkiError.message("The remote backend health check failed with HTTP \(statusCode).")
        }
    }

    public func discoverCompanionEndpoints() async throws -> [DiscoveredBackendCandidate] {
        var discovered: [DiscoveredBackendCandidate] = []

        await withTaskGroup(of: (Int, DiscoveredBackendCandidate?).self) { group in
            for (index, candidate) in companionCandidates.enumerated() {
                group.addTask { [session] in
                    let endpoint = BackendEndpoint(baseURL: candidate.url, deploymentKind: .companion)
                    let request = Self.healthRequest(for: endpoint)

                    do {
                        let (_, response) = try await session.data(for: request)
                        guard let httpResponse = response as? HTTPURLResponse,
                              (200 ... 299).contains(httpResponse.statusCode) else {
                            return (index, nil)
                        }

                        return (
                            index,
                            DiscoveredBackendCandidate(
                                endpoint: endpoint,
                                label: candidate.label,
                                detail: candidate.detail
                            )
                        )
                    } catch {
                        return (index, nil)
                    }
                }
            }

            var indexedResults: [(Int, DiscoveredBackendCandidate)] = []
            for await result in group {
                if let candidate = result.1 {
                    indexedResults.append((result.0, candidate))
                }
            }

            discovered = indexedResults
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }

        return discovered
    }

    public func discoverPreferredEndpoint(for deploymentKind: BackendDeploymentKind) async throws -> BackendEndpoint? {
        guard deploymentKind == .companion else {
            return nil
        }

        return try await discoverCompanionEndpoints().first?.endpoint
    }

    private func isReachable(endpoint: BackendEndpoint) async throws -> Bool {
        do {
            try await verify(endpoint: endpoint)
            return true
        } catch {
            return false
        }
    }

    private static func healthRequest(for endpoint: BackendEndpoint) -> URLRequest {
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("health"))
        request.httpMethod = "GET"
        return request
    }

    public struct CompanionCandidate: Sendable {
        public var url: URL
        public var label: String
        public var detail: String

        public init(url: URL, label: String, detail: String) {
            self.url = url
            self.label = label
            self.detail = detail
        }
    }

    private static let defaultCompanionCandidates: [CompanionCandidate] = [
        (
            "http://127.0.0.1:8080/",
            "This Device",
            "Best for the iOS Simulator or a local companion running on the same machine."
        ),
        (
            "http://localhost:8080/",
            "Localhost",
            "Alternate loopback address for a companion running on the same machine."
        ),
        (
            "http://anki-companion.local:8080/",
            "Anki Companion (.local)",
            "Typical Bonjour hostname for a Mac companion on the local network."
        ),
        (
            "http://ankiatlas.local:8080/",
            "Atlas Companion (.local)",
            "Use this if the host advertises a dedicated Anki Atlas Bonjour name."
        ),
        (
            "http://anki.local:8080/",
            "Anki (.local)",
            "Fallback Bonjour hostname for companion development builds."
        )
    ]
    .compactMap { rawURL, label, detail in
        guard let url = URL(string: rawURL) else {
            return nil
        }
        return CompanionCandidate(url: url, label: label, detail: detail)
    }
}
