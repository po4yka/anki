import Foundation
import AppleBridgeCore

enum PreferencesTab: String, Hashable {
    case general
    case scheduling
    case review
    case backups
    case profiles
    case appearance
    case sync
    case atlas
    case about
}

enum AtlasSetupStateKind: Equatable {
    case ready
    case needsConfiguration
    case unavailable
}

struct AtlasSetupChecklistItem: Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let isSatisfied: Bool
}

struct AtlasSetupStatus: Equatable {
    let kind: AtlasSetupStateKind
    let title: String
    let summary: String
    let guidance: String?
    let checklist: [AtlasSetupChecklistItem]
    let showsRetryAction: Bool
}

extension AtlasConfig {
    var requiresEmbeddingAPIKey: Bool {
        switch embeddingProvider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "openai", "google":
                true
            default:
                false
        }
    }

    var localSetupChecklist: [AtlasSetupChecklistItem] {
        [
            AtlasSetupChecklistItem(
                id: "postgres",
                title: "PostgreSQL URL",
                detail: "Atlas stores embeddings, search state, and analytics in PostgreSQL.",
                isSatisfied: hasValue(postgresUrl)
            ),
            AtlasSetupChecklistItem(
                id: "provider",
                title: "Embedding Provider",
                detail: "Choose the service Atlas will use to build semantic embeddings.",
                isSatisfied: hasValue(embeddingProvider)
            ),
            AtlasSetupChecklistItem(
                id: "model",
                title: "Embedding Model",
                detail: "Set the exact embedding model name that matches the selected provider.",
                isSatisfied: hasValue(embeddingModel)
            ),
            AtlasSetupChecklistItem(
                id: "apiKey",
                title: requiresEmbeddingAPIKey ? "Embedding API Key" : "Embedding API Key",
                detail: requiresEmbeddingAPIKey
                    ? "Required for OpenAI and Google Gemini embedding providers."
                    : "Not required for FastEmbed and Mock providers.",
                isSatisfied: !requiresEmbeddingAPIKey || hasValue(embeddingApiKey)
            )
        ]
    }

    var localSetupIsComplete: Bool {
        localSetupChecklist.allSatisfy(\.isSatisfied)
    }

    private func hasValue(_ string: String?) -> Bool {
        !(string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
