import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var model: SearchModel?
    @State private var showingSetDueDate = false
    @State private var showingAddTags = false
    @State private var showingRemoveTags = false
    @State private var showingFindReplace = false
    @State private var dueDateInput = ""
    @State private var tagInput = ""
    @State private var findText = ""
    @State private var replaceText = ""

    var body: some View {
        Group {
            if let model {
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
                    } primaryAction: { _ in
                        // Double-click: could open editor in future
                    }
                }
                .navigationTitle("Browse")
                .toolbar {
                    ToolbarItemGroup {
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
                .sheet(isPresented: $showingSetDueDate) {
                    SetDueDateSheet(input: $dueDateInput) {
                        Task { await model.setDueDateForSelected(days: dueDateInput) }
                    }
                }
                .sheet(isPresented: $showingAddTags) {
                    TagSheet(title: "Add Tags", input: $tagInput) {
                        Task { await model.addTagsToSelected(tags: tagInput) }
                    }
                }
                .sheet(isPresented: $showingRemoveTags) {
                    TagSheet(title: "Remove Tags", input: $tagInput) {
                        Task { await model.removeTagsFromSelected(tags: tagInput) }
                    }
                }
                .sheet(isPresented: $showingFindReplace) {
                    FindReplaceSheet(find: $findText, replace: $replaceText) {
                        Task {
                            await model.findAndReplace(
                                search: findText, replacement: replaceText,
                                regex: false, matchCase: false, fieldName: ""
                            )
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
            }
        }
        .ankiErrorAlert($model?.error)
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

#Preview {
    SearchView()
        .environment(AppState())
}
