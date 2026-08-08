import XCTest
@testable import SimpleMenuNote

final class NoteRepositoryTests: XCTestCase {
    private var root: URL!
    private var notesFolder: URL!
    private var supportFolder: URL!
    private var repository: NoteRepository!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimpleMenuNoteTests-\(UUID().uuidString)", isDirectory: true)
        notesFolder = root.appendingPathComponent("Notes", isDirectory: true)
        supportFolder = root.appendingPathComponent("Support", isDirectory: true)
        try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: supportFolder, withIntermediateDirectories: true)
        repository = NoteRepository(supportDirectory: supportFolder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testScanImportsPlainMarkdownAndAddsFrontMatter() throws {
        let url = notesFolder.appendingPathComponent("external.md")
        try "# External\n\n本文".write(to: url, atomically: true, encoding: .utf8)

        let result = try repository.scan(folderURL: notesFolder, knownTags: [], transientBlankID: nil)

        XCTAssertEqual(result.notes.count, 1)
        XCTAssertEqual(result.notes[0].body, "# External\n\n本文")
        XCTAssertNotNil(FrontMatterCodec.parse(try String(contentsOf: url)).id)
    }

    func testScanRepairsDuplicateIDsWithoutChangingBodies() throws {
        let id = UUID()
        let date = Date()
        for index in 0..<2 {
            let body = "Body \(index)"
            let source = FrontMatterCodec.render(
                id: id,
                createdAt: date,
                updatedAt: date,
                tagNames: ["TODO"],
                body: body,
                unmanagedLines: []
            )
            try source.write(
                to: notesFolder.appendingPathComponent("\(index).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let result = try repository.scan(folderURL: notesFolder, knownTags: [], transientBlankID: nil)

        XCTAssertEqual(result.notes.count, 2)
        XCTAssertEqual(Set(result.notes.map(\.id)).count, 2)
        XCTAssertEqual(Set(result.notes.map(\.body)), Set(["Body 0", "Body 1"]))
        XCTAssertEqual(result.tags.map(\.name), ["TODO"])
    }

    func testExternalConflictCreatesRecoveredNote() throws {
        var note = try repository.createNote(folderURL: notesFolder, tagNames: ["TODO"])
        note.tagIDs = [UUID()]
        note.body = "Local edit"
        try "External edit".write(to: note.fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 20)],
            ofItemAtPath: note.fileURL.path
        )

        let result = try repository.save(note, tagNames: ["TODO"], detectConflicts: true)
        guard case .conflict(_, let recovered) = result else {
            return XCTFail("Expected a conflict recovery")
        }
        XCTAssertNotEqual(recovered.id, note.id)
        XCTAssertEqual(recovered.body, "Local edit")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovered.fileURL.path))
        XCTAssertEqual(try String(contentsOf: note.fileURL), "External edit")
    }

    func testMoveCopiesThenRemovesSourceMarkdown() throws {
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        let source = notesFolder.appendingPathComponent("note.md")
        try "hello".write(to: source, atomically: true, encoding: .utf8)

        try repository.moveMarkdownFiles(from: notesFolder, to: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("note.md")), "hello")
    }

    func testMetadataRoundTrip() throws {
        let tag = TagRecord(name: "Idea")
        let noteID = UUID()
        var metadata = SupportMetadata()
        metadata.tags = [tag]
        metadata.lastNoteByMode[TagMode.tag(tag.id).storageKey] = noteID
        metadata.editorStates[noteID.uuidString] = EditorState(cursorLocation: 12, scrollOffset: 44)

        try repository.saveMetadata(metadata)
        let loaded = repository.loadMetadata()

        XCTAssertEqual(loaded.tags, [tag])
        XCTAssertEqual(loaded.lastNoteByMode[TagMode.tag(tag.id).storageKey], noteID)
        XCTAssertEqual(loaded.editorStates[noteID.uuidString], EditorState(cursorLocation: 12, scrollOffset: 44))
    }

    func testScanHandlesOneThousandNotes() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<1_000 {
            let source = FrontMatterCodec.render(
                id: UUID(),
                createdAt: date.addingTimeInterval(Double(index)),
                updatedAt: date,
                tagNames: index.isMultiple(of: 2) ? ["TODO"] : ["Idea"],
                body: "Note \(index)",
                unmanagedLines: []
            )
            try source.write(
                to: notesFolder.appendingPathComponent("note-\(index).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let start = Date()
        let result = try repository.scan(folderURL: notesFolder, knownTags: [], transientBlankID: nil)

        XCTAssertEqual(result.notes.count, 1_000)
        XCTAssertEqual(Set(result.tags.map(\.name)), Set(["TODO", "Idea"]))
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }
}
