import Charts
import SwiftUI

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
                    VStack(spacing: 0) {
                        Picker("Time Range", selection: Binding(
                            get: { model.selectedTimeRange },
                            set: { newValue in
                                model.selectedTimeRange = newValue
                                Task { await model.load() }
                            }
                        )) {
                            ForEach(StatsTimeRange.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 8)

                        TabView(selection: Binding(
                            get: { model.selectedTab },
                            set: { model.selectedTab = $0 }
                        )) {
                            TodayStatsView(model: model)
                                .tabItem { Label(StatsTab.today.rawValue, systemImage: StatsTab.today.systemImage) }
                                .tag(StatsTab.today)

                            ReviewChart(model: model)
                                .tabItem { Label(StatsTab.reviews.rawValue, systemImage: StatsTab.reviews.systemImage) }
                                .tag(StatsTab.reviews)

                            CardCountsChart(model: model)
                                .tabItem { Label(StatsTab.cards.rawValue, systemImage: StatsTab.cards.systemImage) }
                                .tag(StatsTab.cards)

                            IntervalChart(model: model)
                                .tabItem { Label(
                                    StatsTab.intervals.rawValue,
                                    systemImage: StatsTab.intervals.systemImage
                                ) }
                                .tag(StatsTab.intervals)

                            EaseChart(model: model)
                                .tabItem { Label(StatsTab.ease.rawValue, systemImage: StatsTab.ease.systemImage) }
                                .tag(StatsTab.ease)

                            FutureDueChart(model: model)
                                .tabItem { Label(
                                    StatsTab.futureDue.rawValue,
                                    systemImage: StatsTab.futureDue.systemImage
                                ) }
                                .tag(StatsTab.futureDue)

                            AddedChart(model: model)
                                .tabItem { Label(StatsTab.added.rawValue, systemImage: StatsTab.added.systemImage) }
                                .tag(StatsTab.added)

                            RetentionView(model: model)
                                .tabItem { Label(
                                    StatsTab.retention.rawValue,
                                    systemImage: StatsTab.retention.systemImage
                                ) }
                                .tag(StatsTab.retention)
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
