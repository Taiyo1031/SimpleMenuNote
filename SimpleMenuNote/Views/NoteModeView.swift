import SwiftUI

struct NoteModeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTagPickerPresented = false
    @State private var resizeStartHeight: Double?
    @State private var showInitialResizeHint = false

    var body: some View {
        Group {
            if model.folderURL == nil {
                welcomeView
            } else {
                noteInterface
            }
        }
        .frame(width: 380, height: model.popoverHeight)
        .preferredColorScheme(model.preferredColorScheme)
        .onExitCommand { model.closePopover() }
        .task {
            guard !model.resizeHintShown else { return }
            withAnimation { showInitialResizeHint = true }
            try? await Task.sleep(for: .seconds(4))
            withAnimation { showInitialResizeHint = false }
            model.markResizeHintShown()
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

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tint)
            Text(model.localized("welcome_title"))
                .font(.title3.weight(.semibold))
            Text(model.localized("welcome_message"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
            Button(model.localized("choose_folder")) {
                model.chooseInitialFolder()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private var noteInterface: some View {
        VStack(spacing: 0) {
            toolbar
                .frame(height: 34)
                .padding(.horizontal, 8)

            Divider()

            ZStack(alignment: .bottom) {
                if let note = model.currentNote {
                    MarkdownTextView(
                        text: Binding(
                            get: { model.currentNote?.body ?? "" },
                            set: { model.updateCurrentBody($0) }
                        ),
                        noteID: note.id,
                        fontSize: model.fontSize,
                        restorationState: model.editorState(for: note.id),
                        focusToken: model.editorFocusToken,
                        onStateChange: { model.updateEditorState($0, for: note.id) }
                    )
                } else {
                    emptyModeView
                }

                if let toast = model.toast {
                    toastView(toast)
                        .padding(8)
                }
            }

            Divider()
            navigationBar
                .frame(height: 31)

            resizeGrip
                .frame(height: 10)
        }
        .overlay(alignment: .bottom) {
            if showInitialResizeHint {
                Text(model.localized("resize_hint"))
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 3, y: 1)
                    .padding(.bottom, 42)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 7) {
            Menu {
                Button(model.localized("all_notes")) { model.selectMode(.all) }
                Divider()
                ForEach(model.tags) { tag in
                    Button(tag.name) { model.selectMode(.tag(tag.id)) }
                }
                Divider()
                Button(model.localized("untagged")) { model.selectMode(.untagged) }
                Button(model.localized("manage_tags")) { model.showManagement(.tags) }
            } label: {
                HStack(spacing: 3) {
                    Text(model.modeDisplayName(model.selectedMode))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(model.localized("switch_tag_mode"))

            if let note = model.currentNote {
                let noteTags = model.tags(for: note)
                ForEach(Array(noteTags.prefix(3))) { tag in
                    Menu {
                        Button(model.localized("remove_tag"), role: .destructive) {
                            model.removeTag(tag.id, from: note.id)
                        }
                    } label: {
                        Text("#\(tag.name)")
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                if noteTags.count > 3 {
                    Text("+\(noteTags.count - 3)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 2)

            Button {
                isTagPickerPresented.toggle()
            } label: {
                Image(systemName: "tag.badge.plus")
            }
            .buttonStyle(.plain)
            .disabled(model.currentNote == nil)
            .popover(isPresented: $isTagPickerPresented, arrowEdge: .bottom) {
                TagPickerView(noteID: model.currentNoteID)
                    .environmentObject(model)
            }
            .help(model.localized("edit_note_tags"))

            Button {
                model.createNote()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help(model.localized("new_note"))

            Button {
                model.showManagement(.notes)
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(.plain)
            .help(model.localized("open_management"))
        }
        .imageScale(.small)
    }

    private var emptyModeView: some View {
        VStack(spacing: 10) {
            Text(model.localized("tag_has_no_notes"))
                .foregroundStyle(.secondary)
            Button {
                model.createNote()
            } label: {
                Label(model.localized("new_note"), systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var navigationBar: some View {
        HStack {
            Button { model.goPrevious() } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!model.canGoPrevious)
            .help(model.localized("previous_note"))

            Spacer()
            Text(positionText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()

            Button { model.goNext() } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 34, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!model.canGoNext)
            .help(model.localized("next_note"))
        }
        .padding(.horizontal, 10)
    }

    private var positionText: String {
        guard let position = model.currentPosition else { return "0 / 0" }
        return "\(position) / \(model.modeNotes.count)"
    }

    private var resizeGrip: some View {
        ZStack {
            Capsule()
                .fill(.tertiary)
                .frame(width: 38, height: 3)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    showInitialResizeHint = false
                    if resizeStartHeight == nil { resizeStartHeight = model.popoverHeight }
                    model.setPopoverHeight((resizeStartHeight ?? model.popoverHeight) + value.translation.height)
                }
                .onEnded { _ in resizeStartHeight = nil }
        )
        .help(model.resizeHintShown ? model.localized("resize_note") : model.localized("resize_hint"))
    }

    private func toastView(_ toast: AppModel.Toast) -> some View {
        HStack(spacing: 10) {
            Text(toast.text)
                .lineLimit(2)
            if toast.offersUndo {
                Button(model.localized("undo")) { model.performUndo() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4, y: 2)
    }
}

struct TagPickerView: View {
    @EnvironmentObject private var model: AppModel
    let noteID: UUID?
    @State private var newTagName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(model.localized("note_tags"))
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.tags) { tag in
                        Button {
                            toggle(tag)
                        } label: {
                            HStack {
                                Image(systemName: contains(tag) ? "checkmark.square.fill" : "square")
                                Text(tag.name)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                    }
                }
            }
            .frame(maxHeight: 190)
            Divider()
            Text(model.localized("new_tag"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField(model.localized("tag_name"), text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createTag)
                Button(action: createTag) { Image(systemName: "plus") }
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 230)
    }

    private func contains(_ tag: TagRecord) -> Bool {
        guard let noteID, let note = model.notes.first(where: { $0.id == noteID }) else { return false }
        return note.tagIDs.contains(tag.id)
    }

    private func toggle(_ tag: TagRecord) {
        if contains(tag) {
            model.removeTag(tag.id, from: noteID)
        } else {
            model.addTag(tag.id, to: noteID)
        }
    }

    private func createTag() {
        if model.createTag(named: newTagName, addTo: noteID) != nil { newTagName = "" }
    }
}
