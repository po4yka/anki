import Foundation
import SwiftProtobuf

enum AnkiError: Error {
    case initFailed
    case backend(Anki_Backend_BackendError)
    case decodingFailed(Error)
}

class AnkiBackend {
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

    func command<Output: SwiftProtobuf.Message>(
        service: UInt32,
        method: UInt32,
        input: some SwiftProtobuf.Message
    ) throws -> Output {
        let inputData = try input.serializedData()
        var isError = false

        let buffer = inputData.withUnsafeBytes { bytes in
            anki_command(
                ptr, service, method,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                bytes.count,
                &isError
            )
        }
        defer { anki_free_buffer(buffer) }

        let outputData = Data(bytes: buffer.data, count: buffer.len)

        if isError {
            let backendError = try Anki_Backend_BackendError(serializedBytes: outputData)
            throw AnkiError.backend(backendError)
        }
        return try Output(serializedBytes: outputData)
    }

    deinit {
        anki_free(ptr)
    }
}
