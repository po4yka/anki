import SwiftUI

struct ReviewProgress: View {
    let model: ReviewerModel

    var body: some View {
        HStack(spacing: 16) {
            CountLabel(count: model.newCount, label: "New", color: .blue)
            CountLabel(count: model.learnCount, label: "Learn", color: .orange)
            CountLabel(count: model.reviewCount, label: "Review", color: .green)
            Spacer()
        }
        .font(.subheadline)
    }
}

private struct CountLabel: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .foregroundStyle(color)
                .fontWeight(.semibold)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}
