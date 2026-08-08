import AppKit
import XCTest

@testable import SimpleMenuNote

@MainActor
final class ApplicationMenuTests: XCTestCase {
    func testEditMenuContainsStandardTextShortcuts() throws {
        let editMenu = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "Edit")?.submenu)

        assertShortcut("z", modifiers: [.command], title: "Undo", in: editMenu)
        assertShortcut("z", modifiers: [.command, .shift], title: "Redo", in: editMenu)
        assertShortcut("x", modifiers: [.command], title: "Cut", in: editMenu)
        assertShortcut("c", modifiers: [.command], title: "Copy", in: editMenu)
        assertShortcut("v", modifiers: [.command], title: "Paste", in: editMenu)
        assertShortcut("a", modifiers: [.command], title: "Select All", in: editMenu)
    }

    private func assertShortcut(
        _ key: String,
        modifiers: NSEvent.ModifierFlags,
        title: String,
        in menu: NSMenu,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let item = menu.items.first { item in
            item.title == title
                && item.keyEquivalent == key
                && item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == modifiers
        }
        XCTAssertNotNil(item, "Missing \(title) shortcut", file: file, line: line)
    }
}
