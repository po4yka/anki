import Foundation
import Observation
import AppleBridgeCore
import AppleSharedUI

@Observable
@MainActor
final class MediaCheckModel {
    var isChecking = false
    var isProcessing = false
    var checkResult: CheckResult?
    var errorMessage: String?

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol) {
        self.service = service
    }

    struct CheckResult {
        let unused: [String]
        let missing: [String]
        let report: String
        let haveTrash: Bool
    }

    func checkMedia() async {
        isChecking = true
        checkResult = nil
        errorMessage = nil

        do {
            let response = try await service.checkMedia()
            checkResult = CheckResult(
                unused: response.unused,
                missing: response.missing,
                report: response.report,
                haveTrash: response.haveTrash
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isChecking = false
    }

    func trashUnused() async {
        guard let result = checkResult, !result.unused.isEmpty else { return }

        isProcessing = true
        errorMessage = nil

        do {
            try await service.trashMediaFiles(filenames: result.unused)
            await checkMedia()
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    func emptyTrash() async {
        isProcessing = true
        errorMessage = nil

        do {
            try await service.emptyTrash()
            await checkMedia()
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    func restoreTrash() async {
        isProcessing = true
        errorMessage = nil

        do {
            try await service.restoreTrash()
            await checkMedia()
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }
}
