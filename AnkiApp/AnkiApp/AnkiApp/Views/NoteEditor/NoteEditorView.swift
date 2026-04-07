import SwiftUI
import UniformTypeIdentifiers

struct NoteEditorView: View {
    @Environment(AppState.self) private var appState
    @State private var model: NoteEditorModel?
    @Environment(\.dismiss) private var dismiss
    @State private var showFieldWarning: Bool = false
    @State private var fieldWarningMessage: String = ""
    var noteId: Int64? = nil

    var body: some View {
        Group {
            if let model {
                Form(content: {
                    Section("Note Type") {
                        NotetypePicker(model: model)
                        DeckPicker(model: model)
                    }

                    Section("Fields") {
                        ForEach(model.fields.indices, id: \.self) { index in
                            FieldEditorView(
                                label: model.fieldNames[index],
                                text: Binding(
                                    get: { model.fields[index] },
                                    set: { model.fields[index] = $0 }
                                ),
                                isPlainText: false,
                                isClozeNotetype: model.isClozeNotetype,
                                onCloze: {
                                    Task {
                                        let num = await model.nextClozeNumber()
                                        let field = model.fields[index]
                                        let range = NSRange(field.startIndex..., in: field)
                                        model.fields[index] = ClozeHelper.insertCloze(
                                            into: field, at: range, number: num
                                        )
                                    }
                                },
                                onAttachImage: { coordinator in
                                    let panel = NSOpenPanel()
                                    panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .webP]
                                    panel.allowsMultipleSelection = false
                                    panel.canChooseDirectories = false
                                    guard panel.runModal() == .OK, let url = panel.url else { return }
                                    Task {
                                        guard let data = try? Data(contentsOf: url) else { return }
                                        let filename = url.lastPathComponent
                                        if let actualName = await model.attachImage(desiredName: filename, data: data) {
                                            coordinator?.insertHTML("<img src=\"\(actualName)\">")
                                        }
                                    }
                                }
                            )
                        }
                    }

                    Section("Tags") {
                        TagEditor(model: model)
                    }
                })
                .formStyle(.grouped)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await validateAndSave() }
                        }
                        .disabled(model.isSaving)
                    }
                }
                .navigationTitle(noteId != nil ? "Edit Note" : "Add Note")
                .alert("Warning", isPresented: $showFieldWarning) {
                    Button("Save Anyway") {
                        Task {
                            await model.save()
                            if model.error == nil { dismiss() }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(fieldWarningMessage)
                }
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear {
            if model == nil {
                let m = NoteEditorModel(service: appState.service)
                model = m
                Task {
                    await m.load()
                    if let noteId {
                        await m.loadNote(id: noteId)
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .ankiErrorAlert(Binding(
            get: { model?.error },
            set: { model?.error = $0 }
        ))
    }

    private func validateAndSave() async {
        guard let model else { return }
        if let check = await model.validateFields() {
            switch check.state {
            case .duplicate:
                fieldWarningMessage = "A note with the same first field already exists. Do you want to save anyway?"
                showFieldWarning = true
                return
            case .missingCloze:
                fieldWarningMessage = "This note type requires a cloze deletion, but none were found. Do you want to save anyway?"
                showFieldWarning = true
                return
            case .empty:
                fieldWarningMessage = "The first field is empty. Do you want to save anyway?"
                showFieldWarning = true
                return
            case .normal, .notetypeNotCloze, .fieldNotCloze, .UNRECOGNIZED:
                break
            }
        }
        await model.save()
        if model.error == nil { dismiss() }
    }
}

#Preview {
    NoteEditorView()
        .environment(AppState())
}
