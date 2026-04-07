import SwiftUI

struct CoverageView: View {
    let coverage: TopicCoverage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(coverage.path)
                .font(.headline)
                .padding(.bottom, 4)

            LabeledRow(label: "Notes") {
                Text("\(coverage.noteCount)")
            }
            LabeledRow(label: "Mature") {
                Text("\(coverage.matureCount)")
            }
            LabeledRow(label: "Confidence") {
                Gauge(value: coverage.avgConfidence, in: 0 ... 1) {
                    EmptyView()
                } currentValueLabel: {
                    Text(String(format: "%.0f%%", coverage.avgConfidence * 100))
                }
                .gaugeStyle(.accessoryLinear)
                .frame(width: 120)
            }
            LabeledRow(label: "Weak Notes") {
                Text("\(coverage.weakNotes)")
                    .foregroundStyle(coverage.weakNotes > 0 ? .orange : .secondary)
            }

            Spacer()
        }
        .padding()
    }
}

private struct LabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            content()
        }
    }
}
