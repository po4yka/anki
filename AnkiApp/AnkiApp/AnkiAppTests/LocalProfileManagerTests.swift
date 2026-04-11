@testable import AnkiApp
import Foundation
import Testing

struct LocalProfileManagerTests {
    @Test
    @MainActor
    func importingLocalProfileCopiesCollectionAndMediaIntoManagedStorage() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceRoot = tempRoot.appendingPathComponent("source", isDirectory: true)
        let managedRoot = tempRoot.appendingPathComponent("managed", isDirectory: true)
        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: managedRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let collectionURL = sourceRoot.appendingPathComponent("collection.anki2")
        let mediaFolderURL = sourceRoot.appendingPathComponent("collection.media", isDirectory: true)
        let mediaDbURL = sourceRoot.appendingPathComponent("collection.media.db2")
        try Data("collection".utf8).write(to: collectionURL)
        try fileManager.createDirectory(at: mediaFolderURL, withIntermediateDirectories: true)
        try Data("media".utf8).write(to: mediaFolderURL.appendingPathComponent("one.txt"))
        try Data("db".utf8).write(to: mediaDbURL)

        let manager = ProfileManager(
            defaults: makeIsolatedUserDefaults(),
            fileManager: fileManager,
            profilesRootOverride: managedRoot
        )

        let profile = try manager.importLocalProfile(from: collectionURL, name: "My Deck")

        #expect(profile.storageKind == .managedLocal)
        #expect(profile.name == "My Deck")
        #expect(fileManager.fileExists(atPath: profile.path))

        let copiedRoot = URL(fileURLWithPath: profile.path).deletingLastPathComponent()
        #expect(fileManager.fileExists(atPath: copiedRoot.appendingPathComponent("collection.media").path))
        #expect(fileManager.fileExists(atPath: copiedRoot.appendingPathComponent("collection.media.db2").path))
    }

    @Test
    @MainActor
    func removingManagedProfileDeletesCopiedDirectory() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceRoot = tempRoot.appendingPathComponent("source", isDirectory: true)
        let managedRoot = tempRoot.appendingPathComponent("managed", isDirectory: true)
        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: managedRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let collectionURL = sourceRoot.appendingPathComponent("collection.anki2")
        try Data("collection".utf8).write(to: collectionURL)

        let manager = ProfileManager(
            defaults: makeIsolatedUserDefaults(),
            fileManager: fileManager,
            profilesRootOverride: managedRoot
        )
        let profile = try manager.importLocalProfile(from: collectionURL)
        let copiedRoot = URL(fileURLWithPath: profile.path).deletingLastPathComponent()

        manager.removeProfile(at: IndexSet(integer: 0))

        #expect(!fileManager.fileExists(atPath: copiedRoot.path))
    }
}
