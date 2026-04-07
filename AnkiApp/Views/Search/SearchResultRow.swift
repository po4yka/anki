import SwiftUI

struct SearchResultRow: View {
    let row: BrowserRowItem

    var body: some View {
        Text(row.questionPreview)
            .lineLimit(2)
            .font(.body)
    }
}
