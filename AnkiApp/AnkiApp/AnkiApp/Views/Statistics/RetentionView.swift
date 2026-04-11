import AppleBridgeCore
import AppleSharedUI
import SwiftUI

struct RetentionView: View {
    let model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let retention = model.trueRetention {
                Text("True Retention")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text("Period").fontWeight(.semibold)
                        Text("Young").fontWeight(.semibold)
                        Text("Mature").fontWeight(.semibold)
                        Text("Total").fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Divider().gridCellColumns(4)

                    RetentionRow(label: "Today", data: retention.today)
                    RetentionRow(label: "Yesterday", data: retention.yesterday)
                    RetentionRow(label: "Week", data: retention.week)
                    RetentionRow(label: "Month", data: retention.month)
                    RetentionRow(label: "Year", data: retention.year)
                    RetentionRow(label: "All Time", data: retention.allTime)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "checkmark.circle",
                    description: Text("No retention data available.")
                )
            }
        }
        .padding()
    }
}

private struct RetentionRow: View {
    let label: String
    let data: Anki_Stats_GraphsResponse.TrueRetentionStats.TrueRetention

    private var youngTotal: UInt32 {
        data.youngPassed + data.youngFailed
    }

    private var matureTotal: UInt32 {
        data.maturePassed + data.matureFailed
    }

    private var totalPassed: UInt32 {
        data.youngPassed + data.maturePassed
    }

    private var totalAll: UInt32 {
        youngTotal + matureTotal
    }

    var body: some View {
        GridRow {
            Text(label)
                .fontWeight(.medium)
            Text(formatRate(passed: data.youngPassed, total: youngTotal))
            Text(formatRate(passed: data.maturePassed, total: matureTotal))
            Text(formatRate(passed: totalPassed, total: totalAll))
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func formatRate(passed: UInt32, total: UInt32) -> String {
        guard total > 0 else { return "--" }
        let pct = Double(passed) / Double(total) * 100
        return String(format: "%.1f%%", pct)
    }
}
