/// Service index constants matching the Rust backend's service registration order.
public enum ServiceIndex {
    public static let sync: UInt32 = 1
    public static let collection: UInt32 = 3
    public static let cards: UInt32 = 5
    public static let decks: UInt32 = 7
    public static let config: UInt32 = 9
    public static let deckConfig: UInt32 = 11
    public static let scheduler: UInt32 = 13
    public static let notetypes: UInt32 = 23
    public static let notes: UInt32 = 25
    public static let cardRendering: UInt32 = 27
    public static let search: UInt32 = 29
    public static let i18n: UInt32 = 33
    public static let imageOcclusion: UInt32 = 35
    public static let importExport: UInt32 = 37
    public static let media: UInt32 = 39
    public static let stats: UInt32 = 41
    public static let tags: UInt32 = 43
}

public enum CollectionMethod {
    public static let openCollection: UInt32 = 0
    public static let closeCollection: UInt32 = 1
    public static let createBackup: UInt32 = 2
    public static let awaitBackupCompletion: UInt32 = 3
    public static let latestProgress: UInt32 = 4
    public static let setWantsAbort: UInt32 = 5
    public static let checkDatabase: UInt32 = 6
    public static let getUndoStatus: UInt32 = 7
    public static let undo: UInt32 = 8
    public static let redo: UInt32 = 9
    public static let addCustomUndoEntry: UInt32 = 10
    public static let mergeUndoEntries: UInt32 = 11
}

public enum SchedulerMethod {
    public static let getQueuedCards: UInt32 = 0
    public static let answerCard: UInt32 = 4
    public static let schedTimingToday: UInt32 = 5
    public static let countsForDeckToday: UInt32 = 10
    public static let congratsInfo: UInt32 = 11
    public static let buryOrSuspendCards: UInt32 = 14
    public static let scheduleCardsAsNew: UInt32 = 17
    public static let setDueDate: UInt32 = 19
    public static let getSchedulingStates: UInt32 = 20
    public static let describeNextStates: UInt32 = 21
    public static let emptyFilteredDeck: UInt32 = 15
    public static let rebuildFilteredDeck: UInt32 = 16
    public static let customStudy: UInt32 = 27
    public static let customStudyDefaults: UInt32 = 28
}

public enum DecksMethod {
    public static let newDeck: UInt32 = 0
    public static let addDeck: UInt32 = 1
    public static let deckTree: UInt32 = 4
    public static let getDeck: UInt32 = 8
    public static let updateDeck: UInt32 = 9
    public static let getDeckNames: UInt32 = 13
    public static let removeDecks: UInt32 = 16
    public static let renameDeck: UInt32 = 18
    public static let setCurrentDeck: UInt32 = 22
    public static let getCurrentDeck: UInt32 = 23
}

public enum NotesMethod {
    public static let newNote: UInt32 = 0
    public static let addNote: UInt32 = 1
    public static let defaultsForAdding: UInt32 = 3
    public static let defaultDeckForNotetype: UInt32 = 4
    public static let updateNotes: UInt32 = 5
    public static let getNote: UInt32 = 6
    public static let removeNotes: UInt32 = 7
    public static let noteFieldsCheck: UInt32 = 11
    public static let clozeNumbersInNote: UInt32 = 8
    public static let cardsOfNote: UInt32 = 12
}

public enum CardsMethod {
    public static let getCard: UInt32 = 0
    public static let updateCards: UInt32 = 1
    public static let setFlag: UInt32 = 4
}

public enum SearchMethod {
    public static let searchCards: UInt32 = 1
    public static let searchNotes: UInt32 = 2
    public static let findAndReplace: UInt32 = 5
    public static let allBrowserColumns: UInt32 = 6
    public static let browserRowForId: UInt32 = 7
    public static let setActiveBrowserColumns: UInt32 = 8
}

public enum CardRenderingMethod {
    public static let extractAvTags: UInt32 = 0
    public static let renderExistingCard: UInt32 = 6
    public static let compareAnswer: UInt32 = 15
}

public enum StatsMethod {
    public static let cardStats: UInt32 = 0
    public static let graphs: UInt32 = 2
}

public enum TagsMethod {
    public static let allTags: UInt32 = 1
    public static let tagTree: UInt32 = 4
    public static let addNoteTags: UInt32 = 7
    public static let removeNoteTags: UInt32 = 8
    public static let completeTag: UInt32 = 10
}

public enum NotetypesMethod {
    public static let addNotetype: UInt32 = 0
    public static let updateNotetype: UInt32 = 1
    public static let removeNotetype: UInt32 = 2
    public static let getNotetype: UInt32 = 6
    public static let getNotetypeNamesAndCounts: UInt32 = 7
    public static let getNotetypeNames: UInt32 = 8
    public static let getFieldNames: UInt32 = 16
}

public enum ImageOcclusionMethod {
    public static let getImageForOcclusion: UInt32 = 0
    public static let getImageOcclusionNote: UInt32 = 1
    public static let addImageOcclusionNote: UInt32 = 4
    public static let updateImageOcclusionNote: UInt32 = 5
}

public enum ImportExportMethod {
    public static let importAnkiPackage: UInt32 = 0
    public static let getCsvMetadata: UInt32 = 2
    public static let importCsv: UInt32 = 3
    public static let exportAnkiPackage: UInt32 = 4
}

public enum MediaMethod {
    public static let checkMedia: UInt32 = 0
    public static let addMediaFile: UInt32 = 1
    public static let trashMediaFiles: UInt32 = 2
    public static let emptyTrash: UInt32 = 3
    public static let restoreTrash: UInt32 = 4
}

public enum DeckConfigMethod {
    public static let getDeckConfig: UInt32 = 1
    public static let removeDeckConfig: UInt32 = 5
    public static let getDeckConfigsForUpdate: UInt32 = 6
    public static let updateDeckConfigs: UInt32 = 7
}

public enum ConfigMethod {
    public static let getConfigBool: UInt32 = 5
    public static let setConfigBool: UInt32 = 6
    public static let getPreferences: UInt32 = 9
    public static let setPreferences: UInt32 = 10
}

public enum SyncMethod {
    public static let syncMedia: UInt32 = 0
    public static let abortMediaSync: UInt32 = 1
    public static let mediaSyncStatus: UInt32 = 2
    public static let syncLogin: UInt32 = 3
    public static let syncStatus: UInt32 = 4
    public static let syncCollection: UInt32 = 5
    public static let fullUploadOrDownload: UInt32 = 6
    public static let abortSync: UInt32 = 7
    public static let setCustomCertificate: UInt32 = 8
}
