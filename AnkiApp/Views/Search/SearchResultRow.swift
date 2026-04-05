import SwiftUI

struct SearchResultRow: View {
    let row: BrowserRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.questionPreview)
                .lineLimit(2)
                .font(.body)
            Text(row.deckName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
