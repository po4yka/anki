import Foundation
import Observation

@Observable
@MainActor
final class DeckConfigModel {
    var configsForUpdate: Anki_DeckConfig_DeckConfigsForUpdate?
    var selectedConfigIndex: Int = 0
    var isLoading = false
    var error: AnkiError?

    let deckId: Int64
    let deckName: String
    private let service: AnkiServiceProtocol

    var fsrsEnabled: Bool {
        get { configsForUpdate?.fsrs ?? false }
        set { configsForUpdate?.fsrs = newValue }
    }

    var fsrsReschedule: Bool = false

    var allConfigs: [Anki_DeckConfig_DeckConfigsForUpdate.ConfigWithExtra] {
        configsForUpdate?.allConfig ?? []
    }

    var selectedConfig: Anki_DeckConfig_DeckConfig? {
        get {
            guard selectedConfigIndex < allConfigs.count else { return nil }
            return allConfigs[selectedConfigIndex].config
        }
        set {
            guard let newValue, selectedConfigIndex < allConfigs.count else { return }
            configsForUpdate?.allConfig[selectedConfigIndex].config = newValue
        }
    }

    init(deckId: Int64, deckName: String, service: AnkiServiceProtocol) {
        self.deckId = deckId
        self.deckName = deckName
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            configsForUpdate = try await service.getDeckConfigsForUpdate(deckId: deckId)
            if let currentConfigId = configsForUpdate?.currentDeck.configID {
                selectedConfigIndex = allConfigs.firstIndex { $0.config.id == currentConfigId } ?? 0
            }
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }

    func save() async {
        guard let configsForUpdate else { return }
        do {
            var req = Anki_DeckConfig_UpdateDeckConfigsRequest()
            req.targetDeckID = deckId
            req.configs = configsForUpdate.allConfig.map(\.config)
            req.mode = .normal
            req.limits = configsForUpdate.currentDeck.limits
            req.fsrs = configsForUpdate.fsrs
            req.fsrsReschedule = fsrsReschedule
            req.newCardsIgnoreReviewLimit = configsForUpdate.newCardsIgnoreReviewLimit
            req.applyAllParentLimits = configsForUpdate.applyAllParentLimits
            _ = try await service.updateDeckConfigs(request: req)
        } catch let ankiError as AnkiError {
            error = ankiError
        } catch {}
    }
}
