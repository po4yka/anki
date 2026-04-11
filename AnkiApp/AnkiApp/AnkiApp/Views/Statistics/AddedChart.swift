import Charts
import SwiftUI
import AppleBridgeCore
import AppleSharedUI

struct AddedChart: View {
    let model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let data = model.addedData
            if data.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "plus.circle",
                    description: Text("No added card data available.")
                )
            } else {
                Text("Cards Added")
                    .font(.headline)

                Chart(data) { point in
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Added", point.count)
                    )
                    .foregroundStyle(.green.gradient)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Day", point.day),
                        y: .value("Added", point.count)
                    )
                    .foregroundStyle(.green.opacity(0.1).gradient)
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxisLabel("Days Ago")
                .chartYAxisLabel("Cards Added")
                .frame(minHeight: 300)
            }
        }
        .padding()
    }
}
