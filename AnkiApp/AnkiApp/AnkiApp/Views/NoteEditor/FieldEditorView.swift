import SwiftUI
import UniformTypeIdentifiers

struct FieldEditorView: View {
    let label: String
    @Binding var text: String
    var isPlainText: Bool = true
    var isClozeNotetype: Bool = false
    var onCloze: (() -> Void)?
    var onAttachImage: ((_ coordinator: RichFieldEditor.Coordinator?) -> Void)?

    @State private var richEditorCoordinator: RichFieldEditor.Coordinator?
    @State private var isShowingHTML: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            if isPlainText {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            } else {
                VStack(spacing: 0) {
                    FormattingToolbar(
                        isClozeNotetype: isClozeNotetype,
                        isShowingHTML: isShowingHTML,
                        onBold: { richEditorCoordinator?.executeCommand("bold") },
                        onItalic: { richEditorCoordinator?.executeCommand("italic") },
                        onUnderline: { richEditorCoordinator?.executeCommand("underline") },
                        onCloze: onCloze,
                        onAttachImage: onAttachImage != nil ? { onAttachImage?(richEditorCoordinator) } : nil,
                        onToggleHTML: { isShowingHTML.toggle() },
                        onLatex: { richEditorCoordinator?.wrapSelectionWithLatex() }
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    Divider()

                    if isShowingHTML {
                        TextEditor(text: $text)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 60)
                    } else {
                        RichFieldEditor(html: $text) { _ in }
                            .frame(minHeight: 60)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FieldEditorView(label: "Front", text: .constant("Hello world"))
        .padding()
}
