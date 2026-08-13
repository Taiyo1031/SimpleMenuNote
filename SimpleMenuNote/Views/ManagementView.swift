import SwiftUI

struct ManagementView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.managementSection) {
                Text(model.localized("notes")).tag(ManagementSection.notes)
                Text(model.localized("tags")).tag(ManagementSection.tags)
                Text(model.localized("settings")).tag(ManagementSection.settings)
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
            .padding(10)

            Divider()

            switch model.managementSection {
            case .notes:
                NotesManagementView()
            case .tags:
                TagsManagementView()
            case .settings:
                SettingsManagementView()
            }
        }
        .preferredColorScheme(model.preferredColorScheme)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                UndoToastView(toast: toast)
                    .padding(.bottom, 14)
            }
        }
        .alert(
            model.localized("error"),
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button(model.localized("ok")) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct NotesManagementView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var filter: TagMode = .all

    private var filteredNotes: [NoteRecord] {
        model.filteredManagementNotes(search: search, tagFilter: filter)
    }

    var body: some View {
        if model.folderURL == nil {
            VStack(spacing: 14) {
                Text(model.localized("choose_folder_first"))
                    .foregroundStyle(.secondary)
                Button(model.localized("choose_folder")) { model.chooseInitialFolder() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Menu {
                            Button(model.localized("all_notes")) { filter = .all }
                            Divider()
                            ForEach(model.tags) { tag in
                                Button(tag.name) { filter = .tag(tag.id) }
                            }
                            Divider()
                            Button(model.localized("untagged")) { filter = .untagged }
                        } label: {
                            Label(model.modeDisplayName(filter), systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .menuStyle(.borderlessButton)
                        Spacer()
                        Button { model.createNote() } label: { Image(systemName: "plus") }
                            .buttonStyle(.plain)
                            .help(model.localized("new_note"))
                    }
                    .padding(8)

                    List(selection: $model.selectedManagementNoteID) {
                        ForEach(filteredNotes) { note in
                            NoteListRow(note: note, deletionOrder: filteredNotes.map(\.id))
                                .tag(Optional(note.id))
                        }
                    }
                    .searchable(text: $search, prompt: model.localized("search_notes"))
                    .onChange(of: model.selectedManagementNoteID) { newValue in
                        model.selectManagementNote(newValue)
                    }
                }
                .frame(minWidth: 230, idealWidth: 290, maxWidth: 360)

                ManagementNoteEditor(noteID: model.selectedManagementNoteID)
                    .frame(minWidth: 430)
            }
        }
    }
}

private struct NoteListRow: View {
    @EnvironmentObject private var model: AppModel
    let note: NoteRecord
    let deletionOrder: [UUID]
    @State private var hovering = false
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title(for: note))
                    .lineLimit(1)
                    .font(.headline)
                HStack {
                    Text(note.updatedAt, style: .date)
                    if !note.tagIDs.isEmpty {
                        Text(model.tags(for: note).prefix(2).map { "#\($0.name)" }.joined(separator: " "))
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Group {
                if hovering {
                    Button(role: .destructive) { requestDeletion() } label: {
                        Image(systemName: "trash")
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(model.localized("delete_note"))
                } else {
                    Color.clear.frame(width: 28, height: 28)
                }
            }
        }
        .padding(.vertical, 3)
        .onHover { hovering = $0 }
        .accessibilityAction(named: Text(model.localized("delete_note"))) { requestDeletion() }
        .alert(model.localized("delete_note_title"), isPresented: $confirmDelete) {
            Button(model.localized("cancel"), role: .cancel) {}
            Button(model.localized("delete"), role: .destructive) {
                model.deleteNote(note.id, orderedNoteIDs: deletionOrder, confirmed: true)
            }
        } message: {
            Text(model.localized("delete_note_message"))
        }
    }

    private func requestDeletion() {
        if model.requiresNoteDeleteConfirmation(for: note.id) {
            confirmDelete = true
        } else {
            model.deleteNote(note.id, orderedNoteIDs: deletionOrder)
        }
    }
}

private struct ManagementNoteEditor: View {
    @EnvironmentObject private var model: AppModel
    let noteID: UUID?
    @State private var showTagPicker = false
    @State private var isPreviewing = false
    @State private var finishPreviewEditingToken = 0

    private var note: NoteRecord? {
        guard let noteID else { return nil }
        return model.notes.first { $0.id == noteID }
    }

    var body: some View {
        if let note {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(model.tags(for: note).prefix(4)) { tag in
                        Text("#\(tag.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if note.tagIDs.count > 4 { Text("+\(note.tagIDs.count - 4)").font(.caption) }
                    Button { showTagPicker.toggle() } label: { Image(systemName: "tag.badge.plus") }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showTagPicker) {
                            TagPickerView(noteID: note.id).environmentObject(model)
                        }
                    Spacer()
                    Button {
                        togglePreview()
                    } label: {
                        Image(systemName: isPreviewing ? "pencil" : "eye")
                    }
                    .buttonStyle(.plain)
                    .help(model.localized(isPreviewing ? "edit" : "preview"))
                }
                .padding(10)
                Divider()

                if isPreviewing {
                    MarkdownPreviewView(
                        markdown: Binding(
                            get: { model.notes.first(where: { $0.id == note.id })?.body ?? "" },
                            set: { model.updateBody(noteID: note.id, body: $0) }
                        ),
                        noteID: note.id,
                        fontSize: model.fontSize,
                        restorationState: model.editorState(for: note.id),
                        finishEditingToken: finishPreviewEditingToken,
                        onStateChange: { model.updateEditorState($0, for: note.id) }
                    )
                } else {
                    MarkdownTextView(
                        text: Binding(
                            get: { model.notes.first(where: { $0.id == note.id })?.body ?? "" },
                            set: { model.updateBody(noteID: note.id, body: $0) }
                        ),
                        noteID: note.id,
                        fontSize: model.fontSize,
                        restorationState: model.editorState(for: note.id),
                        focusToken: model.editorFocusToken,
                        onStateChange: { model.updateEditorState($0, for: note.id) }
                    )
                }

                Divider()
                HStack {
                    Text("\(model.localized("created")): \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    Spacer()
                    Text("\(model.localized("updated")): \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
            }
        } else {
            Text(model.localized("select_note"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func togglePreview() {
        if isPreviewing {
            isPreviewing = false
            model.requestEditorFocus()
        } else {
            model.flushPendingSave()
            isPreviewing = true
        }
    }
}

private struct TagsManagementView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newTagName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField(model.localized("tag_name"), text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createTag)
                Button {
                    createTag()
                } label: {
                    Label(model.localized("new_tag"), systemImage: "plus")
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            Divider()
            List {
                ForEach(model.tags) { tag in
                    TagManagementRow(tag: tag)
                }
            }
        }
    }

    private func createTag() {
        if model.createTag(named: newTagName) != nil { newTagName = "" }
    }
}

private struct TagManagementRow: View {
    @EnvironmentObject private var model: AppModel
    let tag: TagRecord
    @State private var draftName = ""
    @State private var confirmDelete = false

    var body: some View {
        HStack {
            Image(systemName: "tag")
                .foregroundStyle(.secondary)
            TextField("", text: $draftName)
                .textFieldStyle(.plain)
                .onSubmit { model.renameTag(tag.id, to: draftName) }
            Spacer()
            Text("\(model.noteCount(for: tag.id))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button(role: .destructive) { requestDeletion() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .onAppear { draftName = tag.name }
        .onChange(of: tag.name) { draftName = $0 }
        .alert(model.localized("delete_tag_title"), isPresented: $confirmDelete) {
            Button(model.localized("cancel"), role: .cancel) {}
            Button(model.localized("delete"), role: .destructive) {
                model.deleteTag(tag.id, confirmed: true)
            }
        } message: {
            Text(String(format: model.localized("delete_tag_message"), model.noteCount(for: tag.id)))
        }
    }

    private func requestDeletion() {
        if model.requiresTagDeleteConfirmation {
            confirmDelete = true
        } else {
            model.deleteTag(tag.id)
        }
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, appearance, storage, language, markdown, data, about
    var id: String { rawValue }
}

private enum MarkdownSyntax: String, CaseIterable, Identifiable {
    case heading, bold, italic, list, link, inlineCode = "inline_code"
    var id: String { rawValue }
}

private struct SettingsManagementView: View {
    @EnvironmentObject private var model: AppModel
    @State private var category: SettingsCategory = .general

    var body: some View {
        HSplitView {
            List(SettingsCategory.allCases, selection: $category) { item in
                Label(label(for: item), systemImage: icon(for: item))
                    .tag(item)
            }
            .frame(minWidth: 170, idealWidth: 190, maxWidth: 220)

            Group {
                switch category {
                case .general: generalSettings
                case .appearance: appearanceSettings
                case .storage: storageSettings
                case .language: languageSettings
                case .markdown: markdownSettings
                case .data: dataSettings
                case .about: aboutSettings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
    }

    private var generalSettings: some View {
        Form {
            Toggle(
                model.localized("launch_at_login"),
                isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
        }
    }

    private var appearanceSettings: some View {
        Form {
            Picker(model.localized("appearance"), selection: Binding(
                get: { model.appearance },
                set: { model.setAppearance($0) }
            )) {
                Text(model.localized("system")).tag(AppearanceChoice.system)
                Text(model.localized("light")).tag(AppearanceChoice.light)
                Text(model.localized("dark")).tag(AppearanceChoice.dark)
            }
            Picker(model.localized("font_size"), selection: Binding(
                get: { model.fontSize },
                set: { model.setFontSize($0) }
            )) {
                ForEach([12.0, 13, 14, 15, 16, 18, 20], id: \.self) { size in
                    Text("\(Int(size)) pt").tag(size)
                }
            }
        }
    }

    private var storageSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.localized("note_folder")).font(.headline)
            Text(model.folderURL?.path ?? model.localized("not_selected"))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            HStack {
                Button(model.localized("change")) { model.changeStorageFolder() }
                Button(model.localized("show_in_finder")) { model.revealStorageFolder() }
                    .disabled(model.folderURL == nil)
            }
        }
    }

    private var languageSettings: some View {
        Form {
            Picker(model.localized("language"), selection: Binding(
                get: { model.language },
                set: { model.setLanguage($0) }
            )) {
                Text(model.localized("system_language")).tag(LanguageChoice.system)
                Text("日本語").tag(LanguageChoice.japanese)
                Text("English").tag(LanguageChoice.english)
            }
        }
    }

    private var markdownSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.localized("markdown_guide_title"))
                        .font(.title2.bold())
                    Text(model.localized("markdown_guide_intro"))
                        .foregroundStyle(.secondary)
                    Label(model.localized("markdown_preview_hint"), systemImage: "eye")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                ForEach(MarkdownSyntax.allCases) { syntax in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.localized("markdown_\(syntax.rawValue)"))
                            .font(.headline)
                        Text(model.localized("markdown_\(syntax.rawValue)_example"))
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    private var dataSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.localized("data_description"))
                .foregroundStyle(.secondary)
            Button {
                model.rescan()
            } label: {
                Label(model.localized("rebuild_index"), systemImage: "arrow.clockwise")
            }
            Button {
                model.revealStorageFolder()
            } label: {
                Label(model.localized("show_in_finder"), systemImage: "folder")
            }
            .disabled(model.folderURL == nil)
            Divider().padding(.vertical, 4)
            Button {
                model.resetDeletionConfirmations()
            } label: {
                Label(model.localized("reset_delete_confirmations"), systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            }
        }
    }

    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
            Text("SimpleMenuNote").font(.title2.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                .foregroundStyle(.secondary)
            Text(model.localized("privacy_summary"))
                .padding(.top, 8)
        }
    }

    private func label(for category: SettingsCategory) -> String {
        model.localized(category.rawValue)
    }

    private func icon(for category: SettingsCategory) -> String {
        switch category {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .storage: return "externaldrive"
        case .language: return "globe"
        case .markdown: return "doc.text"
        case .data: return "cylinder"
        case .about: return "info.circle"
        }
    }
}
