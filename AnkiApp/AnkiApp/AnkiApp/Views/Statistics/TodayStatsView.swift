import SwiftUI
import AppleBridgeCore
import AppleSharedUI

struct TodayStatsView: View {
    let model: StatsModel

    var body: some View {
        ScrollView {
            if let today = model.todayStats {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    StatCard(title: "Cards Studied", value: "\(today.answerCount)", icon: "rectangle.stack")
                    StatCard(
                        title: "Time Spent",
                        value: formatTime(millis: today.answerMillis),
                        icon: "clock"
                    )
                    StatCard(
                        title: "Correct",
                        value: today.answerCount > 0
                            ? "\(Int(Double(today.correctCount) / Double(today.answerCount) * 100))%"
                            : "0%",
                        icon: "checkmark.circle"
                    )
                    StatCard(title: "Learn", value: "\(today.learnCount)", icon: "book")
                    StatCard(title: "Review", value: "\(today.reviewCount)", icon: "arrow.counterclockwise")
                    StatCard(title: "Relearn", value: "\(today.relearnCount)", icon: "arrow.uturn.backward")
                    StatCard(
                        title: "Mature Correct",
                        value: today.matureCount > 0
                            ? "\(Int(Double(today.matureCorrect) / Double(today.matureCount) * 100))%"
                            : "N/A",
                        icon: "star"
                    )
                    StatCard(title: "Early Review", value: "\(today.earlyReviewCount)", icon: "calendar.badge.clock")
                }
                .padding()
            } else {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("No statistics available for today.")
                )
            }
        }
    }

    private func formatTime(millis: UInt32) -> String {
        let totalSeconds = millis / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
