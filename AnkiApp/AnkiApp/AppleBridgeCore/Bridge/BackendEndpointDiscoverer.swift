import Foundation

public protocol BackendEndpointDiscovering: Sendable {
    func verify(endpoint: BackendEndpoint) async throws
    func discoverCompanionEndpoints() async throws -> [DiscoveredBackendCandidate]
    func discoverPreferredEndpoint(for deploymentKind: BackendDeploymentKind) async throws -> BackendEndpoint?
}

public actor DefaultBackendEndpointDiscoverer: BackendEndpointDiscovering {
    private let session: URLSession
    private let companionCandidates: [CompanionCandidate]
    private let bonjourDiscoverer: any BonjourCompanionDiscovering

    public init(
        session: URLSession = .shared,
        companionCandidates: [CompanionCandidate]? = nil
    ) {
        self.init(
            session: session,
            companionCandidates: companionCandidates,
            bonjourDiscoverer: LiveBonjourCompanionDiscoverer()
        )
    }

    init(
        session: URLSession,
        companionCandidates: [CompanionCandidate]?,
        bonjourDiscoverer: any BonjourCompanionDiscovering
    ) {
        self.session = session
        self.companionCandidates = companionCandidates ?? Self.defaultCompanionCandidates
        self.bonjourDiscoverer = bonjourDiscoverer
    }

    public func verify(endpoint: BackendEndpoint) async throws {
        let (_, response) = try await session.data(for: Self.healthRequest(for: endpoint))
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AnkiError.message("The remote backend health check failed with HTTP \(statusCode).")
        }
    }

    public func discoverCompanionEndpoints() async throws -> [DiscoveredBackendCandidate] {
        let bonjourCandidates = await bonjourDiscoverer.discoverCompanionEndpoints()
        let fallbackCandidates = companionCandidates.map {
            DiscoveredBackendCandidate(
                endpoint: BackendEndpoint(baseURL: $0.url, deploymentKind: .companion),
                label: $0.label,
                detail: $0.detail
            )
        }

        let reachableCandidates = try await probeReachableCandidates(
            bonjourCandidates + fallbackCandidates
        )

        var deduped: [DiscoveredBackendCandidate] = []
        var seenURLs = Set<String>()
        for candidate in reachableCandidates {
            let key = candidate.endpoint.baseURL.absoluteString
            if seenURLs.insert(key).inserted {
                deduped.append(candidate)
            }
        }

        return deduped
    }

    public func discoverPreferredEndpoint(for deploymentKind: BackendDeploymentKind) async throws -> BackendEndpoint? {
        guard deploymentKind == .companion else {
            return nil
        }

        return try await discoverCompanionEndpoints().first?.endpoint
    }

    private func probeReachableCandidates(
        _ candidates: [DiscoveredBackendCandidate]
    ) async throws -> [DiscoveredBackendCandidate] {
        var reachable: [(Int, DiscoveredBackendCandidate)] = []

        await withTaskGroup(of: (Int, DiscoveredBackendCandidate?).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask { [session] in
                    do {
                        let (_, response) = try await session.data(
                            for: Self.healthRequest(for: candidate.endpoint)
                        )
                        guard let httpResponse = response as? HTTPURLResponse,
                              (200 ... 299).contains(httpResponse.statusCode) else {
                            return (index, nil)
                        }
                        return (index, candidate)
                    } catch {
                        return (index, nil)
                    }
                }
            }

            for await result in group {
                if let candidate = result.1 {
                    reachable.append((result.0, candidate))
                }
            }
        }

        return reachable
            .sorted { $0.0 < $1.0 }
            .map(\.1)
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
            "Fallback Bonjour-style hostname for older companion builds."
        ),
        (
            "http://ankiatlas.local:8080/",
            "Atlas Companion (.local)",
            "Fallback hostname when Bonjour discovery is unavailable."
        ),
        (
            "http://anki.local:8080/",
            "Anki (.local)",
            "Legacy development hostname for manual companion discovery."
        )
    ]
    .compactMap { rawURL, label, detail in
        guard let url = URL(string: rawURL) else {
            return nil
        }
        return CompanionCandidate(url: url, label: label, detail: detail)
    }
}

protocol BonjourCompanionDiscovering: Sendable {
    func discoverCompanionEndpoints() async -> [DiscoveredBackendCandidate]
}

private struct LiveBonjourCompanionDiscoverer: BonjourCompanionDiscovering {
    func discoverCompanionEndpoints() async -> [DiscoveredBackendCandidate] {
        await MainActor.run {
            BonjourCompanionDiscoverySession()
        }
        .discover()
    }
}

@MainActor
private final class BonjourCompanionDiscoverySession: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private static let serviceType = "_anki-atlas._tcp."
    private static let domain = "local."

    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var candidates: [DiscoveredBackendCandidate] = []
    private var seenURLs = Set<String>()
    private var continuation: CheckedContinuation<[DiscoveredBackendCandidate], Never>?
    private var timeoutTask: Task<Void, Never>?

    func discover(timeoutNanoseconds: UInt64 = 1_500_000_000) async -> [DiscoveredBackendCandidate] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            let browser = NetServiceBrowser()
            browser.delegate = self
            self.browser = browser
            browser.searchForServices(ofType: Self.serviceType, inDomain: Self.domain)

            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                self?.finish()
            }
        }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing _: Bool
    ) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 1.0)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              sender.port > 0,
              let baseURL = URL(string: "http://\(hostName):\(sender.port)/") else {
            return
        }

        let endpoint = BackendEndpoint(baseURL: baseURL, deploymentKind: .companion)
        let key = endpoint.baseURL.absoluteString
        guard seenURLs.insert(key).inserted else {
            return
        }

        let txtRecord = sender.txtRecordData().flatMap(NetService.dictionary(fromTXTRecord:))
        let accountDisplayName = txtRecord?["account_display_name"].flatMap {
            String(data: $0, encoding: .utf8)
        }
        let detailParts = [
            sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            accountDisplayName
        ]
        .compactMap { $0 }
        let detail = detailParts.isEmpty
            ? "Discovered over Bonjour on the local network."
            : detailParts.joined(separator: " · ")

        candidates.append(
            DiscoveredBackendCandidate(
                endpoint: endpoint,
                label: sender.name,
                detail: detail
            )
        )
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        _ = sender
        _ = errorDict
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        _ = browser
        finish()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        _ = browser
        _ = errorDict
        finish()
    }

    private func finish() {
        timeoutTask?.cancel()
        timeoutTask = nil

        browser?.stop()
        browser = nil
        services.forEach { $0.stop() }
        services.removeAll()

        continuation?.resume(returning: candidates)
        continuation = nil
    }
}
