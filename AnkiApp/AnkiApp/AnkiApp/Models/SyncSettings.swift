import AppleBridgeCore
import AppleSharedUI
import Foundation

enum SyncSettings {
    static var storedUsername: String {
        UserDefaults.standard.string(forKey: "ankiwebUsername") ?? ""
    }

    static var syncOnOpen: Bool {
        UserDefaults.standard.bool(forKey: "syncOnOpen")
    }

    static var autoSyncIntervalMinutes: Int {
        UserDefaults.standard.integer(forKey: "autoSyncInterval")
    }
}
