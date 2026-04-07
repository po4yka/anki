import Charts
import SwiftUI

struct IntervalChart: View {
    let model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let data = model.intervalData
            if data.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "clock",
                    description: Text("No interval data available.")
                )
            } else {
                Text("Card Intervals")
                    .font(.headline)

                Chart(data) { point in
                    BarMark(
                        x: .value("Interval (days)", point.intervalDays),
                        y: .value("Cards", point.count)
                    )
                    .foregroundStyle(.teal.gradient)
                }
                .chartXAxisLabel("Interval (days)")
                .chartYAxisLabel("Number of Cards")
                .frame(minHeight: 300)
            }
        }
        .padding()
    }
}
