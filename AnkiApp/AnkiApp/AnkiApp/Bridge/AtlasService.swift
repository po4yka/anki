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
        self.handle = ptr
    }

    func command<Req: Encodable, Resp: Decodable>(
        method: String, request: Req
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

    deinit {
        atlas_free(handle)
    }
}
