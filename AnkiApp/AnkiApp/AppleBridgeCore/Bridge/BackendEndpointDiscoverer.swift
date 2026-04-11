import Foundation

public protocol BackendEndpointDiscovering: Sendable {
    func verify(endpoint: BackendEndpoint) async throws
    func discoverPreferredEndpoint(for deploymentKind: BackendDeploymentKind) async throws -> BackendEndpoint?
}

public actor DefaultBackendEndpointDiscoverer: BackendEndpointDiscovering {
    private let session: URLSession
    private let companionCandidates: [URL]

    public init(
        session: URLSession = .shared,
        companionCandidates: [URL]? = nil
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

    public func discoverPreferredEndpoint(for deploymentKind: BackendDeploymentKind) async throws -> BackendEndpoint? {
        guard deploymentKind == .companion else {
            return nil
        }

        for candidate in companionCandidates {
            let endpoint = BackendEndpoint(baseURL: candidate, deploymentKind: .companion)
            if try await isReachable(endpoint: endpoint) {
                return endpoint
            }
        }

        return nil
    }

    private func isReachable(endpoint: BackendEndpoint) async throws -> Bool {
        do {
            try await verify(endpoint: endpoint)
            return true
        } catch {
            return false
        }
    }

    private static let defaultCompanionCandidates: [URL] = [
        URL(string: "http://127.0.0.1:8080/"),
        URL(string: "http://localhost:8080/")
    ]
    .compactMap { $0 }
}
