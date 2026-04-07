import SwiftUI
import Charts

struct FutureDueChart: View {
    let model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let data = model.futureDueData
            if data.isEmpty {
                ContentUnavailableView("No Data", systemImage: "calendar.badge.clock", description: Text("No future due data available."))
            } else {
                Text("Future Due")
                    .font(.headline)

                Chart(data) { point in
                    BarMark(
                        x: .value("Day", point.day),
                        y: .value("Cards Due", point.count)
                    )
                    .foregroundStyle(point.day < 0 ? .red.gradient : .blue.gradient)
                }
                .chartXAxisLabel("Days from Today")
                .chartYAxisLabel("Cards Due")
                .frame(minHeight: 300)

                if let futureDue = model.graphs?.futureDue {
                    HStack(spacing: 24) {
                        if futureDue.haveBacklog {
                            Label("Has Backlog", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if futureDue.dailyLoad > 0 {
                            Text("Avg daily load: \(futureDue.dailyLoad)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
    }
}
