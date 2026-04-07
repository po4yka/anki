import SwiftUI

struct CustomStudyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CustomStudyModel

    init(service: AnkiServiceProtocol, deckId: Int64) {
        _model = State(initialValue: CustomStudyModel(service: service, deckId: deckId))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Custom Study")
                .font(.headline)
                .padding()

            Form {
                Picker("Study Mode", selection: $model.selectedMode) {
                    ForEach(CustomStudyMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                switch model.selectedMode {
                case .increaseNewLimit:
                    newLimitSection
                case .increaseReviewLimit:
                    reviewLimitSection
                case .reviewForgotten:
                    forgotSection
                case .reviewAhead:
                    reviewAheadSection
                case .previewNew:
                    previewSection
                case .cramDue:
                    cramSection
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create Session") {
                    Task {
                        if await model.createCustomStudy() {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isLoading)
            }
            .padding()
        }
        .frame(width: 420, height: 340)
        .task {
            await model.loadDefaults()
        }
        .ankiErrorAlert(Binding(
            get: { model.error },
            set: { model.error = $0 }
        ))
    }

    @ViewBuilder
    private var newLimitSection: some View {
        let available = model.defaults.map { $0.availableNew + $0.availableNewInChildren } ?? 0
        Stepper("Increase by: \(model.newLimitDelta)", value: $model.newLimitDelta, in: 1...999)
        Text("Available new cards: \(available)")
            .foregroundStyle(.secondary)
            .font(.caption)
    }

    @ViewBuilder
    private var reviewLimitSection: some View {
        let available = model.defaults.map { $0.availableReview + $0.availableReviewInChildren } ?? 0
        Stepper("Increase by: \(model.reviewLimitDelta)", value: $model.reviewLimitDelta, in: 1...999)
        Text("Available review cards: \(available)")
            .foregroundStyle(.secondary)
            .font(.caption)
    }

    @ViewBuilder
    private var forgotSection: some View {
        Stepper("Cards forgotten in last \(model.forgotDays) days", value: $model.forgotDays, in: 1...365)
    }

    @ViewBuilder
    private var reviewAheadSection: some View {
        Stepper("Review cards due in next \(model.reviewAheadDays) days", value: $model.reviewAheadDays, in: 1...365)
    }

    @ViewBuilder
    private var previewSection: some View {
        Stepper("Preview cards added in last \(model.previewDays) days", value: $model.previewDays, in: 1...365)
    }

    @ViewBuilder
    private var cramSection: some View {
        Picker("Card Selection", selection: $model.cramKind) {
            Text("Due cards").tag(Anki_Scheduler_CustomStudyRequest.Cram.CramKind.due)
            Text("New cards").tag(Anki_Scheduler_CustomStudyRequest.Cram.CramKind.new)
            Text("Review cards").tag(Anki_Scheduler_CustomStudyRequest.Cram.CramKind.review)
            Text("All cards").tag(Anki_Scheduler_CustomStudyRequest.Cram.CramKind.all)
        }
        Stepper("Card limit: \(model.cramCardLimit)", value: $model.cramCardLimit, in: 1...9999)
        tagSelector
    }

    @ViewBuilder
    private var tagSelector: some View {
        if let defaults = model.defaults, !defaults.tags.isEmpty {
            DisclosureGroup("Tags") {
                ForEach(defaults.tags, id: \.name) { tag in
                    HStack {
                        Text(tag.name)
                            .lineLimit(1)
                        Spacer()
                        tagToggle(for: tag.name, isInclude: true)
                        tagToggle(for: tag.name, isInclude: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tagToggle(for tagName: String, isInclude: Bool) -> some View {
        let label = isInclude ? "Include" : "Exclude"
        let list = isInclude ? model.tagsToInclude : model.tagsToExclude
        let isOn = list.contains(tagName)
        Toggle(label, isOn: Binding(
            get: { isOn },
            set: { newValue in
                if isInclude {
                    if newValue {
                        model.tagsToInclude.append(tagName)
                        model.tagsToExclude.removeAll { $0 == tagName }
                    } else {
                        model.tagsToInclude.removeAll { $0 == tagName }
                    }
                } else {
                    if newValue {
                        model.tagsToExclude.append(tagName)
                        model.tagsToInclude.removeAll { $0 == tagName }
                    } else {
                        model.tagsToExclude.removeAll { $0 == tagName }
                    }
                }
            }
        ))
        .toggleStyle(.checkbox)
        .labelsHidden()
    }
}
