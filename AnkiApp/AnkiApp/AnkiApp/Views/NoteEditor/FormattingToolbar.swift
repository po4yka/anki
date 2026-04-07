import SwiftUI

struct FormattingToolbar: View {
    var isClozeNotetype: Bool
    var isShowingHTML: Bool
    var onBold: () -> Void
    var onItalic: () -> Void
    var onUnderline: () -> Void
    var onCloze: (() -> Void)?
    var onAttachImage: (() -> Void)?
    var onToggleHTML: (() -> Void)?
    var onLatex: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBold) {
                Image(systemName: "bold")
            }
            .help("Bold")
            .disabled(isShowingHTML)

            Button(action: onItalic) {
                Image(systemName: "italic")
            }
            .help("Italic")
            .disabled(isShowingHTML)

            Button(action: onUnderline) {
                Image(systemName: "underline")
            }
            .help("Underline")
            .disabled(isShowingHTML)

            if let onLatex {
                Divider()
                    .frame(height: 16)

                Button(action: onLatex) {
                    Image(systemName: "function")
                }
                .help("Insert LaTeX")
                .disabled(isShowingHTML)
            }

            if let onAttachImage {
                Divider()
                    .frame(height: 16)

                Button(action: onAttachImage) {
                    Image(systemName: "photo")
                }
                .help("Attach image")
                .disabled(isShowingHTML)
            }

            if isClozeNotetype, let onCloze {
                Divider()
                    .frame(height: 16)

                Button(action: onCloze) {
                    Image(systemName: "curlybraces")
                }
                .help("Cloze deletion")
                .disabled(isShowingHTML)
            }

            Spacer()

            if let onToggleHTML {
                Button(action: onToggleHTML) {
                    Image(systemName: isShowingHTML ? "richtext" : "chevron.left.forwardslash.chevron.right")
                }
                .help(isShowingHTML ? "Rich text editor" : "HTML source")
            }
        }
        .buttonStyle(.borderless)
    }
}

#Preview {
    FormattingToolbar(
        isClozeNotetype: true,
        isShowingHTML: false,
        onBold: {},
        onItalic: {},
        onUnderline: {},
        onCloze: {},
        onAttachImage: {},
        onToggleHTML: {},
        onLatex: {}
    )
    .padding()
}
