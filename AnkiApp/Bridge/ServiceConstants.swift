/// Service index constants matching the Rust backend's service registration order.
enum ServiceIndex {
    static let sync: UInt32 = 1
    static let collection: UInt32 = 3
    static let cards: UInt32 = 5
    static let decks: UInt32 = 7
    static let config: UInt32 = 9
    static let deckConfig: UInt32 = 11
    static let scheduler: UInt32 = 13
    static let notetypes: UInt32 = 23
    static let notes: UInt32 = 25
    static let cardRendering: UInt32 = 27
    static let search: UInt32 = 29
    static let i18n: UInt32 = 33
    static let imageOcclusion: UInt32 = 35
    static let importExport: UInt32 = 37
    static let media: UInt32 = 39
    static let stats: UInt32 = 41
    static let tags: UInt32 = 43
}

enum CollectionMethod {
    static let openCollection: UInt32 = 0
    static let closeCollection: UInt32 = 1
    static let createBackup: UInt32 = 2
    static let awaitBackupCompletion: UInt32 = 3
    static let latestProgress: UInt32 = 4
    static let setWantsAbort: UInt32 = 5
    static let checkDatabase: UInt32 = 6
    static let getUndoStatus: UInt32 = 7
    static let undo: UInt32 = 8
    static let redo: UInt32 = 9
    static let addCustomUndoEntry: UInt32 = 10
    static let mergeUndoEntries: UInt32 = 11
}

enum SchedulerMethod {
    static let getQueuedCards: UInt32 = 0
    static let answerCard: UInt32 = 4
    static let schedTimingToday: UInt32 = 5
    static let countsForDeckToday: UInt32 = 10
    static let congratsInfo: UInt32 = 11
    static let buryOrSuspendCards: UInt32 = 14
    static let scheduleCardsAsNew: UInt32 = 17
    static let setDueDate: UInt32 = 19
    static let getSchedulingStates: UInt32 = 20
    static let describeNextStates: UInt32 = 21
}

enum DecksMethod {
    static let newDeck: UInt32 = 0
    static let addDeck: UInt32 = 1
    static let deckTree: UInt32 = 4
    static let getDeck: UInt32 = 8
    static let getDeckNames: UInt32 = 13
    static let removeDecks: UInt32 = 16
    static let setCurrentDeck: UInt32 = 22
    static let getCurrentDeck: UInt32 = 23
}

enum NotesMethod {
    static let newNote: UInt32 = 0
    static let addNote: UInt32 = 1
    static let updateNotes: UInt32 = 5
    static let getNote: UInt32 = 6
    static let removeNotes: UInt32 = 7
    static let noteFieldsCheck: UInt32 = 11
    static let cardsOfNote: UInt32 = 12
}

enum CardsMethod {
    static let getCard: UInt32 = 0
    static let updateCards: UInt32 = 1
    static let setFlag: UInt32 = 4
}

enum SearchMethod {
    static let searchCards: UInt32 = 1
    static let searchNotes: UInt32 = 2
    static let findAndReplace: UInt32 = 5
    static let allBrowserColumns: UInt32 = 6
    static let browserRowForId: UInt32 = 7
    static let setActiveBrowserColumns: UInt32 = 8
}

enum CardRenderingMethod {
    static let extractAvTags: UInt32 = 0
    static let renderExistingCard: UInt32 = 6
    static let compareAnswer: UInt32 = 15
}

enum StatsMethod {
    static let cardStats: UInt32 = 0
    static let graphs: UInt32 = 2
}

enum TagsMethod {
    static let allTags: UInt32 = 1
    static let tagTree: UInt32 = 4
    static let addNoteTags: UInt32 = 7
    static let removeNoteTags: UInt32 = 8
    static let completeTag: UInt32 = 10
}

enum NotetypesMethod {
    static let getNotetype: UInt32 = 6
    static let getNotetypeNames: UInt32 = 8
    static let getFieldNames: UInt32 = 16
}

enum ImportExportMethod {
    static let importAnkiPackage: UInt32 = 0
    static let exportAnkiPackage: UInt32 = 4
}

enum MediaMethod {
    static let checkMedia: UInt32 = 0
    static let addMediaFile: UInt32 = 1
}

enum ConfigMethod {
    static let getPreferences: UInt32 = 9
    static let setPreferences: UInt32 = 10
}
