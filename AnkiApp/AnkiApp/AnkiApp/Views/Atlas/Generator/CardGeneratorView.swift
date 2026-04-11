import SwiftUI
import AppleBridgeCore
import AppleSharedUI

struct CardGeneratorView: View {
    @Environment(AppState.self) private var appState
    @State private var model: CardGeneratorModel?

    var body: some View {
        guard let atlas = appState.atlasService else {
            return AnyView(AtlasUnavailableView(featureName: "Card Generator", systemImage: "sparkles"))
        }
        let generatorModel = model ?? CardGeneratorModel(atlas: atlas)
        return AnyView(GeneratorContentView(model: generatorModel)
            .onAppear {
                if model == nil { model = generatorModel }
            })
    }
}

private struct GeneratorContentView: View {
    @Environment(AppState.self) private var appState
    @State var model: CardGeneratorModel

    var body: some View {
        Group {
#if os(macOS)
            HSplitView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Source Text")
                        .font(.headline)
                    TextEditor(text: $model.sourceText)
                        .font(.body)
                        .border(Color.secondary.opacity(0.3))
                        .frame(minHeight: 200)

                    TextField("Topic (optional)", text: $model.topic)
                        .textFieldStyle(.roundedBorder)

                    Button("Generate") {
                        Task { await model.generatePreview() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.sourceText.isEmpty || model.isGenerating)

                    if model.isGenerating {
                        ProgressView("Generating...")
                    }

                    Spacer()
                }
                .padding()
                .frame(minWidth: 280)

                VStack(alignment: .leading, spacing: 8) {
                    if (model.preview?.cards ?? []).isEmpty {
                        ContentUnavailableView(
                            "No Cards Yet",
                            systemImage: "rectangle.on.rectangle",
                            description: Text("Enter source text and tap Generate.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("Generated Cards")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top)
                        List(model.preview?.cards ?? []) { card in
                            CardPreviewView(card: card)
                        }

                        Divider()

                        HStack {
                            if let savedCount = model.savedCount {
                                let deckName = model.savedDeckName ?? "selected deck"
                                Label(
                                    "\(savedCount) card\(savedCount == 1 ? "" : "s") added to \(deckName).",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .foregroundStyle(.green)
                                .font(.callout)
                            }
                            if let errorMsg = model.error {
                                Label(errorMsg, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                    .font(.callout)
                            }
                            Spacer()
                            if model.isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Button("Save \(model.preview?.cards.count ?? 0) Cards to Deck") {
                                Task { await model.saveCards(service: appState.service) }
                            }
                            .disabled(model.preview?.cards.isEmpty ?? true || model.isSaving)
                        }
                        .padding([.horizontal, .bottom])
                    }
                }
                .frame(minWidth: 300)
            }
#else
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Source Text")
                        .font(.headline)
                    TextEditor(text: $model.sourceText)
                        .font(.body)
                        .border(Color.secondary.opacity(0.3))
                        .frame(minHeight: 200)

                    TextField("Topic (optional)", text: $model.topic)
                        .textFieldStyle(.roundedBorder)

                    Button("Generate") {
                        Task { await model.generatePreview() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.sourceText.isEmpty || model.isGenerating)

                    if model.isGenerating {
                        ProgressView("Generating...")
                    }
                }
                .padding()

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    if (model.preview?.cards ?? []).isEmpty {
                        ContentUnavailableView(
                            "No Cards Yet",
                            systemImage: "rectangle.on.rectangle",
                            description: Text("Enter source text and tap Generate.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("Generated Cards")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top)
                        List(model.preview?.cards ?? []) { card in
                            CardPreviewView(card: card)
                                .listRowSeparator(.hidden)
                        }
                        .listStyle(.plain)

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            if let savedCount = model.savedCount {
                                let deckName = model.savedDeckName ?? "selected deck"
                                Label(
                                    "\(savedCount) card\(savedCount == 1 ? "" : "s") added to \(deckName).",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .foregroundStyle(.green)
                                .font(.callout)
                            }
                            if let errorMsg = model.error {
                                Label(errorMsg, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                    .font(.callout)
                            }
                            HStack {
                                if model.isSaving {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Spacer()
                                Button("Save \(model.preview?.cards.count ?? 0) Cards to Deck") {
                                    Task { await model.saveCards(service: appState.service) }
                                }
                                .disabled(model.preview?.cards.isEmpty ?? true || model.isSaving)
                            }
                        }
                        .padding()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
#endif
        }
        .navigationTitle("Card Generator")
    }
}
