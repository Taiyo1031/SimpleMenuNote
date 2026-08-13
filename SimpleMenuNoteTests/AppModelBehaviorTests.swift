import XCTest

@testable import SimpleMenuNote

@MainActor
final class AppModelBehaviorTests: XCTestCase {
    func testTagModesCycleInBothDirectionsIncludingSystemModes() throws {
        let fixture = try makeModel()
        let model = fixture.model

        model.selectMode(.all)
        model.goToPreviousTagMode()
        XCTAssertEqual(model.selectedMode, .untagged)

        model.goToNextTagMode()
        XCTAssertEqual(model.selectedMode, .all)

        model.goToNextTagMode()
        let firstAlphabeticalTag = try XCTUnwrap(model.tags.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.first)
        XCTAssertEqual(model.selectedMode, .tag(firstAlphabeticalTag.id))
    }

    func testTagDeleteConfirmationPersistsOnlyAfterConfirmedDeleteAndCanReset() throws {
        let fixture = try makeModel()
        let model = fixture.model
        let tag = try XCTUnwrap(model.tags.first)

        XCTAssertTrue(model.requiresTagDeleteConfirmation)
        model.deleteTag(tag.id, confirmed: true)
        XCTAssertFalse(model.requiresTagDeleteConfirmation)
        XCTAssertFalse(model.tags.contains(where: { $0.id == tag.id }))

        model.performUndo()
        XCTAssertTrue(model.tags.contains(where: { $0.id == tag.id }))

        model.resetDeletionConfirmations()
        XCTAssertTrue(model.requiresTagDeleteConfirmation)
    }

    private func makeModel() throws -> (model: AppModel, defaults: UserDefaults, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimpleMenuNote-AppModelTests-\(UUID().uuidString)")
        let suite = "SimpleMenuNoteTests.AppModel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let repository = NoteRepository(supportDirectory: root)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return (AppModel(repository: repository, defaults: defaults), defaults, root)
    }
}
