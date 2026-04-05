import SwiftUI

struct NoteEditorView: View {
    @Environment(AppState.self) private var appState
    @State private var model: NoteEditorModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model {
                Form {
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
                                )
                            )
                        }
                    }

                    Section("Tags") {
                        TagEditor(model: model)
                    }
                }
                .formStyle(.grouped)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                await model.save()
                                if model.error == nil { dismiss() }
                            }
                        }
                        .disabled(model.isSaving)
                    }
                }
                .navigationTitle("Add Note")
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear {
            if model == nil {
                model = NoteEditorModel(service: appState.service)
                Task { await model?.load() }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .ankiErrorAlert($model?.error)
    }
}

#Preview {
    NoteEditorView()
        .environment(AppState())
}
