import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class ObsidianModel {
    var vaultPath: URL?
    var scanPreview: ObsidianScanPreview?
    var isScanning: Bool = false
    var error: String?

    private let atlas: AtlasService

    init(atlas: AtlasService) {
        self.atlas = atlas
    }

    func selectVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Obsidian Vault"
        if panel.runModal() == .OK {
            vaultPath = panel.url
        }
    }

    func scan() async {
        guard let vaultPath else {
            error = "No vault path selected"
            return
        }
        isScanning = true
        error = nil
        let request = ObsidianScanRequest(vaultPath: vaultPath.path)
        do {
            let result: ObsidianScanPreview = try await atlas.command(method: "obsidian_scan", request: request)
            scanPreview = result
        } catch {
            self.error = error.localizedDescription
            scanPreview = nil
        }
        isScanning = false
    }
}
