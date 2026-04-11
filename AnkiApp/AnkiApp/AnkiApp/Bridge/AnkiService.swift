// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

#if os(macOS)
actor AnkiService: AnkiServiceProtocol {
    let backend: AnkiBackend

    init(langs: [String] = ["en"]) throws {
        backend = try AnkiBackend(preferredLangs: langs)
    }
}
#else
actor AnkiService: AnkiServiceProtocol {
    init(langs _: [String] = ["en"]) throws {
        throw AnkiError.message("Local Anki backend is unavailable on this platform.")
    }
}
#endif
