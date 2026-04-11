import SwiftUI
import UniformTypeIdentifiers
import AppleBridgeCore
import AppleSharedUI

struct NoteEditorView: View {
    @Environment(AppState.self) private var appState
    @State private var model: NoteEditorModel?
    @Environment(\.dismiss) private var dismiss
    @State private var showFieldWarning: Bool = false
    @State private var fieldWarningMessage: String = ""
    @State private var currentNoteId: Int64?
    @State private var showingImagePicker = false
    @State private var pendingImageCoordinator: RichFieldEditor.Coordinator?

    init(noteId: Int64? = nil) {
        _currentNoteId = State(initialValue: noteId)
    }

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
                            fieldEditorRow(index: index, model: model)
                        }
                    }

                    Section("Tags") {
                        TagEditor(model: model)
                    }

                    if let currentNoteId, let atlas = appState.atlasService {
                        Section("See Also") {
                            SeeAlsoNotesView(atlas: atlas, noteId: currentNoteId) { linkedNoteId in
                                self.currentNoteId = linkedNoteId
                                Task { await model.loadNote(id: linkedNoteId) }
                            }
                        }
                    }

                    if !model.isClozeNotetype, let reqs = model.fieldRequirements {
                        Section("Cards") {
                            HStack {
                                Text("Cards to generate:")
                                Spacer()
                                let cardCountColor: Color = reqs.cardCount > 0 ? .primary : .red
                                Text("\(reqs.cardCount)")
                                    .foregroundStyle(cardCountColor)
                            }
                            if !reqs.emptyRequiredFields.isEmpty {
                                Label(
                                    "Empty required: \(reqs.emptyRequiredFields.joined(separator: ", "))",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .foregroundStyle(.orange)
                                .font(.caption)
                            }
                        }
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
                .navigationTitle(currentNoteId != nil ? "Edit Note" : "Add Note")
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
                let noteEditorModel = NoteEditorModel(service: appState.service)
                model = noteEditorModel
                Task {
                    await noteEditorModel.load()
                    if let currentNoteId {
                        await noteEditorModel.loadNote(id: currentNoteId)
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .ankiErrorAlert(Binding(
            get: { model?.error },
            set: { model?.error = $0 }
        ))
        .fileImporter(
            isPresented: $showingImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard let model,
                  case let .success(urls) = result,
                  let url = urls.first else {
                return
            }
            attachImage(from: url, coordinator: pendingImageCoordinator, model: model)
        }
    }

    @ViewBuilder
    private func fieldEditorRow(index: Int, model: NoteEditorModel) -> some View {
        let label: String = model.fieldNames[index] + (model.isFieldRequired(index) ? " *" : "")
        let binding = Binding<String>(
            get: { model.fields[index] },
            set: { model.fields[index] = $0 }
        )
        FieldEditorView(
            label: label,
            text: binding,
            isPlainText: false,
            isClozeNotetype: model.isClozeNotetype,
            onCloze: { insertCloze(at: index, model: model) },
            onAttachImage: { coordinator in attachImage(coordinator: coordinator, model: model) }
        )
    }

    private func insertCloze(at index: Int, model: NoteEditorModel) {
        Task {
            let num = await model.nextClozeNumber()
            let field = model.fields[index]
            let range = NSRange(field.startIndex..., in: field)
            model.fields[index] = ClozeHelper.insertCloze(into: field, at: range, number: num)
        }
    }

    private func attachImage(coordinator: RichFieldEditor.Coordinator?, model: NoteEditorModel) {
        pendingImageCoordinator = coordinator
        _ = model
        showingImagePicker = true
    }

    private func attachImage(
        from url: URL,
        coordinator: RichFieldEditor.Coordinator?,
        model: NoteEditorModel
    ) {
        Task {
            guard let data = try? Data(contentsOf: url) else { return }
            let filename = url.lastPathComponent
            if let actualName = await model.attachImage(desiredName: filename, data: data) {
                let html = "<img src=\"\(actualName)\">"
                coordinator?.insertHTML(html)
            }
            pendingImageCoordinator = nil
        }
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
        if let reqs = model.fieldRequirements, reqs.cardCount == 0,
           !reqs.emptyRequiredFields.isEmpty {
            let names = reqs.emptyRequiredFields.joined(separator: ", ")
            fieldWarningMessage = "Required fields (\(names)) are empty. No cards will be generated. Save anyway?"
            showFieldWarning = true
            return
        }
        await model.save()
        if model.error == nil { dismiss() }
    }
}

#Preview {
    NoteEditorView()
        .environment(AppState())
}
