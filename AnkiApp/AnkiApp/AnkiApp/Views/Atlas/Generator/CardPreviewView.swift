import SwiftUI

struct CardPreviewView: View {
    let card: PreviewCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.front)
                .font(.body)
                .fontWeight(.semibold)
            Divider()
            Text(card.back)
                .font(.body)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                CardTypeBadge(cardType: card.cardType)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CardTypeBadge: View {
    let cardType: String

    var color: Color {
        switch cardType.lowercased() {
            case "basic": .blue
            case "cloze": .purple
            case "mcq": .green
            default: .secondary
        }
    }

    var body: some View {
        Text(cardType)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
