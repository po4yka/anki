actor AnkiService {
    private let backend: AnkiBackend

    init(langs: [String] = ["en"]) throws {
        self.backend = try AnkiBackend(preferredLangs: langs)
    }

    func openCollection(path: String, mediaFolder: String, mediaDb: String) async throws {
        var req = Anki_Collection_OpenCollectionRequest()
        req.collectionPath = path
        req.mediaFolderPath = mediaFolder
        req.mediaDbPath = mediaDb
        let _: Anki_Generic_Empty = try backend.command(
            service: ServiceIndex.collection,
            method: CollectionMethod.openCollection,
            input: req
        )
    }

    func getCard(id: Int64) async throws -> Anki_Cards_Card {
        var req = Anki_Cards_GetCardRequest()
        req.cardID = id
        return try backend.command(
            service: ServiceIndex.cards,
            method: CardsMethod.getCard,
            input: req
        )
    }
}
