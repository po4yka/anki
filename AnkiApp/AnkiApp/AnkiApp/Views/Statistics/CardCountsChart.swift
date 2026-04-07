import Charts
import SwiftUI

private struct CardSegment {
    let label: String
    let count: UInt32
    let color: Color
}

struct CardCountsChart: View {
    let model: StatsModel

    private var segments: [CardSegment] {
        guard let counts = model.cardCountsData else { return [] }
        return [
            CardSegment(label: "New", count: counts.newCards, color: .blue),
            CardSegment(label: "Learn", count: counts.learn, color: .orange),
            CardSegment(label: "Relearn", count: counts.relearn, color: .red),
            CardSegment(label: "Young", count: counts.young, color: .green),
            CardSegment(label: "Mature", count: counts.mature, color: .teal),
            CardSegment(label: "Suspended", count: counts.suspended, color: .gray),
            CardSegment(label: "Buried", count: counts.buried, color: .brown)
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
