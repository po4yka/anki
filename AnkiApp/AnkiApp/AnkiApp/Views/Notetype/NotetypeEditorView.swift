import SwiftUI

struct NotetypeEditorView: View {
    @Bindable var model: NotetypeModel
    @State private var selectedTab = 0
    @State private var newFieldName = ""
    @State private var showAddField = false

    var body: some View {
        if let notetype = model.selectedNotetype {
            VStack(alignment: .leading, spacing: 0) {
                Text(notetype.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding()

                TabView(selection: $selectedTab) {
                    fieldsTab(notetype: notetype)
                        .tabItem { Label("Fields", systemImage: "list.bullet") }
                        .tag(0)

                    templatesTab(notetype: notetype)
                        .tabItem { Label("Templates", systemImage: "doc.plaintext") }
                        .tag(1)
                }
                .padding()
            }
            .alert("Add Field", isPresented: $showAddField) {
                TextField("Field Name", text: $newFieldName)
                Button("Add") {
                    Task { await model.addField(name: newFieldName) }
                    newFieldName = ""
                }
                Button("Cancel", role: .cancel) { newFieldName = "" }
            }
        }
    }

    @ViewBuilder
    private func fieldsTab(notetype: Anki_Notetypes_Notetype) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fields")
                    .font(.headline)
                Spacer()
                Button(action: { showAddField = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }

            List {
                ForEach(Array(notetype.fields.enumerated()), id: \.offset) { index, field in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                        Text(field.name)
                        Spacer()
                        Text("ord: \(field.ord.val)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        if notetype.fields.count > 1 {
                            Button(role: .destructive) {
                                Task { await model.removeField(at: index) }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .onMove { from, to in
                    guard let source = from.first else { return }
                    Task { await model.moveField(from: source, to: to) }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func templatesTab(notetype: Anki_Notetypes_Notetype) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if notetype.templates.isEmpty {
                ContentUnavailableView("No Templates", systemImage: "doc.plaintext", description: Text("This note type has no templates."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(notetype.templates.enumerated()), id: \.offset) { index, template in
                            templateEditor(index: index, template: template)
                        }

                        cssEditor(notetype: notetype)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func templateEditor(index: Int, template: Anki_Notetypes_Notetype.Template) -> some View {
        GroupBox(template.name) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Front Template")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { template.config.qFormat },
                    set: { newValue in
                        Task { await model.updateTemplateFront(index: index, format: newValue) }
                    }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)

                Divider()

                Text("Back Template")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { template.config.aFormat },
                    set: { newValue in
                        Task { await model.updateTemplateBack(index: index, format: newValue) }
                    }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private func cssEditor(notetype: Anki_Notetypes_Notetype) -> some View {
        GroupBox("Styling (CSS)") {
            TextEditor(text: Binding(
                get: { notetype.config.css },
                set: { newValue in
                    Task { await model.updateCSS(newValue) }
                }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 120)
            .padding(4)
        }
    }
}
