import AppKit
import Foundation

struct ScanResult {
    var notes: [NoteRecord]
    var tags: [TagRecord]
    var warnings: [String]
}

final class NoteRepository {
    private let fileManager: FileManager
    private let metadataURL: URL
    private var scopedURL: URL?
    private var isAccessingScopedURL = false

    init(fileManager: FileManager = .default, supportDirectory: URL? = nil) {
        self.fileManager = fileManager
        let root = supportDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("SimpleMenuNote", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        metadataURL = root.appendingPathComponent("metadata.json")
    }

    deinit {
        stopAccessingFolder()
    }

    func loadMetadata() -> SupportMetadata {
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(SupportMetadata.self, from: data) else {
            return SupportMetadata()
        }
        return metadata
    }

    func saveMetadata(_ metadata: SupportMetadata) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    func makeBookmark(for folderURL: URL) throws -> Data {
        try folderURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) throws -> (url: URL, refreshedBookmark: Data?) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale ? try makeBookmark(for: url) : nil)
    }

    @discardableResult
    func startAccessingFolder(_ url: URL) -> Bool {
        stopAccessingFolder()
        scopedURL = url
        isAccessingScopedURL = url.startAccessingSecurityScopedResource()
        return isAccessingScopedURL
    }

    func stopAccessingFolder() {
        if isAccessingScopedURL {
            scopedURL?.stopAccessingSecurityScopedResource()
        }
        scopedURL = nil
        isAccessingScopedURL = false
    }

    func scan(folderURL: URL, knownTags: [TagRecord], transientBlankID: UUID?) throws -> ScanResult {
        guard fileManager.fileExists(atPath: folderURL.path) else {
            throw SimpleMenuNoteError.storageUnavailable
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isHiddenKey,
            .creationDateKey,
            .contentModificationDateKey
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "md" }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var tags = knownTags
        // Metadata is user-editable JSON.  Avoid trapping if a damaged file contains
        // duplicate tag names that differ only by case, and keep the oldest record.
        var tagsByName: [String: TagRecord] = [:]
        tags = tags.filter { tag in
            let key = normalizedTagName(tag.name)
            guard tagsByName[key] == nil else { return false }
            tagsByName[key] = tag
            return true
        }
        var seenIDs = Set<UUID>()
        var notes: [NoteRecord] = []
        var warnings: [String] = []

        for url in urls {
            do {
                let values = try url.resourceValues(forKeys: resourceKeys)
                guard values.isRegularFile == true, values.isHidden != true else { continue }
                let source = try String(contentsOf: url, encoding: .utf8)
                let parsed = FrontMatterCodec.parse(source)
                let fallbackCreated = values.creationDate ?? values.contentModificationDate ?? Date()
                let fallbackUpdated = values.contentModificationDate ?? fallbackCreated
                var id = parsed.id ?? UUID()
                var needsRewrite = !parsed.hadValidFrontMatter || parsed.id == nil

                if seenIDs.contains(id) {
                    id = UUID()
                    needsRewrite = true
                    warnings.append("Duplicate note ID repaired in \(url.lastPathComponent)")
                }
                seenIDs.insert(id)

                var tagIDs = Set<UUID>()
                var canonicalTagNames: [String] = []
                for rawName in parsed.tagNames {
                    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    let key = normalizedTagName(name)
                    let tag: TagRecord
                    if let existing = tagsByName[key] {
                        tag = existing
                    } else {
                        tag = TagRecord(name: name)
                        tags.append(tag)
                        tagsByName[key] = tag
                    }
                    if tagIDs.insert(tag.id).inserted {
                        canonicalTagNames.append(tag.name)
                    }
                }

                let createdAt = parsed.createdAt ?? fallbackCreated
                let updatedAt = parsed.updatedAt ?? fallbackUpdated
                if parsed.createdAt == nil || parsed.updatedAt == nil { needsRewrite = true }

                if needsRewrite {
                    let repaired = FrontMatterCodec.render(
                        id: id,
                        createdAt: createdAt,
                        updatedAt: updatedAt,
                        tagNames: canonicalTagNames,
                        body: parsed.body,
                        unmanagedLines: parsed.unmanagedLines
                    )
                    try writeAtomically(repaired, to: url)
                }

                let modificationDate = modificationDate(of: url)
                notes.append(NoteRecord(
                    id: id,
                    fileURL: url,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    tagIDs: tagIDs,
                    body: parsed.body,
                    unmanagedFrontMatter: parsed.unmanagedLines,
                    loadedModificationDate: modificationDate ?? fallbackUpdated,
                    isTransientBlank: transientBlankID == id && parsed.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ))
            } catch {
                warnings.append("Could not read \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return ScanResult(notes: notes, tags: tags, warnings: warnings)
    }

    func createNote(folderURL: URL, tagNames: [String]) throws -> NoteRecord {
        let now = Date()
        let id = UUID()
        let url = uniqueNoteURL(folderURL: folderURL, date: now, id: id)
        let source = FrontMatterCodec.render(
            id: id,
            createdAt: now,
            updatedAt: now,
            tagNames: tagNames,
            body: "",
            unmanagedLines: []
        )
        try writeAtomically(source, to: url)
        let modificationDate = modificationDate(of: url)
        return NoteRecord(
            id: id,
            fileURL: url,
            createdAt: now,
            updatedAt: now,
            tagIDs: [],
            body: "",
            unmanagedFrontMatter: [],
            loadedModificationDate: modificationDate ?? now,
            isTransientBlank: true
        )
    }

    func save(_ note: NoteRecord, tagNames: [String], detectConflicts: Bool = true) throws -> SaveOutcome {
        if detectConflicts,
           let loadedDate = note.loadedModificationDate,
           fileManager.fileExists(atPath: note.fileURL.path),
           let diskDate = modificationDate(of: note.fileURL),
           abs(diskDate.timeIntervalSince(loadedDate)) > 0.001 {
            let now = Date()
            let recoveredID = UUID()
            let recoveredURL = uniqueNoteURL(folderURL: note.fileURL.deletingLastPathComponent(), date: now, id: recoveredID)
            let source = FrontMatterCodec.render(
                id: recoveredID,
                createdAt: now,
                updatedAt: now,
                tagNames: tagNames,
                body: note.body,
                unmanagedLines: note.unmanagedFrontMatter
            )
            try writeAtomically(source, to: recoveredURL)
            let recoveredDate = modificationDate(of: recoveredURL)
            var recovered = note
            recovered.id = recoveredID
            recovered.fileURL = recoveredURL
            recovered.createdAt = now
            recovered.updatedAt = now
            recovered.loadedModificationDate = recoveredDate ?? now
            recovered.isTransientBlank = false
            return .conflict(original: note, recovered: recovered)
        }

        var saved = note
        saved.updatedAt = Date()
        let source = FrontMatterCodec.render(
            id: saved.id,
            createdAt: saved.createdAt,
            updatedAt: saved.updatedAt,
            tagNames: tagNames,
            body: saved.body,
            unmanagedLines: saved.unmanagedFrontMatter
        )
        try writeAtomically(source, to: saved.fileURL)
        saved.loadedModificationDate = modificationDate(of: saved.fileURL)
        saved.isTransientBlank = saved.isBlank && saved.isTransientBlank
        return .saved(saved)
    }

    @discardableResult
    func trash(_ note: NoteRecord) throws -> URL? {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: note.fileURL, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }

    func restoreDeletedNote(_ note: NoteRecord, tagNames: [String]) throws -> NoteRecord {
        var restored = note
        let folderURL = note.fileURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: restored.fileURL.path) {
            restored.fileURL = uniqueNoteURL(folderURL: folderURL, date: note.createdAt, id: note.id)
        }

        let source = FrontMatterCodec.render(
            id: restored.id,
            createdAt: restored.createdAt,
            updatedAt: restored.updatedAt,
            tagNames: tagNames,
            body: restored.body,
            unmanagedLines: restored.unmanagedFrontMatter
        )
        try writeAtomically(source, to: restored.fileURL)
        restored.loadedModificationDate = modificationDate(of: restored.fileURL) ?? Date()
        return restored
    }

    func moveMarkdownFiles(from sourceFolder: URL, to destinationFolder: URL) throws {
        let sourceFiles = try fileManager.contentsOfDirectory(
            at: sourceFolder,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "md" }

        guard !sourceFiles.isEmpty else { return }
        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let staging = destinationFolder.appendingPathComponent(
            ".simplemenunote-migration-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        var stagedPairs: [(source: URL, staged: URL, destination: URL)] = []

        do {
            for source in sourceFiles {
                let staged = staging.appendingPathComponent(source.lastPathComponent)
                try fileManager.copyItem(at: source, to: staged)
                let sourceSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize
                let stagedSize = try staged.resourceValues(forKeys: [.fileSizeKey]).fileSize
                guard sourceSize == stagedSize else {
                    throw SimpleMenuNoteError.message("Could not verify \(source.lastPathComponent).")
                }
                let destination = uniqueDestinationURL(
                    in: destinationFolder,
                    preferredName: source.lastPathComponent
                )
                stagedPairs.append((source, staged, destination))
            }

            for pair in stagedPairs {
                try fileManager.moveItem(at: pair.staged, to: pair.destination)
            }
            for pair in stagedPairs {
                try fileManager.removeItem(at: pair.source)
            }
            try? fileManager.removeItem(at: staging)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private func writeAtomically(_ source: String, to url: URL) throws {
        guard let data = source.data(using: .utf8) else {
            throw SimpleMenuNoteError.message("The note could not be encoded as UTF-8.")
        }
        try data.write(to: url, options: .atomic)
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private func uniqueNoteURL(folderURL: URL, date: Date, id: UUID) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let shortID = id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        let preferred = "\(formatter.string(from: date))_\(shortID).md"
        return uniqueDestinationURL(in: folderURL, preferredName: preferred)
    }

    private func uniqueDestinationURL(in folder: URL, preferredName: String) -> URL {
        let preferred = folder.appendingPathComponent(preferredName)
        guard fileManager.fileExists(atPath: preferred.path) else { return preferred }
        let base = preferred.deletingPathExtension().lastPathComponent
        return folder.appendingPathComponent("\(base)_\(UUID().uuidString.prefix(8)).md")
    }

    private func normalizedTagName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
