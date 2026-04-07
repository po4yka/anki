import Charts
import SwiftUI

struct CardCountsChart: View {
    let model: StatsModel

    private var segments: [(label: String, count: UInt32, color: Color)] {
        guard let counts = model.cardCountsData else { return [] }
        return [
            ("New", counts.newCards, .blue),
            ("Learn", counts.learn, .orange),
            ("Relearn", counts.relearn, .red),
            ("Young", counts.young, .green),
            ("Mature", counts.mature, .teal),
            ("Suspended", counts.suspended, .gray),
            ("Buried", counts.buried, .brown),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.cardCountsData != nil {
                Text("Total: \(model.totalCards) cards")
                    .font(.headline)

                Chart(segments, id: \.label) { segment in
                    BarMark(
                        x: .value("Count", segment.count),
                        y: .value("Type", segment.label)
                    )
                    .foregroundStyle(segment.color)
                }
                .chartXAxisLabel("Number of Cards")
                .frame(minHeight: 300)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(segments, id: \.label) { segment in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(segment.color)
                                .frame(width: 10, height: 10)
                            Text("\(segment.label): \(segment.count)")
                                .font(.caption)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "rectangle.stack",
                    description: Text("No card count data available.")
                )
            }
        }
        .padding()
    }
}
