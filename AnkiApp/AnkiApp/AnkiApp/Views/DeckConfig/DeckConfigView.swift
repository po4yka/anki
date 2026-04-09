import SwiftUI

// swiftlint:disable:next type_body_length
struct DeckConfigView: View {
    @State private var model: DeckConfigModel
    @Environment(\.dismiss) private var dismiss

    init(deckId: Int64, deckName: String, service: AnkiServiceProtocol) {
        _model = State(initialValue: DeckConfigModel(deckId: deckId, deckName: deckName, service: service))
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isLoading {
                ProgressView("Loading config...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.configsForUpdate != nil {
                presetPicker
                    .padding()

                Divider()

                TabView {
                    newCardsTab
                        .tabItem { Label("New Cards", systemImage: "sparkles") }
                    reviewsTab
                        .tabItem { Label("Reviews", systemImage: "arrow.clockwise") }
                    lapsesTab
                        .tabItem { Label("Lapses", systemImage: "exclamationmark.triangle") }
                    advancedTab
                        .tabItem { Label("Advanced", systemImage: "gearshape.2") }
                }
                .padding()

                Divider()

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        Task {
                            await model.save()
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 450)
        .navigationTitle("Options for \(model.deckName)")
        .task { await model.load() }
        .ankiErrorAlert(Binding(
            get: { model.error },
            set: { model.error = $0 }
        ))
    }

    // MARK: - Preset Picker

    private var presetPicker: some View {
        HStack {
            Text("Preset:")
            Picker("Preset", selection: $model.selectedConfigIndex) {
                ForEach(Array(model.allConfigs.enumerated()), id: \.offset) { index, item in
                    Text(item.config.name).tag(index)
                }
            }
            .labelsHidden()
        }
    }

    // MARK: - New Cards Tab

    private var newCardsTab: some View {
        Form {
            if var config = model.selectedConfig?.config {
                LabeledContent("Learning Steps") {
                    TextField("Steps", text: stepsBinding(
                        get: { model.selectedConfig?.config.learnSteps ?? [] },
                        set: { steps in config.learnSteps = steps
                            updateConfig(config)
                        }
                    ))
                    .frame(width: 200)
                }
                LabeledContent("Graduating Interval") {
                    HStack {
                        TextField("", value: Binding(
                            get: { model.selectedConfig?.config.graduatingIntervalGood ?? 1 },
                            set: { val in config.graduatingIntervalGood = val
                                updateConfig(config)
                            }
                        ), format: .number)
                            .frame(width: 80)
                        Text("days")
                    }
                }
                LabeledContent("Easy Interval") {
                    HStack {
                        TextField("", value: Binding(
                            get: { model.selectedConfig?.config.graduatingIntervalEasy ?? 4 },
                            set: { val in config.graduatingIntervalEasy = val
                                updateConfig(config)
                            }
                        ), format: .number)
                            .frame(width: 80)
                        Text("days")
                    }
                }
                LabeledContent("New Cards/Day") {
                    TextField("", value: Binding(
                        get: { model.selectedConfig?.config.newPerDay ?? 20 },
                        set: { val in config.newPerDay = val
                            updateConfig(config)
                        }
                    ), format: .number)
                        .frame(width: 80)
                }
            }
        }
    }

    // MARK: - Reviews Tab

    private var reviewsTab: some View {
        Form {
            if var config = model.selectedConfig?.config {
                LabeledContent("Maximum Reviews/Day") {
                    TextField("", value: Binding(
                        get: { model.selectedConfig?.config.reviewsPerDay ?? 200 },
                        set: { val in config.reviewsPerDay = val
                            updateConfig(config)
                        }
                    ), format: .number)
                        .frame(width: 80)
                }
                LabeledContent("Maximum Interval") {
                    HStack {
                        TextField("", value: Binding(
                            get: { model.selectedConfig?.config.maximumReviewInterval ?? 36500 },
                            set: { val in config.maximumReviewInterval = val
                                updateConfig(config)
                            }
                        ), format: .number)
                            .frame(width: 80)
                        Text("days")
                    }
                }
                LabeledContent("Bury Related Reviews") {
                    Toggle("", isOn: Binding(
                        get: { model.selectedConfig?.config.buryReviews ?? false },
                        set: { val in config.buryReviews = val
                            updateConfig(config)
                        }
                    ))
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: - Lapses Tab

    private var lapsesTab: some View {
        Form {
            if var config = model.selectedConfig?.config {
                LabeledContent("Relearning Steps") {
                    TextField("Steps", text: stepsBinding(
                        get: { model.selectedConfig?.config.relearnSteps ?? [] },
                        set: { steps in config.relearnSteps = steps
                            updateConfig(config)
                        }
                    ))
                    .frame(width: 200)
                }
                LabeledContent("Minimum Interval") {
                    HStack {
                        TextField("", value: Binding(
                            get: { model.selectedConfig?.config.minimumLapseInterval ?? 1 },
                            set: { val in config.minimumLapseInterval = val
                                updateConfig(config)
                            }
                        ), format: .number)
                            .frame(width: 80)
                        Text("days")
                    }
                }
                LabeledContent("Leech Threshold") {
                    TextField("", value: Binding(
                        get: { model.selectedConfig?.config.leechThreshold ?? 8 },
                        set: { val in config.leechThreshold = val
                            updateConfig(config)
                        }
                    ), format: .number)
                        .frame(width: 80)
                }
                LabeledContent("Leech Action") {
                    Picker("", selection: Binding(
                        get: { model.selectedConfig?.config.leechAction ?? .suspend },
                        set: { val in config.leechAction = val
                            updateConfig(config)
                        }
                    )) {
                        Text("Suspend Card").tag(Anki_DeckConfig_DeckConfig.Config.LeechAction.suspend)
                        Text("Tag Only").tag(Anki_DeckConfig_DeckConfig.Config.LeechAction.tagOnly)
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
        }
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        Form {
            if var config = model.selectedConfig?.config {
                LabeledContent("Interval Multiplier") {
                    TextField("", value: Binding(
                        get: { model.selectedConfig?.config.intervalMultiplier ?? 1.0 },
                        set: { val in config.intervalMultiplier = val
                            updateConfig(config)
                        }
                    ), format: .number)
                        .frame(width: 80)
                }
                LabeledContent("Hard Multiplier") {
                    TextField("", value: Binding(
                        get: { model.selectedConfig?.config.hardMultiplier ?? 1.2 },
                        set: { val in config.hardMultiplier = val
                            updateConfig(config)
                        }
                    ), format: .number)
                        .frame(width: 80)
                }
                LabeledContent("Easy Multiplier") {
                    TextField("", value: Binding(
                        get: { model.selectedConfig?.config.easyMultiplier ?? 1.3 },
                        set: { val in config.easyMultiplier = val
                            updateConfig(config)
                        }
                    ), format: .number)
                        .frame(width: 80)
                }
                LabeledContent("Show Timer") {
                    Toggle("", isOn: Binding(
                        get: { model.selectedConfig?.config.showTimer ?? false },
                        set: { val in config.showTimer = val
                            updateConfig(config)
                        }
                    ))
                    .labelsHidden()
                }
                LabeledContent("Bury New Siblings") {
                    Toggle("", isOn: Binding(
                        get: { model.selectedConfig?.config.buryNew ?? false },
                        set: { val in config.buryNew = val
                            updateConfig(config)
                        }
                    ))
                    .labelsHidden()
                }

                Section("FSRS Parameters") {
                    LabeledContent("Enable FSRS Scheduler") {
                        Toggle("", isOn: Binding(
                            get: { model.fsrsEnabled },
                            set: { model.fsrsEnabled = $0 }
                        ))
                        .labelsHidden()
                    }

                    if model.fsrsEnabled {
                        LabeledContent("Desired Retention") {
                            TextField("", value: Binding(
                                get: { model.selectedConfig?.config.desiredRetention ?? 0.9 },
                                set: { val in config.desiredRetention = val
                                    updateConfig(config)
                                }
                            ), format: .percent)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                        }

                        LabeledContent("Reschedule on Parameter Change") {
                            Toggle("", isOn: Binding(
                                get: { model.fsrsReschedule },
                                set: { model.fsrsReschedule = $0 }
                            ))
                            .labelsHidden()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func updateConfig(_ config: Anki_DeckConfig_DeckConfig.Config) {
        guard var selected = model.selectedConfig else { return }
        selected.config = config
        model.selectedConfig = selected
    }

    private func stepsBinding(
        get: @escaping () -> [Float],
        set: @escaping ([Float]) -> Void
    ) -> Binding<String> {
        Binding(
            get: { get().map { String(format: "%g", $0) }.joined(separator: " ") },
            set: { text in
                let steps = text.split(separator: " ").compactMap { Float($0) }
                set(steps)
            }
        )
    }
}
