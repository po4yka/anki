import SwiftUI

struct CardGeneratorView: View {
    @Environment(AppState.self) private var appState
    @State private var model: CardGeneratorModel?

    var body: some View {
        guard let atlas = appState.atlasService else {
            return AnyView(ContentUnavailableView(
                "Atlas Not Configured",
                systemImage: "sparkles",
                description: Text("Configure Atlas in Settings to use Card Generator.")
            ))
        }
        let generatorModel = model ?? CardGeneratorModel(atlas: atlas)
        return AnyView(GeneratorContentView(model: generatorModel)
            .onAppear {
                if model == nil { model = generatorModel }
            })
    }
}

private struct GeneratorContentView: View {
    @State var model: CardGeneratorModel

    var body: some View {
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
                }
            }
            .frame(minWidth: 300)
        }
        .navigationTitle("Card Generator")
    }
}
