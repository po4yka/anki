import SwiftUI
import Charts

struct ReviewChart: View {
    let model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reviews")
                .font(.headline)

            if model.reviewData.isEmpty {
                Text("No review data available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(model.reviewData) { entry in
                    BarMark(
                        x: .value("Day", entry.date),
                        y: .value("Reviews", entry.count)
                    )
                    .foregroundStyle(by: .value("Type", entry.type))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks { AxisGridLine(); AxisValueLabel() }
                }
                .chartForegroundStyleScale([
                    "New": Color.blue,
                    "Learn": Color.orange,
                    "Review": Color.green,
                    "Relearn": Color.red
                ])
            }
        }
        .padding()
    }
}
