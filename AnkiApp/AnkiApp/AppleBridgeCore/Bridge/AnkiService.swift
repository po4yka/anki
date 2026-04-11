// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

#if os(macOS)
public actor AnkiService: AnkiServiceProtocol {
    public let backend: AnkiBackend

    public init(langs: [String] = ["en"]) throws {
        backend = try AnkiBackend(preferredLangs: langs)
    }
}
#else
public actor AnkiService: AnkiServiceProtocol {
    public init(langs _: [String] = ["en"]) throws {
        throw AnkiError.message("Local Anki backend is unavailable on this platform.")
    }
}
#endif
