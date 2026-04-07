import Foundation
import Observation

enum CustomStudyMode: String, CaseIterable, Identifiable {
    case increaseNewLimit = "Increase today's new card limit"
    case increaseReviewLimit = "Increase today's review limit"
    case reviewForgotten = "Review forgotten cards"
    case reviewAhead = "Review ahead"
    case previewNew = "Preview new cards"
    case cramDue = "Study by card state or tag"

    var id: String {
        rawValue
    }
}

@Observable
@MainActor
final class CustomStudyModel {
    var deckId: Int64
    var selectedMode: CustomStudyMode = .increaseNewLimit
    var defaults: Anki_Scheduler_CustomStudyDefaultsResponse?
    var isLoading = false
    var error: AnkiError?

    var newLimitDelta: Int32 = 10
    var reviewLimitDelta: Int32 = 20
    var forgotDays: UInt32 = 1
    var reviewAheadDays: UInt32 = 1
    var previewDays: UInt32 = 1
    var cramCardLimit: UInt32 = 100
    var cramKind: Anki_Scheduler_CustomStudyRequest.Cram.CramKind = .due
    var tagsToInclude: [String] = []
    var tagsToExclude: [String] = []

    private let service: AnkiServiceProtocol

    init(service: AnkiServiceProtocol, deckId: Int64) {
        self.service = service
        self.deckId = deckId
    }

    func loadDefaults() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await service.customStudyDefaults(deckId: deckId)
            defaults = response
            newLimitDelta = Int32(response.extendNew)
            reviewLimitDelta = Int32(response.extendReview)
            error = nil
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func createCustomStudy() async -> Bool {
        do {
            var req = Anki_Scheduler_CustomStudyRequest()
            req.deckID = deckId
            switch selectedMode {
                case .increaseNewLimit:
                    req.newLimitDelta = newLimitDelta
                case .increaseReviewLimit:
                    req.reviewLimitDelta = reviewLimitDelta
                case .reviewForgotten:
                    req.forgotDays = forgotDays
                case .reviewAhead:
                    req.reviewAheadDays = reviewAheadDays
                case .previewNew:
                    req.previewDays = previewDays
                case .cramDue:
                    var cram = Anki_Scheduler_CustomStudyRequest.Cram()
                    cram.kind = cramKind
                    cram.cardLimit = cramCardLimit
                    cram.tagsToInclude = tagsToInclude
                    cram.tagsToExclude = tagsToExclude
                    req.cram = cram
            }
            _ = try await service.customStudy(request: req)
            error = nil
            return true
        } catch let ankiError as AnkiError {
            error = ankiError
            return false
        } catch {
            return false
        }
    }
}
