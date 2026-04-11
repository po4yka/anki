import AppleBridgeCore
import AppleSharedUI
import SwiftUI

struct AtlasSearchView: View {
    @Environment(AppState.self) private var appState
    @State private var model: AtlasSearchModel?

    var body: some View {
        guard let atlas = appState.atlasService else {
            return AnyView(AtlasUnavailableView(featureName: "Smart Search", systemImage: "magnifyingglass"))
        }
        return AnyView(SearchContentView(model: model ?? AtlasSearchModel(atlas: atlas))
            .onAppear {
                if model == nil {
                    model = AtlasSearchModel(atlas: atlas)
                }
            })
    }
}

private struct SearchContentView: View {
    @State var model: AtlasSearchModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search notes...", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                Picker("Mode", selection: $model.searchMode) {
                    Text("Hybrid").tag(SearchMode.hybrid)
                    Text("Semantic").tag(SearchMode.semanticOnly)
                    Text("Full-text").tag(SearchMode.ftsOnly)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                Button("Search") {
                    Task { await model.search() }
                }
                .disabled(model.query.isEmpty)
            }
            .padding()

            if model.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.results) { item in
                    AtlasSearchResultRow(item: item)
                }
            }
        }
        .navigationTitle("Smart Search")
    }
}

private struct AtlasSearchResultRow: View {
    let item: SearchResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.headline ?? "")
                .font(.body)
                .lineLimit(2)
            HStack {
                ProgressView(value: item.rrfScore, total: 1.0)
                    .frame(width: 80)
                Text(String(format: "%.2f", item.rrfScore))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                SourceBadge(source: item.matchModality ?? "")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SourceBadge: View {
    let source: String

    var color: Color {
        switch source {
            case "semantic": .purple
            case "fts": .blue
            default: .green
        }
    }

    var body: some View {
        Text(source)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
