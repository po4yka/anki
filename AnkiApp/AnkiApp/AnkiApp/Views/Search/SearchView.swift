import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var model: SearchModel?
    @State private var editingNoteId: Int64?
    @State private var showingSetDueDate = false
    @State private var showingAddTags = false
    @State private var showingRemoveTags = false
    @State private var showingFindReplace = false
    @State private var dueDateInput = ""
    @State private var tagInput = ""
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var showingColumnPicker = false
    @State private var showingSaveSearch = false
    @State private var saveSearchName = ""
    @State private var renamingSearchId: UUID?
    @State private var renameSearchText = ""

    var body: some View {
        Group {
            if let model {
                if !appState.isCollectionOpen {
                    ContentUnavailableView {
                        Label("No Collection Open", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Open a collection from Preferences to search notes.")
                    } actions: {
                        Button("Open Preferences") {
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    HSplitView {
                        // Saved searches sidebar
                        SavedSearchesSidebar(
                            model: model,
                            showingSaveSearch: $showingSaveSearch,
                            saveSearchName: $saveSearchName,
                            renamingSearchId: $renamingSearchId,
                            renameSearchText: $renameSearchText
                        )
                        .frame(minWidth: 160, maxWidth: 220)

                        VStack(spacing: 0) {
                            SearchBar(model: model)
                                .padding()

                            Divider()

                            HStack {
                                Picker("Mode", selection: Binding(
                                    get: { model.searchMode },
                                    set: { mode in
                                        model.searchMode = mode
                                        Task { await model.search() }
                                    }
                                )) {
                                    ForEach(BrowserSearchMode.allCases, id: \.self) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 200)

                                Spacer()

                                Text("\(model.cardIds.count) results")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)

                                if !model.selectedCardIds.isEmpty {
                                    Text("\(model.selectedCardIds.count) selected")
                                        .foregroundStyle(.blue)
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)

                            Divider()

                            if model.cardIds.isEmpty, !model.isSearching {
                                ContentUnavailableView(
                                    "Search Notes",
                                    systemImage: "magnifyingglass",
                                    description: Text("Enter a query above and press Return to search.")
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                Table(model.results, selection: Binding(
                                    get: { model.selectedCardIds },
                                    set: { model.selectedCardIds = $0 }
                                )) {
                                    TableColumn("Question") { row in
                                        Text(row.questionPreview)
                                            .lineLimit(1)
                                    }
                                    .width(min: 200)

                                    TableColumn("Deck") { row in
                                        Text(row.deckName)
                                            .foregroundStyle(.secondary)
                                    }
                                    .width(min: 100)

                                    TableColumn("Due") { row in
                                        Text(row.due)
                                            .foregroundStyle(.secondary)
                                    }
                                    .width(min: 80)
                                }
                                .contextMenu(forSelectionType: Int64.self) { ids in
                                    if !ids.isEmpty {
                                        Button("Edit Note") {
                                            if let cardId = ids.first {
                                                Task {
                                                    let card = try? await appState.service.getCard(id: cardId)
                                                    if let noteId = card?.noteID {
                                                        editingNoteId = noteId
                                                    }
                                                }
                                            }
                                        }
                                        Divider()
                                        Button("Set Due Date...") {
                                            dueDateInput = ""
                                            showingSetDueDate = true
                                        }
                                        Button("Add Tags...") {
                                            tagInput = ""
                                            showingAddTags = true
                                        }
                                        Button("Remove Tags...") {
                                            tagInput = ""
                                            showingRemoveTags = true
                                        }
                                        Divider()
                                        Button("Suspend") {
                                            Task { await model.suspendSelected() }
                                        }
                                        Button("Bury") {
                                            Task { await model.burySelected() }
                                        }
                                        Button("Forget") {
                                            Task { await model.forgetSelected() }
                                        }
                                        Divider()
                                        Button("Find and Replace...") {
                                            findText = ""
                                            replaceText = ""
                                            showingFindReplace = true
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            Task { await model.deleteSelected() }
                                        }
                                    }
                                } primaryAction: { ids in
                                    if let cardId = ids.first {
                                        Task {
                                            let card = try? await appState.service.getCard(id: cardId)
                                            if let noteId = card?.noteID {
                                                editingNoteId = noteId
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } // end HSplitView
                    .navigationTitle("Browse")
                    .toolbar {
                        ToolbarItemGroup {
                            Button {
                                showingColumnPicker = true
                            } label: {
                                Label("Columns", systemImage: "gearshape")
                            }
                            .popover(isPresented: $showingColumnPicker) {
                                ColumnPickerView(model: model)
                            }

                            Button {
                                dueDateInput = ""
                                showingSetDueDate = true
                            } label: {
                                Label("Set Due Date", systemImage: "calendar")
                            }
                            .disabled(model.selectedCardIds.isEmpty)

                            Button {
                                tagInput = ""
                                showingAddTags = true
                            } label: {
                                Label("Add Tags", systemImage: "tag")
                            }
                            .disabled(model.selectedCardIds.isEmpty)

                            Button(role: .destructive) {
                                Task { await model.deleteSelected() }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .disabled(model.selectedCardIds.isEmpty)
                        }
                    }
                }
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear {
            if model == nil {
                model = SearchModel(service: appState.service)
                Task {
                    await model?.loadColumns()
                    model?.loadSavedSearches()
                }
            }
        }
        .ankiErrorAlert(Binding(
            get: { model?.error },
            set: { model?.error = $0 }
        ))
        .sheet(item: Binding(
            get: { editingNoteId.map { EditNoteItem(noteId: $0) } },
            set: { editingNoteId = $0?.noteId }
        )) { item in
            NavigationStack {
                NoteEditorView(noteId: item.noteId)
            }
        }
        .sheet(isPresented: $showingSetDueDate) {
            SetDueDateSheet(input: $dueDateInput) {
                Task { await model?.setDueDateForSelected(days: dueDateInput) }
            }
        }
        .sheet(isPresented: $showingAddTags) {
            TagSheet(title: "Add Tags", input: $tagInput) {
                Task { await model?.addTagsToSelected(tags: tagInput) }
            }
        }
        .sheet(isPresented: $showingRemoveTags) {
            TagSheet(title: "Remove Tags", input: $tagInput) {
                Task { await model?.removeTagsFromSelected(tags: tagInput) }
            }
        }
        .sheet(isPresented: $showingFindReplace) {
            FindReplaceSheet(find: $findText, replace: $replaceText) {
                Task {
                    await model?.findAndReplace(
                        search: findText, replacement: replaceText,
                        regex: false, matchCase: false, fieldName: ""
                    )
                }
            }
        }
    }
}

private struct EditNoteItem: Identifiable {
    let noteId: Int64
    var id: Int64 {
        noteId
    }
}

private struct SearchBar: View {
    let model: SearchModel

    var body: some View {
        @Bindable var model = model
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search notes...", text: $model.query)
                .textFieldStyle(.plain)
                .keyboardShortcut("f", modifiers: .command)
                .onSubmit {
                    Task { await model.search() }
                }
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    Task { await model.search() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Batch Operation Sheets

private struct SetDueDateSheet: View {
    @Binding var input: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Set Due Date")
                .font(.headline)
            Text("Enter number of days from today (e.g. \"0\" for today, \"1\" for tomorrow).")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Days", text: $input)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Set") {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(input.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

private struct TagSheet: View {
    let title: String
    @Binding var input: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
            TextField("Tags (space-separated)", text: $input)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(input.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

private struct FindReplaceSheet: View {
    @Binding var find: String
    @Binding var replace: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Find and Replace")
                .font(.headline)
            TextField("Find", text: $find)
                .textFieldStyle(.roundedBorder)
            TextField("Replace with", text: $replace)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Replace All") {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(find.isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

// MARK: - Column Picker

private struct ColumnPickerView: View {
    let model: SearchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Visible Columns")
                .font(.headline)
                .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.allColumns, id: \.key) { column in
                        let isVisible = model.visibleColumnKeys.contains(column.key)
                        Button {
                            Task { await model.toggleColumn(key: column.key) }
                        } label: {
                            HStack {
                                Image(systemName: isVisible ? "checkmark.square" : "square")
                                    .foregroundStyle(isVisible ? .blue : .secondary)
                                Text(column.cardsModeLabel.isEmpty ? column.key : column.cardsModeLabel)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 220, maxHeight: 350)
    }
}

// MARK: - Saved Searches Sidebar

private struct SavedSearchesSidebar: View {
    let model: SearchModel
    @Binding var showingSaveSearch: Bool
    @Binding var saveSearchName: String
    @Binding var renamingSearchId: UUID?
    @Binding var renameSearchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Saved Searches")
                    .font(.headline)
                Spacer()
                Button {
                    saveSearchName = ""
                    showingSaveSearch = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .disabled(model.query.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if model.savedSearches.isEmpty {
                Text("No saved searches")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)
            } else {
                List {
                    ForEach(model.savedSearches) { saved in
                        Button {
                            Task { await model.applySavedSearch(saved) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(saved.name)
                                    .lineLimit(1)
                                Text(saved.query)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Rename...") {
                                renameSearchText = saved.name
                                renamingSearchId = saved.id
                            }
                            Button("Delete", role: .destructive) {
                                model.deleteSavedSearch(id: saved.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }

            Spacer()
        }
        .alert("Save Search", isPresented: $showingSaveSearch) {
            TextField("Name", text: $saveSearchName)
            Button("Save") {
                let name = saveSearchName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    model.saveCurrentSearch(name: name)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for this search.")
        }
        .alert("Rename Search", isPresented: Binding(
            get: { renamingSearchId != nil },
            set: { if !$0 { renamingSearchId = nil } }
        )) {
            TextField("Name", text: $renameSearchText)
            Button("Rename") {
                let name = renameSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, let id = renamingSearchId {
                    model.renameSavedSearch(id: id, newName: name)
                }
                renamingSearchId = nil
            }
            Button("Cancel", role: .cancel) {
                renamingSearchId = nil
            }
        } message: {
            Text("Enter a new name.")
        }
    }
}

#Preview {
    SearchView()
        .environment(AppState())
}
