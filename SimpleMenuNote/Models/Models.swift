import Foundation
import SwiftUI

struct TagRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

enum TagMode: Hashable, Codable {
    case all
    case untagged
    case tag(UUID)

    var storageKey: String {
        switch self {
        case .all: return "all"
        case .untagged: return "untagged"
        case .tag(let id): return "tag:\(id.uuidString)"
        }
    }

    static func from(storageKey: String) -> TagMode {
        if storageKey == "untagged" { return .untagged }
        if storageKey.hasPrefix("tag:"),
           let id = UUID(uuidString: String(storageKey.dropFirst(4))) {
            return .tag(id)
        }
        return .all
    }
}

struct EditorState: Codable, Equatable {
    var cursorLocation: Int = 0
    var scrollOffset: Double = 0
}

struct NoteRecord: Identifiable, Equatable {
    var id: UUID
    var fileURL: URL
    var createdAt: Date
    var updatedAt: Date
    var tagIDs: Set<UUID>
    var body: String
    var unmanagedFrontMatter: [String]
    var loadedModificationDate: Date?
    var isTransientBlank: Bool

    var firstNonEmptyLine: String? {
        body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .map { line in
                var value = line
                while value.first == "#" { value.removeFirst() }
                return value.trimmingCharacters(in: .whitespaces)
            }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    var isBlank: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum AppearanceChoice: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum LanguageChoice: String, Codable, CaseIterable, Identifiable {
    case system
    case japanese
    case english

    var id: String { rawValue }

    var languageCode: String? {
        switch self {
        case .system: return nil
        case .japanese: return "ja"
        case .english: return "en"
        }
    }
}

struct SupportMetadata: Codable {
    var schemaVersion = 1
    var tags: [TagRecord] = []
    var selectedModeKey = "all"
    var lastNoteByMode: [String: UUID] = [:]
    var editorStates: [String: EditorState] = [:]
    var transientBlankNoteID: UUID?
}

enum SaveOutcome {
    case saved(NoteRecord)
    case conflict(original: NoteRecord, recovered: NoteRecord)
}

enum SimpleMenuNoteError: LocalizedError {
    case storageUnavailable
    case invalidTag
    case duplicateTag
    case fileConflict
    case message(String)

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return "The note folder is unavailable."
        case .invalidTag:
            return "A tag must be a non-empty single line."
        case .duplicateTag:
            return "A tag with that name already exists."
        case .fileConflict:
            return "The note was changed by another application."
        case .message(let value):
            return value
        }
    }
}
