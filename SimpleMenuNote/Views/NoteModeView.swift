import SwiftUI

struct NoteModeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTagPickerPresented = false
    @State private var resizeStartHeight: Double?
    @State private var showInitialResizeHint = false
    @State private var showNavigationHint = false
    @State private var isPreviewing = false
    @State private var finishPreviewEditingToken = 0
    @State private var confirmDelete = false

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
        .task(id: model.folderURL) {
            guard model.folderURL != nil else { return }
            await presentFirstUseHints()
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
                    if isPreviewing {
                        MarkdownPreviewView(
                            markdown: Binding(
                                get: { model.currentNote?.body ?? "" },
                                set: { model.updateCurrentBody($0) }
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
                                get: { model.currentNote?.body ?? "" },
                                set: { model.updateCurrentBody($0) }
                            ),
                            noteID: note.id,
                            fontSize: model.fontSize,
                            restorationState: model.editorState(for: note.id),
                            focusToken: model.editorFocusToken,
                            onStateChange: { model.updateEditorState($0, for: note.id) }
                        )
                    }
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
            } else if showNavigationHint {
                Text(model.localized("navigation_shortcut_hint"))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 3, y: 1)
                    .padding(.bottom, 42)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background {
            KeyboardNavigationMonitor(
                isEnabled: !confirmDelete && !isTagPickerPresented,
                previousNote: { navigate(model.goPrevious) },
                nextNote: { navigate(model.goNext) },
                previousTag: { navigate(model.goToPreviousTagMode) },
                nextTag: { navigate(model.goToNextTagMode) }
            )
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
                        .frame(maxWidth: 76)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(model.localized("switch_tag_mode_shortcut"))

            if let note = model.currentNote {
                let noteTags = model.tags(for: note)
                HStack(spacing: 3) {
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
                .frame(maxWidth: 92, alignment: .leading)
                .clipped()
            }

            Spacer(minLength: 2)

            Button {
                togglePreview()
            } label: {
                Image(systemName: isPreviewing ? "pencil" : "eye")
            }
            .buttonStyle(.plain)
            .disabled(model.currentNote == nil)
            .help(model.localized(isPreviewing ? "edit" : "preview"))

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

            Button(role: .destructive) {
                requestCurrentNoteDeletion()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(model.currentNote == nil)
            .help(model.localized("delete_note"))
            .alert(model.localized("delete_note_title"), isPresented: $confirmDelete) {
                Button(model.localized("cancel"), role: .cancel) {}
                Button(model.localized("delete"), role: .destructive) {
                    guard let noteID = model.currentNoteID else { return }
                    model.deleteNote(
                        noteID,
                        orderedNoteIDs: model.modeNotes.map(\.id),
                        confirmed: true
                    )
                }
            } message: {
                Text(model.localized("delete_note_message"))
            }

            Button {
                model.showManagement(.notes)
            } label: {
                HoverToolbarIcon(systemName: "rectangle.on.rectangle")
            }
            .buttonStyle(.plain)
            .help(model.localized("open_management"))
            .accessibilityLabel(model.localized("open_management"))
        }
        .imageScale(.small)
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

    private func navigate(_ action: () -> Void) {
        isTagPickerPresented = false
        finishPreviewEditingToken &+= 1
        model.flushPendingSave()
        action()
    }

    private func requestCurrentNoteDeletion() {
        guard let noteID = model.currentNoteID else { return }
        finishPreviewEditingToken &+= 1
        if model.requiresNoteDeleteConfirmation(for: noteID) {
            confirmDelete = true
        } else {
            model.deleteNote(noteID, orderedNoteIDs: model.modeNotes.map(\.id))
        }
    }

    @MainActor
    private func presentFirstUseHints() async {
        if !model.resizeHintShown {
            withAnimation { showInitialResizeHint = true }
            try? await Task.sleep(for: .seconds(4))
            withAnimation { showInitialResizeHint = false }
            model.markResizeHintShown()
        }
        guard !Task.isCancelled, !model.navigationHintShown else { return }
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation { showNavigationHint = true }
        try? await Task.sleep(for: .seconds(5))
        withAnimation { showNavigationHint = false }
        model.markNavigationHintShown()
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
            .help(model.localized("previous_note_shortcut"))

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
            .help(model.localized("next_note_shortcut"))
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
        UndoToastView(toast: toast)
    }
}

struct UndoToastView: View {
    @EnvironmentObject private var model: AppModel
    let toast: AppModel.Toast

    var body: some View {
        HStack(spacing: 10) {
            Text(toast.text).lineLimit(2)
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

private struct HoverToolbarIcon: View {
    let systemName: String
    @State private var hovering = false

    var body: some View {
        Image(systemName: systemName)
            .frame(width: 32, height: 28)
            .background(hovering ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

private struct KeyboardNavigationMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let previousNote: () -> Void
    let nextNote: () -> Void
    let previousTag: () -> Void
    let nextTag: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator {
        var parent: KeyboardNavigationMonitor
        weak var hostView: NSView?
        private var monitor: Any?

        init(parent: KeyboardNavigationMonitor) { self.parent = parent }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      parent.isEnabled,
                      let window = hostView?.window,
                      window.isVisible,
                      event.window === window else { return event }
                let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
                guard modifiers == [.command, .option] else { return event }
                switch event.keyCode {
                case 123: parent.previousNote()
                case 124: parent.nextNote()
                case 125: parent.nextTag()
                case 126: parent.previousTag()
                default: return event
                }
                return nil
            }
        }
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
