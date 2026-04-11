import Foundation
import Observation

@Observable
@MainActor
final class ObsidianModel {
    var vaultPath: URL?
    var scanPreview: ObsidianScanPreview?
    var isScanning: Bool = false
    var error: String?

    private let atlas: any AtlasServiceProtocol

    init(atlas: any AtlasServiceProtocol) {
        self.atlas = atlas
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
            let result = try await atlas.obsidianScan(request)
            scanPreview = result
        } catch {
            self.error = error.localizedDescription
            scanPreview = nil
        }
        isScanning = false
    }
}
