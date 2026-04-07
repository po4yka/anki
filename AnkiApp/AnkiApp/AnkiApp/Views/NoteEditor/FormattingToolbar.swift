import SwiftUI

struct FormattingToolbar: View {
    var isClozeNotetype: Bool
    var onBold: () -> Void
    var onItalic: () -> Void
    var onUnderline: () -> Void
    var onCloze: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBold) {
                Image(systemName: "bold")
            }
            .help("Bold")

            Button(action: onItalic) {
                Image(systemName: "italic")
            }
            .help("Italic")

            Button(action: onUnderline) {
                Image(systemName: "underline")
            }
            .help("Underline")

            if isClozeNotetype, let onCloze {
                Divider()
                    .frame(height: 16)

                Button(action: onCloze) {
                    Image(systemName: "curlybraces")
                }
                .help("Cloze deletion")
            }
        }
        .buttonStyle(.borderless)
    }
}

#Preview {
    FormattingToolbar(
        isClozeNotetype: true,
        onBold: {},
        onItalic: {},
        onUnderline: {},
        onCloze: {}
    )
    .padding()
}
