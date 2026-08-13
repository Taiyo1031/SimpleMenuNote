import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private enum DefaultsKey {
        static let folderBookmark = "noteFolderBookmark"
        static let appearance = "appearance"
        static let language = "language"
        static let fontSize = "fontSize"
        static let popoverHeight = "popoverHeight"
        static let resizeHintShown = "resizeHintShown"
        static let navigationHintShown = "navigationHintShown"
        static let noteDeleteConfirmed = "noteDeleteConfirmed"
        static let tagDeleteConfirmed = "tagDeleteConfirmed"
    }

    struct Toast: Equatable {
        let text: String
        let offersUndo: Bool
    }

    private enum UndoAction {
        case restoreRemovedTag(noteID: UUID, tagID: UUID, mode: TagMode)
        case restoreDeletedNote(note: NoteRecord, selectedMode: TagMode)
        case restoreDeletedTag(tag: TagRecord, noteIDs: [UUID], selectedMode: TagMode)
    }

    @Published private(set) var notes: [NoteRecord] = []
    @Published private(set) var tags: [TagRecord] = []
    @Published var selectedMode: TagMode = .all
    @Published var currentNoteID: UUID?
    @Published var selectedManagementNoteID: UUID?
    @Published private(set) var folderURL: URL?
    @Published var appearance: AppearanceChoice
    @Published var language: LanguageChoice
    @Published var fontSize: Double
    @Published var popoverHeight: Double
    @Published private(set) var resizeHintShown: Bool
    @Published private(set) var navigationHintShown: Bool
    @Published var errorMessage: String?
    @Published var toast: Toast?
    @Published private(set) var launchAtLoginEnabled = false
    @Published var editorFocusToken = 0
    @Published var managementSection: ManagementSection = .notes

    var requestManagementWindow: ((ManagementSection) -> Void)?
    var requestPopoverClose: (() -> Void)?

    private let repository: NoteRepository
    private let defaults: UserDefaults
    private var metadata: SupportMetadata
    private var saveTask: Task<Void, Never>?
    private var metadataSaveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var undoAction: UndoAction?
    private var dirtyNoteIDs = Set<UUID>()

    init(repository: NoteRepository = NoteRepository(), defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults
        metadata = repository.loadMetadata()
        appearance = AppearanceChoice(
            rawValue: defaults.string(forKey: DefaultsKey.appearance) ?? "system"
        ) ?? .system
        language = LanguageChoice(
            rawValue: defaults.string(forKey: DefaultsKey.language) ?? "system"
        ) ?? .system
        let storedFontSize = defaults.double(forKey: DefaultsKey.fontSize)
        fontSize = storedFontSize == 0 ? 14 : storedFontSize
        let storedHeight = defaults.double(forKey: DefaultsKey.popoverHeight)
        popoverHeight = storedHeight == 0 ? 320 : min(max(storedHeight, 180), 700)
        resizeHintShown = defaults.bool(forKey: DefaultsKey.resizeHintShown)
        navigationHintShown = defaults.bool(forKey: DefaultsKey.navigationHintShown)
        selectedMode = TagMode.from(storageKey: metadata.selectedModeKey)
        tags = metadata.tags
        ensureInitialTags()
    }

    func bootstrap() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        guard let bookmark = defaults.data(forKey: DefaultsKey.folderBookmark) else { return }
        do {
            let resolved = try repository.resolveBookmark(bookmark)
            if let refreshed = resolved.refreshedBookmark {
                defaults.set(refreshed, forKey: DefaultsKey.folderBookmark)
            }
            repository.startAccessingFolder(resolved.url)
            folderURL = resolved.url
            try performScan(flushFirst: false)
        } catch {
            folderURL = nil
            errorMessage = localized("storage_access_error")
        }
    }

    func localized(_ key: String) -> String {
        let bundle: Bundle
        if let code = language.languageCode,
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            bundle = localizedBundle
        } else {
            bundle = .main
        }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    var preferredColorScheme: ColorScheme? { appearance.colorScheme }

    var currentNote: NoteRecord? {
        guard let currentNoteID else { return nil }
        return notes.first { $0.id == currentNoteID }
    }

    var modeNotes: [NoteRecord] {
        notes.filter { note in
            switch selectedMode {
            case .all: return true
            case .untagged: return note.tagIDs.isEmpty
            case .tag(let tagID): return note.tagIDs.contains(tagID)
            }
        }
        .sorted {
            if $0.createdAt == $1.createdAt {
                return $0.fileURL.lastPathComponent < $1.fileURL.lastPathComponent
            }
            return $0.createdAt < $1.createdAt
        }
    }

    var currentPosition: Int? {
        guard let currentNoteID else { return nil }
        return modeNotes.firstIndex { $0.id == currentNoteID }.map { $0 + 1 }
    }

    var canGoPrevious: Bool { currentPosition != nil && modeNotes.count > 1 }
    var canGoNext: Bool { currentPosition != nil && modeNotes.count > 1 }

    var tagModes: [TagMode] {
        let sortedTags = tags.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return [.all] + sortedTags.map { .tag($0.id) } + [.untagged]
    }

    func modeDisplayName(_ mode: TagMode) -> String {
        switch mode {
        case .all: return localized("all_notes")
        case .untagged: return localized("untagged")
        case .tag(let id): return tags.first(where: { $0.id == id })?.name ?? localized("all_notes")
        }
    }

    func title(for note: NoteRecord) -> String {
        note.firstNonEmptyLine ?? localized("untitled_note")
    }

    func tagName(for id: UUID) -> String {
        tags.first(where: { $0.id == id })?.name ?? ""
    }

    func tags(for note: NoteRecord) -> [TagRecord] {
        tags.filter { note.tagIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func selectMode(_ mode: TagMode) {
        flushPendingSave()
        selectedMode = mode
        metadata.selectedModeKey = mode.storageKey
        let candidates = modeNotes
        if let remembered = metadata.lastNoteByMode[mode.storageKey],
           candidates.contains(where: { $0.id == remembered }) {
            currentNoteID = remembered
        } else {
            currentNoteID = candidates.first?.id
        }
        rememberCurrentNote()
        requestEditorFocus()
    }

    func selectNote(_ id: UUID?) {
        guard currentNoteID != id else { return }
        flushPendingSave()
        currentNoteID = id
        if let id { metadata.lastNoteByMode[selectedMode.storageKey] = id }
        scheduleMetadataSave()
        requestEditorFocus()
    }

    func selectManagementNote(_ id: UUID?) {
        flushPendingSave()
        selectedManagementNoteID = id
    }

    func goPrevious() {
        guard let index = currentPosition.map({ $0 - 1 }), modeNotes.count > 1 else { return }
        selectNote(modeNotes[(index - 1 + modeNotes.count) % modeNotes.count].id)
    }

    func goNext() {
        guard let index = currentPosition.map({ $0 - 1 }), modeNotes.count > 1 else { return }
        selectNote(modeNotes[(index + 1) % modeNotes.count].id)
    }

    func goToPreviousTagMode() {
        guard let index = tagModes.firstIndex(of: selectedMode), !tagModes.isEmpty else { return }
        selectMode(tagModes[(index - 1 + tagModes.count) % tagModes.count])
    }

    func goToNextTagMode() {
        guard let index = tagModes.firstIndex(of: selectedMode), !tagModes.isEmpty else { return }
        selectMode(tagModes[(index + 1) % tagModes.count])
    }

    func createNote() {
        guard let folderURL else {
            chooseInitialFolder()
            return
        }
        flushPendingSave()

        if let blankID = metadata.transientBlankNoteID,
           let blankIndex = notes.firstIndex(where: { $0.id == blankID && $0.isBlank }) {
            switch selectedMode {
            case .all:
                break
            case .untagged:
                notes[blankIndex].tagIDs.removeAll()
            case .tag(let tagID):
                notes[blankIndex].tagIDs.insert(tagID)
            }
            saveNote(at: blankIndex, detectConflicts: true)
            currentNoteID = blankID
            rememberCurrentNote()
            requestEditorFocus()
            return
        }

        do {
            let inheritedTagIDs: Set<UUID>
            switch selectedMode {
            case .tag(let id): inheritedTagIDs = [id]
            case .all, .untagged: inheritedTagIDs = []
            }
            let names = tags.filter { inheritedTagIDs.contains($0.id) }.map(\.name)
            var note = try repository.createNote(folderURL: folderURL, tagNames: names)
            note.tagIDs = inheritedTagIDs
            notes.append(note)
            metadata.transientBlankNoteID = note.id
            currentNoteID = note.id
            selectedManagementNoteID = note.id
            rememberCurrentNote()
            saveMetadataNow()
            requestEditorFocus()
        } catch {
            present(error)
        }
    }

    func updateCurrentBody(_ body: String) {
        guard let id = currentNoteID,
              let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].body != body else { return }
        notes[index].body = body
        dirtyNoteIDs.insert(id)
        if !notes[index].isBlank {
            notes[index].isTransientBlank = false
            if metadata.transientBlankNoteID == id { metadata.transientBlankNoteID = nil }
        }
        scheduleSave(noteID: id)
    }

    func updateBody(noteID: UUID, body: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }),
              notes[index].body != body else { return }
        notes[index].body = body
        dirtyNoteIDs.insert(noteID)
        if !notes[index].isBlank {
            notes[index].isTransientBlank = false
            if metadata.transientBlankNoteID == noteID { metadata.transientBlankNoteID = nil }
        }
        scheduleSave(noteID: noteID)
    }

    func addTag(_ tagID: UUID, to noteID: UUID? = nil) {
        let targetID = noteID ?? currentNoteID
        guard let targetID, let index = notes.firstIndex(where: { $0.id == targetID }) else { return }
        notes[index].tagIDs.insert(tagID)
        saveNote(at: index, detectConflicts: true)
    }

    func removeTag(_ tagID: UUID, from noteID: UUID? = nil) {
        let targetID = noteID ?? currentNoteID
        guard let targetID,
              let index = notes.firstIndex(where: { $0.id == targetID }),
              notes[index].tagIDs.contains(tagID) else { return }

        let oldModeNotes = modeNotes
        let oldPosition = oldModeNotes.firstIndex { $0.id == targetID } ?? 0
        notes[index].tagIDs.remove(tagID)
        saveNote(at: index, detectConflicts: true)

        if selectedMode == .tag(tagID) {
            let remaining = modeNotes
            currentNoteID = remaining.indices.contains(oldPosition)
                ? remaining[oldPosition].id
                : remaining.last?.id
            undoAction = .restoreRemovedTag(noteID: targetID, tagID: tagID, mode: selectedMode)
            showToast(localized("removed_from_tag"), offersUndo: true)
        }
        rememberCurrentNote()
    }

    @discardableResult
    func createTag(named rawName: String, addTo noteID: UUID? = nil) -> TagRecord? {
        do {
            let name = try validatedTagName(rawName, excluding: nil)
            let tag = TagRecord(name: name)
            tags.append(tag)
            tags.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            metadata.tags = tags
            if let target = noteID ?? currentNoteID { addTag(tag.id, to: target) }
            saveMetadataNow()
            return tag
        } catch {
            present(error)
            return nil
        }
    }

    func renameTag(_ tagID: UUID, to rawName: String) {
        guard let tagIndex = tags.firstIndex(where: { $0.id == tagID }) else { return }
        do {
            let name = try validatedTagName(rawName, excluding: tagID)
            guard tags[tagIndex].name != name else { return }
            tags[tagIndex].name = name
            tags.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            metadata.tags = tags
            for index in notes.indices where notes[index].tagIDs.contains(tagID) {
                saveNote(at: index, detectConflicts: true)
            }
            saveMetadataNow()
        } catch {
            present(error)
        }
    }

    var requiresTagDeleteConfirmation: Bool {
        !defaults.bool(forKey: DefaultsKey.tagDeleteConfirmed)
    }

    func deleteTag(_ tagID: UUID, confirmed: Bool = false) {
        flushPendingSave()
        guard let deletedTag = tags.first(where: { $0.id == tagID }) else { return }
        let affectedIDs = notes.filter { $0.tagIDs.contains(tagID) }.map(\.id)
        let previousMode = selectedMode
        for id in affectedIDs {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { continue }
            notes[index].tagIDs.remove(tagID)
            saveNote(at: index, detectConflicts: true)
        }
        tags.removeAll { $0.id == tagID }
        metadata.tags = tags
        if selectedMode == .tag(tagID) { selectMode(.all) }
        saveMetadataNow()
        if confirmed {
            defaults.set(true, forKey: DefaultsKey.tagDeleteConfirmed)
        }
        undoAction = .restoreDeletedTag(tag: deletedTag, noteIDs: affectedIDs, selectedMode: previousMode)
        showToast(localized("tag_deleted"), offersUndo: true)
    }

    func noteCount(for tagID: UUID) -> Int {
        notes.reduce(into: 0) { count, note in
            if note.tagIDs.contains(tagID) { count += 1 }
        }
    }

    func requiresNoteDeleteConfirmation(for noteID: UUID) -> Bool {
        guard let note = notes.first(where: { $0.id == noteID }) else { return false }
        if note.isTransientBlank && note.isBlank { return false }
        return !defaults.bool(forKey: DefaultsKey.noteDeleteConfirmed)
    }

    @discardableResult
    func deleteNote(
        _ noteID: UUID,
        orderedNoteIDs: [UUID]? = nil,
        confirmed: Bool = false
    ) -> Bool {
        flushPendingSave()
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        let deletedNote = notes[index]
        let isDisposableBlank = deletedNote.isTransientBlank && deletedNote.isBlank
        let order = orderedNoteIDs ?? modeNotes.map(\.id)
        let removedPosition = order.firstIndex(of: noteID)
        let previousMode = selectedMode
        do {
            try repository.trash(deletedNote)
            notes.remove(at: index)
            metadata.editorStates.removeValue(forKey: noteID.uuidString)
            if metadata.transientBlankNoteID == noteID { metadata.transientBlankNoteID = nil }
            metadata.lastNoteByMode = metadata.lastNoteByMode.filter { $0.value != noteID }
            let remainingOrder = order.filter { candidate in
                candidate != noteID && notes.contains(where: { $0.id == candidate })
            }
            let fallbackID: UUID? = {
                guard !remainingOrder.isEmpty else { return nil }
                let position = min(removedPosition ?? 0, remainingOrder.count - 1)
                return remainingOrder[position]
            }()
            if currentNoteID == noteID {
                currentNoteID = fallbackID ?? modeNotes.first?.id
            }
            if selectedManagementNoteID == noteID {
                selectedManagementNoteID = fallbackID
            }
            saveMetadataNow()
            if !isDisposableBlank {
                if confirmed {
                    defaults.set(true, forKey: DefaultsKey.noteDeleteConfirmed)
                }
                undoAction = .restoreDeletedNote(note: deletedNote, selectedMode: previousMode)
                showToast(localized("note_deleted"), offersUndo: true)
            }
            return true
        } catch {
            present(error)
            return false
        }
    }

    func filteredManagementNotes(search: String, tagFilter: TagMode) -> [NoteRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return notes.filter { note in
            let modeMatches: Bool
            switch tagFilter {
            case .all: modeMatches = true
            case .untagged: modeMatches = note.tagIDs.isEmpty
            case .tag(let id): modeMatches = note.tagIDs.contains(id)
            }
            guard modeMatches else { return false }
            guard !query.isEmpty else { return true }
            let tagText = tags(for: note).map(\.name).joined(separator: " ")
            let haystack = "\(note.body) \(tagText)".folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            return haystack.contains(query)
        }
        .sorted {
            if $0.updatedAt == $1.updatedAt { return $0.createdAt > $1.createdAt }
            return $0.updatedAt > $1.updatedAt
        }
    }

    func editorState(for noteID: UUID) -> EditorState {
        metadata.editorStates[noteID.uuidString] ?? EditorState()
    }

    func updateEditorState(_ state: EditorState, for noteID: UUID) {
        guard metadata.editorStates[noteID.uuidString] != state else { return }
        metadata.editorStates[noteID.uuidString] = state
        scheduleMetadataSave()
    }

    func rescan() {
        do {
            try performScan(flushFirst: true)
            showToast(localized("notes_refreshed"), offersUndo: false)
        } catch {
            present(error)
        }
    }

    func refreshFromExternalChanges() {
        guard folderURL != nil else { return }
        do {
            try performScan(flushFirst: true)
        } catch {
            present(error)
        }
    }

    func chooseInitialFolder() {
        guard let url = chooseFolder() else { return }
        activateFolder(url)
    }

    func changeStorageFolder() {
        guard let newURL = chooseFolder(), newURL != folderURL else { return }
        let alert = NSAlert()
        alert.messageText = localized("change_storage_title")
        alert.informativeText = localized("change_storage_message")
        alert.addButton(withTitle: localized("move_existing_notes"))
        alert.addButton(withTitle: localized("new_notes_only"))
        alert.addButton(withTitle: localized("cancel"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            activateFolder(newURL, moveExisting: true)
        } else if response == .alertSecondButtonReturn {
            activateFolder(newURL, moveExisting: false)
        }
    }

    func revealStorageFolder() {
        guard let folderURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folderURL])
    }

    func setAppearance(_ choice: AppearanceChoice) {
        appearance = choice
        defaults.set(choice.rawValue, forKey: DefaultsKey.appearance)
    }

    func setLanguage(_ choice: LanguageChoice) {
        language = choice
        defaults.set(choice.rawValue, forKey: DefaultsKey.language)
        objectWillChange.send()
    }

    func setFontSize(_ size: Double) {
        fontSize = min(max(size, 12), 20)
        defaults.set(fontSize, forKey: DefaultsKey.fontSize)
    }

    func setPopoverHeight(_ height: Double) {
        popoverHeight = min(max(height, 180), 700)
        defaults.set(popoverHeight, forKey: DefaultsKey.popoverHeight)
        if !resizeHintShown {
            resizeHintShown = true
            defaults.set(true, forKey: DefaultsKey.resizeHintShown)
        }
    }

    func markResizeHintShown() {
        resizeHintShown = true
        defaults.set(true, forKey: DefaultsKey.resizeHintShown)
    }

    func markNavigationHintShown() {
        navigationHintShown = true
        defaults.set(true, forKey: DefaultsKey.navigationHintShown)
    }

    func resetDeletionConfirmations() {
        defaults.set(false, forKey: DefaultsKey.noteDeleteConfirmed)
        defaults.set(false, forKey: DefaultsKey.tagDeleteConfirmed)
        showToast(localized("delete_confirmations_reset"), offersUndo: false)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            present(error)
        }
    }

    func showManagement(_ section: ManagementSection = .notes) {
        managementSection = section
        requestManagementWindow?(section)
    }

    func closePopover() {
        flushPendingSave()
        requestPopoverClose?()
    }

    func performUndo() {
        toastTask?.cancel()
        guard let action = undoAction else { return }
        undoAction = nil
        toast = nil
        switch action {
        case .restoreRemovedTag(let noteID, let tagID, let mode):
            addTag(tagID, to: noteID)
            selectMode(mode)
            selectNote(noteID)
        case .restoreDeletedNote(let note, let mode):
            do {
                let tagNames = tags.filter { note.tagIDs.contains($0.id) }.map(\.name).sorted()
                let restored = try repository.restoreDeletedNote(note, tagNames: tagNames)
                notes.append(restored)
                selectedMode = mode
                metadata.selectedModeKey = mode.storageKey
                currentNoteID = restored.id
                selectedManagementNoteID = restored.id
                metadata.lastNoteByMode[mode.storageKey] = restored.id
                saveMetadataNow()
                requestEditorFocus()
            } catch {
                present(error)
            }
        case .restoreDeletedTag(let tag, let noteIDs, let mode):
            let restoredTag: TagRecord
            if let existing = tags.first(where: {
                normalizedTagName($0.name) == normalizedTagName(tag.name)
            }) {
                restoredTag = existing
            } else {
                restoredTag = tag
                tags.append(tag)
                tags.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            for noteID in noteIDs {
                addTag(restoredTag.id, to: noteID)
            }
            metadata.tags = tags
            if mode == .tag(tag.id) {
                selectMode(.tag(restoredTag.id))
            }
            saveMetadataNow()
        }
    }

    func dismissError() { errorMessage = nil }

    func flushPendingSave() {
        let pendingTask = saveTask
        saveTask = nil
        pendingTask?.cancel()
        let pendingIDs = dirtyNoteIDs
        for id in pendingIDs {
            if let index = notes.firstIndex(where: { $0.id == id }) {
                saveNote(at: index, detectConflicts: true)
            }
        }
        saveMetadataNow()
    }

    func applicationWillTerminate() {
        flushPendingSave()
        repository.stopAccessingFolder()
    }

    func requestEditorFocus() {
        editorFocusToken &+= 1
    }

    private func activateFolder(_ url: URL, moveExisting: Bool = false) {
        do {
            let newScope = url.startAccessingSecurityScopedResource()
            defer { if newScope { url.stopAccessingSecurityScopedResource() } }
            if moveExisting, let oldURL = folderURL {
                flushPendingSave()
                try repository.moveMarkdownFiles(from: oldURL, to: url)
            }
            let bookmark = try repository.makeBookmark(for: url)
            defaults.set(bookmark, forKey: DefaultsKey.folderBookmark)
            repository.startAccessingFolder(url)
            folderURL = url
            currentNoteID = nil
            selectedManagementNoteID = nil
            try performScan(flushFirst: false)
        } catch {
            present(error)
        }
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = localized("choose_note_folder")
        panel.prompt = localized("choose")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func performScan(flushFirst: Bool) throws {
        if flushFirst { flushPendingSave() }
        guard let folderURL else { throw SimpleMenuNoteError.storageUnavailable }
        let previousCurrent = currentNoteID
        let result = try repository.scan(
            folderURL: folderURL,
            knownTags: tags,
            transientBlankID: metadata.transientBlankNoteID
        )
        notes = result.notes
        tags = result.tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        metadata.tags = tags

        if case .tag(let id) = selectedMode, !tags.contains(where: { $0.id == id }) {
            selectedMode = .all
        }
        if let previousCurrent, modeNotes.contains(where: { $0.id == previousCurrent }) {
            currentNoteID = previousCurrent
        } else if let remembered = metadata.lastNoteByMode[selectedMode.storageKey],
                  modeNotes.contains(where: { $0.id == remembered }) {
            currentNoteID = remembered
        } else {
            currentNoteID = modeNotes.first?.id
        }
        if let selectedManagementNoteID,
           !notes.contains(where: { $0.id == selectedManagementNoteID }) {
            self.selectedManagementNoteID = nil
        }
        if self.selectedManagementNoteID == nil {
            self.selectedManagementNoteID = notes.sorted { $0.updatedAt > $1.updatedAt }.first?.id
        }
        if let transientID = metadata.transientBlankNoteID,
           !notes.contains(where: { $0.id == transientID && $0.isBlank }) {
            metadata.transientBlankNoteID = nil
        }
        rememberCurrentNote()
        saveMetadataNow()
        if let warning = result.warnings.first { errorMessage = warning }
    }

    private func scheduleSave(noteID: UUID) {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled,
                      let self,
                      let index = self.notes.firstIndex(where: { $0.id == noteID }) else { return }
                self.saveNote(at: index, detectConflicts: true)
            } catch {
                return
            }
        }
    }

    private func saveNote(at index: Int, detectConflicts: Bool) {
        guard notes.indices.contains(index) else { return }
        let note = notes[index]
        let names = tags.filter { note.tagIDs.contains($0.id) }.map(\.name).sorted()
        do {
            switch try repository.save(note, tagNames: names, detectConflicts: detectConflicts) {
            case .saved(let saved):
                if let liveIndex = notes.firstIndex(where: { $0.id == saved.id }) {
                    notes[liveIndex] = saved
                }
            case .conflict(_, let recovered):
                notes.append(recovered)
                currentNoteID = recovered.id
                selectedManagementNoteID = recovered.id
                metadata.transientBlankNoteID = nil
                showToast(localized("conflict_recovered"), offersUndo: false)
            }
            dirtyNoteIDs.remove(note.id)
            metadata.tags = tags
            saveMetadataNow()
        } catch {
            present(error)
        }
    }

    private func validatedTagName(_ rawName: String, excluding excludedID: UUID?) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("\n"), !name.contains("\r") else {
            throw SimpleMenuNoteError.invalidTag
        }
        let normalized = normalizedTagName(name)
        guard !tags.contains(where: { $0.id != excludedID && normalizedTagName($0.name) == normalized }) else {
            throw SimpleMenuNoteError.duplicateTag
        }
        return name
    }

    private func normalizedTagName(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private func ensureInitialTags() {
        guard tags.isEmpty else { return }
        tags = ["TODO", "Idea", "Temporary"].map { TagRecord(name: $0) }
        metadata.tags = tags
        saveMetadataNow()
    }

    private func rememberCurrentNote() {
        metadata.selectedModeKey = selectedMode.storageKey
        if let currentNoteID { metadata.lastNoteByMode[selectedMode.storageKey] = currentNoteID }
        scheduleMetadataSave()
    }

    private func scheduleMetadataSave() {
        metadataSaveTask?.cancel()
        metadataSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.saveMetadataNow()
            } catch {
                return
            }
        }
    }

    private func saveMetadataNow() {
        metadataSaveTask?.cancel()
        metadataSaveTask = nil
        metadata.tags = tags
        do {
            try repository.saveMetadata(metadata)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func showToast(_ text: String, offersUndo: Bool) {
        toastTask?.cancel()
        toast = Toast(text: text, offersUndo: offersUndo)
        toastTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.toast = nil
                self?.undoAction = nil
            } catch {
                return
            }
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

enum ManagementSection: String, CaseIterable, Identifiable {
    case notes
    case tags
    case settings

    var id: String { rawValue }
}
