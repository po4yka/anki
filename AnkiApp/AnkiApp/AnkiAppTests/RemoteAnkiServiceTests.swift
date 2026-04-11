@testable import AppleBridgeCore
import Foundation
import SwiftProtobuf
import Testing

@Suite(.serialized)
struct RemoteAnkiServiceTests {
    @Test
    func encodesNoteDeckAndNotetypeRequests() async throws {
        let transport = RecordingBackendTransport()
        let service = RemoteAnkiService(transport: transport)

        var note = Anki_Notes_Note()
        note.id = 101
        var addResponse = Anki_Notes_AddNoteResponse()
        addResponse.noteID = 101

        try await transport.enqueueResponse(note)
        try await transport.enqueueResponse(addResponse)
        try await transport.enqueueResponse(Anki_Collection_OpChanges())
        try await transport.enqueueResponse(Anki_Decks_Deck())
        try await transport.enqueueResponse(Anki_Collection_OpChanges())
        try await transport.enqueueResponse(Anki_Notetypes_NotetypeNames())

        let createdNote = try await service.newNote(notetypeId: 42)
        #expect(createdNote.id == 101)
        let addedNote = try await service.addNote(note: note, deckId: 55)
        #expect(addedNote.noteID == 101)
        let _: Anki_Collection_OpChanges = try await service.updateNotes(notes: [note])
        let _: Anki_Decks_Deck = try await service.getDeck(id: 88)
        let _: Anki_Collection_OpChanges = try await service.updateDeck(deck: Anki_Decks_Deck())
        let _: Anki_Notetypes_NotetypeNames = try await service.getNotetypeNames()

        let invocations = await transport.allInvocations()
        #expect(invocations.count == 6)

        let newNoteRequest = try Anki_Notetypes_NotetypeId(serializedBytes: invocations[0].payload)
        #expect(invocations[0].service == ServiceIndex.notes)
        #expect(invocations[0].method == NotesMethod.newNote)
        #expect(newNoteRequest.ntid == 42)

        let addNoteRequest = try Anki_Notes_AddNoteRequest(serializedBytes: invocations[1].payload)
        #expect(invocations[1].service == ServiceIndex.notes)
        #expect(invocations[1].method == NotesMethod.addNote)
        #expect(addNoteRequest.note.id == 101)
        #expect(addNoteRequest.deckID == 55)

        let updateNotesRequest = try Anki_Notes_UpdateNotesRequest(serializedBytes: invocations[2].payload)
        #expect(invocations[2].service == ServiceIndex.notes)
        #expect(invocations[2].method == NotesMethod.updateNotes)
        #expect(updateNotesRequest.notes.count == 1)

        let getDeckRequest = try Anki_Decks_DeckId(serializedBytes: invocations[3].payload)
        #expect(invocations[3].service == ServiceIndex.decks)
        #expect(invocations[3].method == DecksMethod.getDeck)
        #expect(getDeckRequest.did == 88)

        #expect(invocations[4].service == ServiceIndex.decks)
        #expect(invocations[4].method == DecksMethod.updateDeck)
        #expect(invocations[5].service == ServiceIndex.notetypes)
        #expect(invocations[5].method == NotetypesMethod.getNotetypeNames)
    }

