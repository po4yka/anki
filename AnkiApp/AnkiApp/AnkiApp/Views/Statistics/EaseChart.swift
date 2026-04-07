import Charts
import SwiftUI

struct EaseChart: View {
    let model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let data = model.easeData
            if data.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "gauge.medium",
                    description: Text("No ease data available.")
                )
            } else {
                HStack {
                    Text("Ease Factor")
                        .font(.headline)
                    Spacer()
                    if model.averageEase > 0 {
                        Text("Average: \(Int(model.averageEase / 10))%")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Chart(data) { point in
                    BarMark(
                        x: .value("Ease (%)", point.ease / 10),
                        y: .value("Cards", point.count)
                    )
                    .foregroundStyle(.purple.gradient)
                }
                .chartXAxisLabel("Ease Factor (%)")
                .chartYAxisLabel("Number of Cards")
                .frame(minHeight: 300)
            }
        }
        .padding()
    }
}
