// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

public actor AnkiService: AnkiServiceProtocol {
    public let backend: AnkiBackend

    public init(langs: [String] = ["en"]) throws {
        backend = try AnkiBackend(preferredLangs: langs)
    }
}
