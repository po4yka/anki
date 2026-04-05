import SwiftUI
import Charts

struct StatisticsView: View {
    @Environment(AppState.self) private var appState
    @State private var model: StatsModel?

    var body: some View {
        Group {
            if let model {
                if !appState.isCollectionOpen {
                    ContentUnavailableView {
                        Label("No Collection Open", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Open a collection from Preferences to view statistics.")
                    } actions: {
                        Button("Open Preferences") {
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if model.isLoading {
                    ProgressView("Loading statistics...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(.default, value: model.isLoading)
                } else {
                    TabView {
                        ReviewChart(model: model)
                            .tabItem {
                                Label("Reviews", systemImage: "chart.bar")
                            }
                    }
                    .navigationTitle("Statistics")
                }
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear {
            if model == nil {
                model = StatsModel(service: appState.service)
                Task { await model?.load() }
            }
        }
        .ankiErrorAlert(Binding(
            get: { model?.error },
            set: { model?.error = $0 }
        ))
    }
}

#Preview {
    StatisticsView()
        .environment(AppState())
}
