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

    func testSettingsCommandUsesCommandComma() throws {
        let mainMenu = try XCTUnwrap(NSApp.mainMenu)
        let item = menuItem(
            withKeyEquivalent: ",",
            modifiers: [.command],
            in: mainMenu
        )

        XCTAssertNotNil(item, "Missing Settings Command-, shortcut")
    }

    func testSettingsCommandOpensAndReusesManagementWindow() throws {
        let mainMenu = try XCTUnwrap(NSApp.mainMenu)
        let item = try XCTUnwrap(menuItem(
            withKeyEquivalent: ",",
            modifiers: [.command],
            in: mainMenu
        ))
        let action = try XCTUnwrap(item.action)

        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
        let firstWindow = try XCTUnwrap(managementWindows().first)

        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
        let secondWindow = try XCTUnwrap(managementWindows().first)
        XCTAssertTrue(firstWindow === secondWindow)
        XCTAssertEqual(managementWindows().count, 1)
    }

    func testMarkdownGuideIsAvailableInEnglishAndJapanese() throws {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimpleMenuNote-MarkdownGuide-\(UUID().uuidString)")
        let suiteName = "SimpleMenuNoteTests.MarkdownGuide.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: supportDirectory)
        }

        let model = AppModel(
            repository: NoteRepository(supportDirectory: supportDirectory),
            defaults: defaults
        )
        let expected: [(key: String, english: String, japanese: String)] = [
            ("markdown_guide_title", "Writing in Markdown", "Markdownの書き方"),
            (
                "markdown_preview_hint",
                "Select the eye to preview. Click a block to edit its Markdown, then click outside or press Command-Return. Links open in your browser. Use Command-Option-Arrows to move between notes and tags.",
                "目のボタンでプレビューし、ブロックをクリックするとMarkdown原文を編集できます。外側クリックまたは⌘Returnで表示へ戻り、リンクはブラウザで開きます。⌘⌥矢印でNoteとTagを移動できます。"
            ),
            ("markdown_heading_example", "# Heading", "# 見出し"),
            ("markdown_bold_example", "**Bold text**", "**太字のテキスト**"),
            ("markdown_italic_example", "*Italic text*", "*斜体のテキスト*"),
            ("markdown_list_example", "- List item", "- リスト項目"),
            ("markdown_link_example", "[OpenAI](https://openai.com)", "[OpenAI](https://openai.com)"),
            ("markdown_inline_code_example", "`code`", "`コード`")
        ]

        model.setLanguage(.english)
        for item in expected {
            XCTAssertEqual(model.localized(item.key), item.english)
        }

        model.setLanguage(.japanese)
        for item in expected {
            XCTAssertEqual(model.localized(item.key), item.japanese)
        }
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

    private func menuItem(
        withKeyEquivalent key: String,
        modifiers: NSEvent.ModifierFlags,
        in menu: NSMenu
    ) -> NSMenuItem? {
        for item in menu.items {
            if item.keyEquivalent == key,
               item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == modifiers {
                return item
            }
            if let submenu = item.submenu,
               let match = menuItem(withKeyEquivalent: key, modifiers: modifiers, in: submenu) {
                return match
            }
        }
        return nil
    }

    private func managementWindows() -> [NSWindow] {
        NSApp.windows.filter { window in
            window.title == "SimpleMenuNote" && window.styleMask.contains(.titled)
        }
    }
}
