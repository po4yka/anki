import AppleBridgeCore
import AppleSharedUI
import Charts
import SwiftUI

struct ReviewChart: View {
    let model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let data = model.reviewCountData
            if data.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.bar",
                    description: Text("No review data available.")
                )
            } else {
                Text("Review Counts")
                    .font(.headline)

                Chart(data) { point in
                    BarMark(
                        x: .value("Day", point.day),
                        y: .value("Learn", point.learn)
                    )
                    .foregroundStyle(by: .value("Type", "Learn"))

                    BarMark(
                        x: .value("Day", point.day),
                        y: .value("Relearn", point.relearn)
                    )
                    .foregroundStyle(by: .value("Type", "Relearn"))

                    BarMark(
                        x: .value("Day", point.day),
                        y: .value("Young", point.young)
                    )
                    .foregroundStyle(by: .value("Type", "Young"))

                    BarMark(
                        x: .value("Day", point.day),
                        y: .value("Mature", point.mature)
                    )
                    .foregroundStyle(by: .value("Type", "Mature"))
                }
                .chartForegroundStyleScale([
                    "Learn": .orange,
                    "Relearn": .red,
                    "Young": .green,
                    "Mature": .teal
                ])
                .chartXAxisLabel("Days Ago")
                .chartYAxisLabel("Reviews")
                .frame(minHeight: 300)
            }
        }
        .padding()
    }
}
