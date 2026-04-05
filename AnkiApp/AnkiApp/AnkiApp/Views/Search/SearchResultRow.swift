import SwiftUI

struct SearchResultRow: View {
    let row: Anki_Search_BrowserRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.cells.first?.text ?? "")
                .lineLimit(2)
                .font(.body)
            Text(row.cells.dropFirst().first?.text ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
