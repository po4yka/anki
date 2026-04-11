import AppleBridgeCore
import AppleSharedUI
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
    @State private var isShowingLinkSheet: Bool = false
    @State private var linkURL: String = ""

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
                        onStrikethrough: { richEditorCoordinator?.executeCommand("strikeThrough") },
                        onOrderedList: { richEditorCoordinator?.executeCommand("insertOrderedList") },
                        onUnorderedList: { richEditorCoordinator?.executeCommand("insertUnorderedList") },
                        onAlignLeft: { richEditorCoordinator?.executeCommand("justifyLeft") },
                        onAlignCenter: { richEditorCoordinator?.executeCommand("justifyCenter") },
                        onAlignRight: { richEditorCoordinator?.executeCommand("justifyRight") },
                        onInsertLink: {
                            linkURL = ""
                            isShowingLinkSheet = true
                        },
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
                        RichFieldEditor(
                            html: $text,
                            onContentChange: nil,
                            onCoordinatorReady: { coordinator in
                                richEditorCoordinator = coordinator
                            }
                        )
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
        .sheet(isPresented: $isShowingLinkSheet) {
            InsertLinkSheet(url: $linkURL) { confirmedURL in
                richEditorCoordinator?.executeCommand("createLink", value: confirmedURL)
            }
        }
    }
}

private struct InsertLinkSheet: View {
    @Binding var url: String
    var onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Insert Link")
                .font(.headline)

            TextField("https://example.com", text: $url)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 300)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Insert") {
                    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onConfirm(trimmed)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
    }
}

#Preview {
    FieldEditorView(label: "Front", text: .constant("Hello world"))
        .padding()
}
