import SwiftUI

struct AtlasSetupStatusPanel: View {
    let status: AtlasSetupStatus
    let showChecklist: Bool

    init(status: AtlasSetupStatus, showChecklist: Bool = true) {
        self.status = status
        self.showChecklist = showChecklist
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: status.kind.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(status.kind.tintColor)

                VStack(alignment: .leading, spacing: 6) {
                    Text(status.title)
                        .font(.headline)
                    Text(status.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if showChecklist, !status.checklist.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(status.checklist) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.isSatisfied ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(item.isSatisfied ? Color.green : Color.orange)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let guidance = status.guidance {
                Text(guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct AtlasUnavailableView: View {
    @Environment(AppState.self) private var appState

    let featureName: String
    let systemImage: String

    var body: some View {
        let status = appState.atlasSetupStatus

        ContentUnavailableView {
            Label("\(featureName) Unavailable", systemImage: systemImage)
        } description: {
            VStack(alignment: .center, spacing: 12) {
                Text(status.summary)
                if let guidance = status.guidance {
                    Text(guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } actions: {
            Button("Open Atlas Settings") {
                appState.showAtlasSettings()
            }
            .buttonStyle(.borderedProminent)

            if status.showsRetryAction {
                Button("Retry Atlas Startup") {
                    Task { await appState.retryAtlasSetup() }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private extension AtlasSetupStateKind {
    var symbolName: String {
        switch self {
            case .ready:
                "checkmark.circle.fill"
            case .needsConfiguration:
                "slider.horizontal.3"
            case .unavailable:
                "exclamationmark.triangle.fill"
        }
    }

    var tintColor: Color {
        switch self {
            case .ready:
                .green
            case .needsConfiguration:
                .orange
            case .unavailable:
                .red
        }
    }
}
