import Foundation

public actor RemoteHTTPCommandTransport: BackendCommandTransport {
    private let sessionProvider: any RemoteSessionProviding
    private let session: URLSession

    public init(
        sessionProvider: any RemoteSessionProviding,
        session: URLSession = .shared
    ) {
        self.sessionProvider = sessionProvider
        self.session = session
    }

    public func send(service: UInt32, method: UInt32, payload: Data) async throws -> BackendCommandResponse {
        try await send(service: service, method: method, payload: payload, allowRetry: true)
    }

    private func send(
        service: UInt32,
        method: UInt32,
        payload: Data,
        allowRetry: Bool
    ) async throws -> BackendCommandResponse {
        let endpoint = try await sessionProvider.endpoint()
        let accessToken = try await sessionProvider.authorizedAccessToken()
        let backendSession = try await sessionProvider.ensureBackendSession()

        var request = URLRequest(
            url: endpoint.baseURL
                .appendingPathComponent("api")
                .appendingPathComponent("anki")
                .appendingPathComponent("rpc")
                .appendingPathComponent(String(service))
                .appendingPathComponent(String(method))
        )
        request.httpMethod = "POST"
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(backendSession, forHTTPHeaderField: "X-Anki-Backend-Session")
        request.httpBody = payload

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnkiError.message("The remote backend did not return a valid HTTP response.")
        }

        switch httpResponse.statusCode {
            case 200 ... 299:
                let isBackendError = httpResponse.value(forHTTPHeaderField: "X-Anki-Error") == "1"
                return BackendCommandResponse(payload: data, isBackendError: isBackendError)
            case 401:
                await sessionProvider.invalidateAuth()
                throw decodeServerError(data: data, statusCode: httpResponse.statusCode)
            case 404 where allowRetry:
                await sessionProvider.invalidateBackendSession()
                return try await send(service: service, method: method, payload: payload, allowRetry: false)
            default:
                throw decodeServerError(data: data, statusCode: httpResponse.statusCode)
        }
    }

    private func decodeServerError(data: Data, statusCode: Int) -> AnkiError {
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = payload["error"] as? String {
            return .message(message)
        }
        return .message("Remote backend request failed with HTTP \(statusCode).")
    }
}
