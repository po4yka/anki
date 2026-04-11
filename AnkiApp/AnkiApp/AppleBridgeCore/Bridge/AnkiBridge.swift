import Foundation
import SwiftProtobuf

public enum AnkiError: Error {
    case initFailed
    case backend(Anki_Backend_BackendError)
    case decodingFailed(Error)
    case message(String)
}

extension AnkiError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case .initFailed:
                "Failed to initialize the Anki backend."
            case let .backend(error):
                error.message
            case let .decodingFailed(error):
                "Failed to decode backend response: \(error.localizedDescription)"
            case let .message(message):
                message
        }
    }
}

#if os(macOS)
public class AnkiBackend {
    private let ptr: UnsafeMutableRawPointer

    init(preferredLangs: [String], server: Bool = false) throws {
        var initMsg = Anki_Backend_BackendInit()
        initMsg.preferredLangs = preferredLangs
        initMsg.server = server
        let data = try initMsg.serializedData()

        let backend = data.withUnsafeBytes { bytes in
            anki_init(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count)
        }
        guard let backend else {
            throw AnkiError.initFailed
        }
        ptr = backend
    }

    public func command<Output: SwiftProtobuf.Message>(
        service: UInt32,
        method: UInt32,
        input: some SwiftProtobuf.Message
    ) throws -> Output {
        let response = try sendSync(service: service, method: method, payload: try input.serializedData())
        if response.isBackendError {
            let backendError = try Anki_Backend_BackendError(serializedBytes: response.payload)
            throw AnkiError.backend(backendError)
        }
        return try Output(serializedBytes: response.payload)
    }

    private func sendSync(service: UInt32, method: UInt32, payload: Data) throws -> BackendCommandResponse {
        var isError = false
        let buffer = payload.withUnsafeBytes { bytes in
            anki_command(
                ptr,
                service,
                method,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                bytes.count,
                &isError
            )
        }
        defer { anki_free_buffer(buffer) }

        return BackendCommandResponse(
            payload: Data(bytes: buffer.data, count: buffer.len),
            isBackendError: isError
        )
    }

    deinit {
        anki_free(ptr)
    }
}

extension AnkiBackend: BackendCommandTransport {
    public func send(service: UInt32, method: UInt32, payload: Data) async throws -> BackendCommandResponse {
        try sendSync(service: service, method: method, payload: payload)
    }
}
#endif
