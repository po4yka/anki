import AppleBridgeCore
import AppleSharedUI
import SwiftUI

struct ReviewProgress: View {
    let newCount: UInt32
    let learnCount: UInt32
    let reviewCount: UInt32

    var body: some View {
        HStack(spacing: 16) {
            CountLabel(count: Int(newCount), label: "New", color: .blue)
            CountLabel(count: Int(learnCount), label: "Learn", color: .orange)
            CountLabel(count: Int(reviewCount), label: "Review", color: .green)
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
