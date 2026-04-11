import Foundation
import Observation
import SwiftUI
import AppleBridgeCore
import AppleSharedUI

@Observable
@MainActor
final class ProfileManager {
    enum StorageKind: String, Codable, Hashable {
        case externalPath
        case managedLocal
    }

    struct Profile: Identifiable, Codable, Hashable {
        let id: String
        let name: String
        let path: String
        let storageKind: StorageKind
        let importedSourcePath: String?

        init(
            id: String = UUID().uuidString,
            name: String,
            path: String,
            storageKind: StorageKind,
            importedSourcePath: String? = nil
        ) {
            self.id = id
            self.name = name
            self.path = path
            self.storageKind = storageKind
            self.importedSourcePath = importedSourcePath
        }

        var displayPath: String {
            switch storageKind {
                case .externalPath:
                    path
                case .managedLocal:
                    "On-device copy"
            }
        }
    }

    private struct LegacyProfile: Codable {
        let name: String
        let path: String
    }

    private static let profilesKey = "ankiProfiles"
    private static let activeProfileKey = "ankiActiveProfileID"

    var profiles: [Profile] = []
    var activeProfileID: String = ""

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let profilesRootOverride: URL?

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        profilesRootOverride: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.profilesRootOverride = profilesRootOverride
        loadProfiles()
    }

    var activeProfile: Profile? {
        profiles.first(where: { $0.id == activeProfileID })
    }

    func loadProfiles() {
        if let data = defaults.data(forKey: Self.profilesKey) {
            if let decoded = try? JSONDecoder().decode([Profile].self, from: data) {
                profiles = decoded
            } else if let decoded = try? JSONDecoder().decode([LegacyProfile].self, from: data) {
                profiles = decoded.map {
                    Profile(id: $0.path, name: $0.name, path: $0.path, storageKind: .externalPath)
                }
                saveProfiles()
            }
        }

        let legacyActivePath = defaults.string(forKey: Self.activeProfileKey)
        activeProfileID = legacyActivePath ?? ""
        if activeProfileID.isEmpty,
           let oldPath = defaults.string(forKey: "ankiActiveProfile"),
           let profile = profiles.first(where: { $0.path == oldPath }) {
            activeProfileID = profile.id
            defaults.set(profile.id, forKey: Self.activeProfileKey)
        }
    }

    func addProfile(name: String, path: String) {
        let profile = Profile(name: name, path: path, storageKind: .externalPath)
        guard !profiles.contains(where: { $0.path == path && $0.storageKind == .externalPath }) else { return }
        profiles.append(profile)
        saveProfiles()
    }

    @discardableResult
    func importLocalProfile(from sourceURL: URL, name: String? = nil) throws -> Profile {
        let rootURL = try localProfilesRoot()
        let profileID = UUID().uuidString
        let profileRootURL = rootURL.appendingPathComponent(profileID, isDirectory: true)
        try fileManager.createDirectory(at: profileRootURL, withIntermediateDirectories: true)

        let collectionURL = profileRootURL.appendingPathComponent("collection.anki2")
        let mediaFolderURL = profileRootURL.appendingPathComponent("collection.media", isDirectory: true)
        let mediaDbURL = profileRootURL.appendingPathComponent("collection.media.db2")

        let sourceDirectoryURL = sourceURL.deletingLastPathComponent()
        let sourceMediaFolderURL = sourceDirectoryURL.appendingPathComponent("collection.media", isDirectory: true)
        let sourceMediaDbURL = sourceDirectoryURL.appendingPathComponent("collection.media.db2")

        let needsScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try copyItemReplacingIfNeeded(at: sourceURL, to: collectionURL)
        if fileManager.fileExists(atPath: sourceMediaFolderURL.path) {
            try copyItemReplacingIfNeeded(at: sourceMediaFolderURL, to: mediaFolderURL)
        } else {
            try fileManager.createDirectory(at: mediaFolderURL, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: sourceMediaDbURL.path) {
            try copyItemReplacingIfNeeded(at: sourceMediaDbURL, to: mediaDbURL)
        } else {
            _ = fileManager.createFile(atPath: mediaDbURL.path, contents: Data())
        }

        let profileName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = if let profileName, !profileName.isEmpty {
            profileName
        } else {
            sourceURL.deletingPathExtension().lastPathComponent
        }

        let profile = Profile(
            id: profileID,
            name: resolvedName,
            path: collectionURL.path,
            storageKind: .managedLocal,
            importedSourcePath: sourceURL.path
        )
        profiles.append(profile)
        saveProfiles()
        return profile
    }

    func removeProfile(at offsets: IndexSet) {
        let removedProfiles = offsets.map { profiles[$0] }
        profiles.remove(atOffsets: offsets)
        for profile in removedProfiles where profile.storageKind == .managedLocal {
            try? fileManager.removeItem(at: profileRootURL(for: profile))
        }
        if !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = ""
            defaults.removeObject(forKey: Self.activeProfileKey)
        }
        saveProfiles()
    }

    func setActive(profileID: String) {
        activeProfileID = profileID
        defaults.set(profileID, forKey: Self.activeProfileKey)
    }

    func switchProfile(to profile: Profile, appState: AppState) async {
        if appState.isCollectionOpen {
            await appState.closeCollection()
        }
        setActive(profileID: profile.id)
        await appState.openCollection(path: profile.path)
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Self.profilesKey)
        }
    }

    private func localProfilesRoot() throws -> URL {
        if let profilesRootOverride {
            try fileManager.createDirectory(at: profilesRootOverride, withIntermediateDirectories: true)
            return profilesRootOverride
        }
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootURL = baseURL.appendingPathComponent("AnkiLocalProfiles", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func profileRootURL(for profile: Profile) -> URL {
        URL(fileURLWithPath: profile.path)
            .deletingLastPathComponent()
    }

    private func copyItemReplacingIfNeeded(at sourceURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
}
