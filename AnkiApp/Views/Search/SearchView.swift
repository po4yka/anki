import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var model: SearchModel?

    var body: some View {
        Group {
            if let model {
                VStack(spacing: 0) {
                    SearchBar(model: model)
                        .padding()

                    Divider()

                    Table(model.results) {
                        TableColumn("Question") { row in
                            SearchResultRow(row: row)
                        }
                        TableColumn("Deck", value: \.deckName)
                        TableColumn("Due") { row in
                            Text(row.due)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Browse")
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear {
            if model == nil {
                model = SearchModel(service: appState.service)
            }
        }
        .ankiErrorAlert($model?.error)
    }
}

private struct SearchBar: View {
    let model: SearchModel

    var body: some View {
        @Bindable var model = model
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search notes...", text: $model.query)
                .textFieldStyle(.plain)
                .onSubmit {
                    Task { await model.search() }
                }
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    Task { await model.search() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    SearchView()
        .environment(AppState())
}
