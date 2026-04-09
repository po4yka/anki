import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ProfileManager {
    struct Profile: Identifiable, Codable, Hashable {
        var id: String {
            path
        }

        let name: String
        let path: String
    }

    private static let profilesKey = "ankiProfiles"
    private static let activeProfileKey = "ankiActiveProfile"

    var profiles: [Profile] = []
    var activeProfilePath: String = ""

    init() {
        loadProfiles()
    }

    func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: Self.profilesKey),
           let decoded = try? JSONDecoder().decode([Profile].self, from: data) {
            profiles = decoded
        }
        activeProfilePath = UserDefaults.standard.string(forKey: Self.activeProfileKey) ?? ""
    }

    func addProfile(name: String, path: String) {
        let profile = Profile(name: name, path: path)
        if !profiles.contains(where: { $0.path == path }) {
            profiles.append(profile)
            saveProfiles()
        }
    }

    func removeProfile(at offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
        saveProfiles()
    }

    func setActive(path: String) {
        activeProfilePath = path
        UserDefaults.standard.set(path, forKey: Self.activeProfileKey)
    }

    func switchProfile(to profile: Profile, appState: AppState) async {
        if appState.isCollectionOpen {
            await appState.closeCollection()
        }
        setActive(path: profile.path)
        await appState.openCollection(path: profile.path)
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Self.profilesKey)
        }
    }
}
