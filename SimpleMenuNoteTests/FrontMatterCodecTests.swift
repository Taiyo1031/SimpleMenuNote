import XCTest
@testable import SimpleMenuNote

final class FrontMatterCodecTests: XCTestCase {
    func testRoundTripPreservesBodyUnicodeAndUnknownKeys() throws {
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let body = "# 今日やること\n\n- Maya\n- レポート 🌞"
        let source = FrontMatterCodec.render(
            id: id,
            createdAt: created,
            updatedAt: created,
            tagNames: ["TODO", "学校 \"A\""],
            body: body,
            unmanagedLines: ["pinned: false", "custom: value"]
        )

        let parsed = FrontMatterCodec.parse(source)
        XCTAssertEqual(parsed.id, id)
        XCTAssertEqual(parsed.tagNames, ["TODO", "学校 \"A\""])
        XCTAssertEqual(parsed.body, body)
        XCTAssertTrue(parsed.unmanagedLines.contains("pinned: false"))
        XCTAssertTrue(parsed.unmanagedLines.contains("custom: value"))
    }

    func testParsesCRLF() {
        let id = UUID()
        let source = "---\r\nid: \"\(id.uuidString)\"\r\ncreated: \"2026-08-08T15:23:15+09:00\"\r\nupdated: \"2026-08-08T15:23:15+09:00\"\r\ntags:\r\n  - \"TODO\"\r\n---\r\n\r\n本文"
        let parsed = FrontMatterCodec.parse(source)
        XCTAssertEqual(parsed.id, id)
        XCTAssertEqual(parsed.tagNames, ["TODO"])
        XCTAssertEqual(parsed.body, "本文")
    }

    func testPlainMarkdownIsEntireBody() {
        let source = "# Plain note\n\nNo front matter"
        let parsed = FrontMatterCodec.parse(source)
        XCTAssertFalse(parsed.hadValidFrontMatter)
        XCTAssertEqual(parsed.body, source)
        XCTAssertNil(parsed.id)
    }

    func testMalformedFrontMatterDoesNotLoseText() {
        let source = "---\nid: broken\ntags:\n  - TODO\nNo closing delimiter"
        let parsed = FrontMatterCodec.parse(source)
        XCTAssertFalse(parsed.hadValidFrontMatter)
        XCTAssertEqual(parsed.body, source)
    }
}
