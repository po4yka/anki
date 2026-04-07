import SwiftUI

struct NotetypeListView: View {
    @Environment(AppState.self) private var appState
    @State private var model: NotetypeModel?
    @State private var showNewNotetype = false
    @State private var newNotetypeName = ""
    @State private var cloneTarget: Anki_Notetypes_NotetypeNameIdUseCount? = nil
    @State private var cloneName = ""

    var body: some View {
        Group {
            if let model {
                contentView(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            let m = NotetypeModel(service: appState.service)
            model = m
            await m.load()
        }
    }

    @ViewBuilder
    private func contentView(model: NotetypeModel) -> some View {
        HSplitView {
            listPane(model: model)
                .frame(minWidth: 220, idealWidth: 280)
            editorPane(model: model)
                .frame(minWidth: 400)
        }
        .alert("New Note Type", isPresented: $showNewNotetype) {
            TextField("Name", text: $newNotetypeName)
            Button("Add") {
                Task { await model.addNotetype(name: newNotetypeName) }
                newNotetypeName = ""
            }
            Button("Cancel", role: .cancel) { newNotetypeName = "" }
        }
        .alert("Clone Note Type", isPresented: Binding(
            get: { cloneTarget != nil },
            set: { if !$0 { cloneTarget = nil; cloneName = "" } }
        )) {
            TextField("New Name", text: $cloneName)
            Button("Clone") {
                if let target = cloneTarget {
                    Task { await model.cloneNotetype(id: target.id, newName: cloneName) }
                }
                cloneTarget = nil
                cloneName = ""
            }
            Button("Cancel", role: .cancel) { cloneTarget = nil; cloneName = "" }
        }
    }

    @ViewBuilder
    private func listPane(model: NotetypeModel) -> some View {
        VStack(spacing: 0) {
            List(model.notetypes, id: \.id, selection: Binding(
                get: { model.selectedNotetype?.id },
                set: { id in
                    if let id { Task { await model.selectNotetype(id: id) } }
                }
            )) { entry in
                HStack {
                    Text(entry.name)
                    Spacer()
                    Text("\(entry.useCount)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .contextMenu {
                    Button("Clone") {
                        cloneName = "\(entry.name) copy"
                        cloneTarget = entry
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        Task { await model.deleteNotetype(id: entry.id) }
                    }
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Button(action: { showNewNotetype = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .padding(8)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func editorPane(model: NotetypeModel) -> some View {
        if model.selectedNotetype != nil {
            NotetypeEditorView(model: model)
        } else {
            ContentUnavailableView("Select a Note Type", systemImage: "doc.text", description: Text("Choose a note type from the list to edit its fields and templates."))
        }
    }
}

#Preview {
    NotetypeListView()
        .environment(AppState())
}
