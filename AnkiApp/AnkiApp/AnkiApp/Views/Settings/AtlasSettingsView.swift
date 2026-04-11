import SwiftUI

struct AtlasSettingsView: View {
    @Environment(AppState.self) private var appState

    @AppStorage("atlasEmbeddingProvider") private var provider = "google"
    @AppStorage("atlasEmbeddingModel") private var model = "gemini-embedding-2-preview"
    @AppStorage("atlasEmbeddingDimension") private var dimension = 768

    @State private var apiKey = ""
    @State private var postgresUrl = ""
    @State private var statusMessage: String?

    private let providers = ["openai", "google", "fastembed", "mock"]

    private let validDimensions = [384, 768, 1024, 1536, 3072]

    private var needsApiKey: Bool {
        provider == "openai" || provider == "google"
    }

    var body: some View {
        Form {
            Section("Embedding Provider") {
                Picker("Provider", selection: $provider) {
                    Text("OpenAI").tag("openai")
                    Text("Google Gemini").tag("google")
                    Text("FastEmbed (local)").tag("fastembed")
                    Text("Mock (testing)").tag("mock")
                }
                .onChange(of: provider) { _, newValue in
                    applyProviderDefaults(newValue)
                }

                TextField("Model", text: $model)
                    .textFieldStyle(.roundedBorder)

                Picker("Dimension", selection: $dimension) {
                    ForEach(validDimensions, id: \.self) { dim in
                        Text("\(dim)").tag(dim)
                    }
                }
            }

            if needsApiKey {
                Section("API Key") {
                    SecureField("Embedding API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Required for \(provider == "google" ? "Google Gemini" : "OpenAI") provider")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Database") {
                SecureField("PostgreSQL URL", text: $postgresUrl)
                    .textFieldStyle(.roundedBorder)
                Text("e.g. postgresql://user:pass@localhost:5432/ankiatlas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save & Reinitialize") {
                        Task { await save() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { loadSecrets() }
    }

    private func loadSecrets() {
        apiKey = KeychainHelper.loadAtlasApiKey() ?? ""
        postgresUrl = KeychainHelper.loadAtlasPostgresUrl() ?? ""
    }

    private func save() async {
        KeychainHelper.saveAtlasApiKey(apiKey)
        KeychainHelper.saveAtlasPostgresUrl(postgresUrl)
        statusMessage = "Reinitializing Atlas..."
        await appState.reinitializeAtlas()
        statusMessage = appState.isAtlasAvailable ? "Atlas initialized" : "Atlas unavailable"
    }

    private func applyProviderDefaults(_ newProvider: String) {
        switch newProvider {
            case "google":
                model = "gemini-embedding-2-preview"
                dimension = 768
            case "openai":
                model = "text-embedding-3-small"
                dimension = 1536
            case "fastembed":
                model = "BAAI/bge-small-en-v1.5"
                dimension = 384
            case "mock":
                model = "mock"
                dimension = 384
            default:
                break
        }
    }
}

#Preview {
    AtlasSettingsView()
        .environment(AppState())
}