    @Test
    func encodesImportAndMediaRequests() async throws {
        let transport = RecordingBackendTransport()
        let service = RemoteAnkiService(transport: transport)

        var csvMetadata = Anki_ImportExport_CsvMetadata()
        csvMetadata.delimiter = .tab
        var exportedCount = Anki_Generic_UInt32()
        exportedCount.val = 12
        var mediaPath = Anki_Generic_String()
        mediaPath.val = "audio.mp3"

        try await transport.enqueueResponse(csvMetadata)
        try await transport.enqueueResponse(exportedCount)
        try await transport.enqueueResponse(mediaPath)

        let metadata = try await service.getCsvMetadata(
            path: "/tmp/input.csv",
            delimiter: .tab,
            notetypeId: 7,
            deckId: 8,
            isHtml: true
        )
        #expect(metadata.delimiter == .tab)
        let exported = try await service.exportAnkiPackage(
            outPath: "/tmp/export.apkg",
            options: Anki_ImportExport_ExportAnkiPackageOptions(),
            limit: Anki_ImportExport_ExportLimit()
        )
        #expect(exported == 12)
        let storedMediaName = try await service.addMediaFile(
            desiredName: "audio.mp3",
            data: Data([0x01, 0x02, 0x03])
        )
        #expect(storedMediaName == "audio.mp3")

        let invocations = await transport.allInvocations()
        #expect(invocations.count == 3)

        let metadataRequest = try Anki_ImportExport_CsvMetadataRequest(serializedBytes: invocations[0].payload)
        #expect(invocations[0].service == ServiceIndex.importExport)
        #expect(invocations[0].method == ImportExportMethod.getCsvMetadata)
        #expect(metadataRequest.path == "/tmp/input.csv")
        #expect(metadataRequest.delimiter == .tab)
        #expect(metadataRequest.notetypeID == 7)
        #expect(metadataRequest.deckID == 8)
        #expect(metadataRequest.isHtml)

        let exportRequest = try Anki_ImportExport_ExportAnkiPackageRequest(serializedBytes: invocations[1].payload)
        #expect(invocations[1].service == ServiceIndex.importExport)
        #expect(invocations[1].method == ImportExportMethod.exportAnkiPackage)
        #expect(exportRequest.outPath == "/tmp/export.apkg")

        let mediaRequest = try Anki_Media_AddMediaFileRequest(serializedBytes: invocations[2].payload)
        #expect(invocations[2].service == ServiceIndex.media)
        #expect(invocations[2].method == MediaMethod.addMediaFile)
        #expect(mediaRequest.desiredName == "audio.mp3")
        #expect(mediaRequest.data == Data([0x01, 0x02, 0x03]))
    }

    @Test
    func encodesSchedulerBackupAndImageOcclusionRequests() async throws {
        let transport = RecordingBackendTransport()
        let service = RemoteAnkiService(transport: transport)

        var backupCreated = Anki_Generic_Bool()
        backupCreated.val = true
        try await transport.enqueueResponse(backupCreated)
        try await transport.enqueueResponse(Anki_Scheduler_CustomStudyDefaultsResponse())
        try await transport.enqueueResponse(Anki_ImageOcclusion_GetImageForOcclusionResponse())
        try await transport.enqueueResponse(Anki_CardRendering_ExtractAvTagsResponse())
        try await transport.enqueueResponse(Anki_Generic_StringList())

        let created = try await service.createBackup(
            backupFolder: "/tmp/backups",
            force: true,
            waitForCompletion: false
        )
        #expect(created)
        let _: Anki_Scheduler_CustomStudyDefaultsResponse = try await service.customStudyDefaults(deckId: 77)
        let _: Anki_ImageOcclusion_GetImageForOcclusionResponse = try await service.getImageForOcclusion(path: "/tmp/image.png")
        let _: Anki_CardRendering_ExtractAvTagsResponse = try await service.extractAvTags(
            text: "[sound:test.mp3]",
            questionSide: true
        )
        let _: Anki_Generic_StringList = try await service.allTags()

        let invocations = await transport.allInvocations()
        #expect(invocations.count == 5)

        let backupRequest = try Anki_Collection_CreateBackupRequest(serializedBytes: invocations[0].payload)
        #expect(invocations[0].service == ServiceIndex.collection)
        #expect(invocations[0].method == CollectionMethod.createBackup)
        #expect(backupRequest.backupFolder == "/tmp/backups")
        #expect(backupRequest.force)
        #expect(!backupRequest.waitForCompletion)

        let customStudyRequest = try Anki_Scheduler_CustomStudyDefaultsRequest(serializedBytes: invocations[1].payload)
        #expect(invocations[1].service == ServiceIndex.scheduler)
        #expect(invocations[1].method == SchedulerMethod.customStudyDefaults)
        #expect(customStudyRequest.deckID == 77)

        let imageRequest = try Anki_ImageOcclusion_GetImageForOcclusionRequest(serializedBytes: invocations[2].payload)
        #expect(invocations[2].service == ServiceIndex.imageOcclusion)
        #expect(invocations[2].method == ImageOcclusionMethod.getImageForOcclusion)
        #expect(imageRequest.path == "/tmp/image.png")

        let avTagsRequest = try Anki_CardRendering_ExtractAvTagsRequest(serializedBytes: invocations[3].payload)
        #expect(invocations[3].service == ServiceIndex.cardRendering)
        #expect(invocations[3].method == CardRenderingMethod.extractAvTags)
        #expect(avTagsRequest.text == "[sound:test.mp3]")
        #expect(avTagsRequest.questionSide)

        #expect(invocations[4].service == ServiceIndex.tags)
        #expect(invocations[4].method == TagsMethod.allTags)
    }
}
