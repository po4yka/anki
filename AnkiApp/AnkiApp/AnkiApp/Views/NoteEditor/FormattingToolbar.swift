import SwiftUI

struct FormattingToolbar: View {
    var isClozeNotetype: Bool
    var isShowingHTML: Bool
    var onBold: () -> Void
    var onItalic: () -> Void
    var onUnderline: () -> Void
    var onStrikethrough: (() -> Void)?
    var onOrderedList: (() -> Void)?
    var onUnorderedList: (() -> Void)?
    var onAlignLeft: (() -> Void)?
    var onAlignCenter: (() -> Void)?
    var onAlignRight: (() -> Void)?
    var onInsertLink: (() -> Void)?
    var onCloze: (() -> Void)?
    var onAttachImage: (() -> Void)?
    var onToggleHTML: (() -> Void)?
    var onLatex: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            // Text style group
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

            if let onStrikethrough {
                Button(action: onStrikethrough) {
                    Image(systemName: "strikethrough")
                }
                .help("Strikethrough")
                .disabled(isShowingHTML)
            }

            // List group
            if onOrderedList != nil || onUnorderedList != nil {
                Divider()
                    .frame(height: 16)

                if let onOrderedList {
                    Button(action: onOrderedList) {
                        Image(systemName: "list.number")
                    }
                    .help("Numbered List")
                    .disabled(isShowingHTML)
                }

                if let onUnorderedList {
                    Button(action: onUnorderedList) {
                        Image(systemName: "list.bullet")
                    }
                    .help("Bulleted List")
                    .disabled(isShowingHTML)
                }
            }

            // Alignment group
            if onAlignLeft != nil || onAlignCenter != nil || onAlignRight != nil {
                Divider()
                    .frame(height: 16)

                if let onAlignLeft {
                    Button(action: onAlignLeft) {
                        Image(systemName: "text.alignleft")
                    }
                    .help("Align Left")
                    .disabled(isShowingHTML)
                }

                if let onAlignCenter {
                    Button(action: onAlignCenter) {
                        Image(systemName: "text.aligncenter")
                    }
                    .help("Align Center")
                    .disabled(isShowingHTML)
                }

                if let onAlignRight {
                    Button(action: onAlignRight) {
                        Image(systemName: "text.alignright")
                    }
                    .help("Align Right")
                    .disabled(isShowingHTML)
                }
            }

            // Insert group: link, LaTeX, image, cloze
            if onInsertLink != nil || onLatex != nil || onAttachImage != nil || (isClozeNotetype && onCloze != nil) {
                Divider()
                    .frame(height: 16)

                if let onInsertLink {
                    Button(action: onInsertLink) {
                        Image(systemName: "link")
                    }
                    .help("Insert Link")
                    .disabled(isShowingHTML)
                }

                if let onLatex {
                    Button(action: onLatex) {
                        Image(systemName: "function")
                    }
                    .help("Insert LaTeX")
                    .disabled(isShowingHTML)
                }

                if let onAttachImage {
                    Button(action: onAttachImage) {
                        Image(systemName: "photo")
                    }
                    .help("Attach image")
                    .disabled(isShowingHTML)
                }

                if isClozeNotetype, let onCloze {
                    Button(action: onCloze) {
                        Image(systemName: "curlybraces")
                    }
                    .help("Cloze deletion")
                    .disabled(isShowingHTML)
                }
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
        onStrikethrough: {},
        onOrderedList: {},
        onUnorderedList: {},
        onAlignLeft: {},
        onAlignCenter: {},
        onAlignRight: {},
        onInsertLink: {},
        onCloze: {},
        onAttachImage: {},
        onToggleHTML: {},
        onLatex: {}
    )
    .padding()
}
