import Foundation
import SwiftProtobuf

public struct BackendCommandResponse: Sendable {
    public let payload: Data
    public let isBackendError: Bool

    public init(payload: Data, isBackendError: Bool) {
        self.payload = payload
        self.isBackendError = isBackendError
    }
}

public protocol BackendCommandTransport {
    func send(service: UInt32, method: UInt32, payload: Data) async throws -> BackendCommandResponse
}

public extension BackendCommandTransport {
    func sendCommand<Output: SwiftProtobuf.Message>(
        service: UInt32,
        method: UInt32,
        input: some SwiftProtobuf.Message
    ) async throws -> Output {
        let response = try await send(service: service, method: method, payload: try input.serializedData())
        if response.isBackendError {
            let backendError = try Anki_Backend_BackendError(serializedBytes: response.payload)
            throw AnkiError.backend(backendError)
        }
        return try Output(serializedBytes: response.payload)
    }
}
