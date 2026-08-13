import XCTest

@testable import SimpleMenuNote

final class MarkdownPreviewParserTests: XCTestCase {
    func testParsesBasicMarkdownBlocks() {
        let markdown = """
        # Heading

        A paragraph with **bold**, *italic*, [link](https://example.com), and `code`.

        - First
        - Second

        1. One
        2. Two

        > Quoted text

        ---

        ```swift
        let answer = 42
        ```
        """

        XCTAssertEqual(MarkdownPreviewParser.parse(markdown).map(\.content), [
            .heading(level: 1, text: "Heading"),
            .paragraph("A paragraph with **bold**, *italic*, [link](https://example.com), and `code`."),
            .unorderedList(["First", "Second"]),
            .orderedList(["One", "Two"]),
            .blockquote("Quoted text"),
            .horizontalRule,
            .code("let answer = 42")
        ])
    }

    func testNormalizesLineEndingsAndPreservesParagraphLines() {
        XCTAssertEqual(
            MarkdownPreviewParser.parse("First\r\nSecond\r\n\r\n## 見出し").map(\.content),
            [
                .paragraph("First\nSecond"),
                .heading(level: 2, text: "見出し")
            ]
        )
    }

    func testMalformedMarkdownRemainsVisibleAsParagraphText() {
        XCTAssertEqual(
            MarkdownPreviewParser.parse("#NoSpace\n1.NotAList").map(\.content),
            [.paragraph("#NoSpace\n1.NotAList")]
        )
    }

    func testSourceRangesUseUTF16AndPreserveOriginalLineEndings() throws {
        let markdown = "# 見出し\r\n\r\n本文😀\r\n二行目\r\n\r\n- 一\r\n- 二"
        let blocks = MarkdownPreviewParser.parse(markdown)
        let source = markdown as NSString

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(source.substring(with: blocks[0].sourceRange), "# 見出し")
        XCTAssertEqual(source.substring(with: blocks[1].sourceRange), "本文😀\r\n二行目")
        XCTAssertEqual(source.substring(with: blocks[2].sourceRange), "- 一\r\n- 二")
        XCTAssertEqual(blocks[1].sourceRange.location, ("# 見出し\r\n\r\n" as NSString).length)
    }

    func testEditingOneRangeLeavesSurroundingMarkdownUntouched() throws {
        let markdown = "# Title\n\nBefore\n\n- One\n- Two\n\nAfter"
        let blocks = MarkdownPreviewParser.parse(markdown)
        let list = try XCTUnwrap(blocks.first { block in
            if case .unorderedList = block.content { return true }
            return false
        })

        let edited = (markdown as NSString).replacingCharacters(
            in: list.sourceRange,
            with: "- One\n- Two edited"
        )

        XCTAssertEqual(edited, "# Title\n\nBefore\n\n- One\n- Two edited\n\nAfter")
        XCTAssertEqual(MarkdownPreviewParser.parse(edited).map(\.content), [
            .heading(level: 1, text: "Title"),
            .paragraph("Before"),
            .unorderedList(["One", "Two edited"]),
            .paragraph("After")
        ])
    }
}
