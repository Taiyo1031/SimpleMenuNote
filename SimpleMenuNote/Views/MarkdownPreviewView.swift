import AppKit
import Foundation
import SwiftUI

enum MarkdownPreviewContent: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case blockquote(String)
    case code(String)
    case horizontalRule
}

struct MarkdownPreviewBlock: Equatable, Identifiable {
    let content: MarkdownPreviewContent
    let sourceRange: NSRange

    var id: Int { sourceRange.location }
}

enum MarkdownPreviewParser {
    private struct SourceLine {
        let text: String
        let start: Int
        let contentEnd: Int
    }

    static func parse(_ markdown: String) -> [MarkdownPreviewBlock] {
        let source = markdown as NSString
        let lines = sourceLines(in: source)
        var blocks: [MarkdownPreviewBlock] = []
        var index = 0

        func block(_ content: MarkdownPreviewContent, from start: Int, to end: Int) -> MarkdownPreviewBlock {
            let location = lines[start].start
            let upperBound = lines[max(start, end - 1)].contentEnd
            return MarkdownPreviewBlock(
                content: content,
                sourceRange: NSRange(location: location, length: upperBound - location)
            )
        }

        while index < lines.count {
            let line = lines[index].text
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let start = index
                index += 1
                var codeLines: [String] = []
                while index < lines.count,
                      !lines[index].text.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index].text)
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(block(.code(codeLines.joined(separator: "\n")), from: start, to: index))
                continue
            }

            if let heading = heading(from: line) {
                blocks.append(block(heading, from: index, to: index + 1))
                index += 1
                continue
            }

            if isHorizontalRule(line) {
                blocks.append(block(.horizontalRule, from: index, to: index + 1))
                index += 1
                continue
            }

            if unorderedItem(from: line) != nil {
                let start = index
                var items: [String] = []
                while index < lines.count, let item = unorderedItem(from: lines[index].text) {
                    items.append(item)
                    index += 1
                }
                blocks.append(block(.unorderedList(items), from: start, to: index))
                continue
            }

            if orderedItem(from: line) != nil {
                let start = index
                var items: [String] = []
                while index < lines.count, let item = orderedItem(from: lines[index].text) {
                    items.append(item)
                    index += 1
                }
                blocks.append(block(.orderedList(items), from: start, to: index))
                continue
            }

            if blockquoteText(from: line) != nil {
                let start = index
                var quoteLines: [String] = []
                while index < lines.count, let quote = blockquoteText(from: lines[index].text) {
                    quoteLines.append(quote)
                    index += 1
                }
                blocks.append(block(.blockquote(quoteLines.joined(separator: "\n")), from: start, to: index))
                continue
            }

            let start = index
            var paragraphLines: [String] = []
            while index < lines.count,
                  !lines[index].text.trimmingCharacters(in: .whitespaces).isEmpty,
                  !startsBlock(lines[index].text) {
                paragraphLines.append(lines[index].text)
                index += 1
            }
            if paragraphLines.isEmpty {
                paragraphLines.append(line)
                index += 1
            }
            blocks.append(block(.paragraph(paragraphLines.joined(separator: "\n")), from: start, to: index))
        }

        return blocks
    }

    private static func sourceLines(in source: NSString) -> [SourceLine] {
        var result: [SourceLine] = []
        var location = 0
        while location < source.length {
            var lineStart = 0
            var lineEnd = 0
            var contentEnd = 0
            source.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentEnd,
                for: NSRange(location: location, length: 0)
            )
            result.append(SourceLine(
                text: source.substring(with: NSRange(location: lineStart, length: contentEnd - lineStart)),
                start: lineStart,
                contentEnd: contentEnd
            ))
            guard lineEnd > location else { break }
            location = lineEnd
        }
        return result
    }

    private static func startsBlock(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
            || heading(from: line) != nil
            || isHorizontalRule(line)
            || unorderedItem(from: line) != nil
            || orderedItem(from: line) != nil
            || blockquoteText(from: line) != nil
    }

    private static func heading(from line: String) -> MarkdownPreviewContent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let level = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), trimmed.dropFirst(level).first == " " else { return nil }
        return .heading(level: level, text: String(trimmed.dropFirst(level + 1)))
    }

    private static func unorderedItem(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2,
              ["-", "*", "+"].contains(String(trimmed.prefix(1))),
              trimmed.dropFirst().first == " " else { return nil }
        return String(trimmed.dropFirst(2))
    }

    private static func orderedItem(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let period = trimmed.firstIndex(of: "."),
              period != trimmed.startIndex,
              trimmed[..<period].allSatisfy(\.isNumber) else { return nil }
        let afterPeriod = trimmed.index(after: period)
        guard afterPeriod < trimmed.endIndex, trimmed[afterPeriod] == " " else { return nil }
        return String(trimmed[trimmed.index(after: afterPeriod)...])
    }

    private static func blockquoteText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == ">" else { return nil }
        return String(trimmed.dropFirst().drop(while: { $0 == " " }))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first, ["-", "*", "_"].contains(marker) else {
            return false
        }
        return compact.allSatisfy { $0 == marker }
    }
}

struct MarkdownPreviewView: View {
    @Binding var markdown: String
    let noteID: UUID
    let fontSize: Double
    let restorationState: EditorState
    let finishEditingToken: Int
    let onStateChange: (EditorState) -> Void

    @State private var displayBlocks: [MarkdownPreviewBlock] = []
    @State private var editingRange: NSRange?
    @State private var editingText = ""
    @State private var editorHeight: CGFloat = 52

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if displayBlocks.isEmpty {
                    if editingRange != nil {
                        editor
                    } else {
                        Color.clear.frame(height: 44)
                    }
                } else {
                    ForEach(displayBlocks) { block in
                        if editingRange?.location == block.sourceRange.location {
                            editor
                        } else {
                            blockView(block.content)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { beginEditing(block) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { finishEditing() }
            }
        }
        .onAppear { synchronizeBlocks(startEmptyEditor: true) }
        .onChange(of: noteID) { _ in synchronizeBlocks(startEmptyEditor: true) }
        .onChange(of: markdown) { _ in
            if editingRange == nil { synchronizeBlocks(startEmptyEditor: true) }
        }
        .onChange(of: finishEditingToken) { _ in finishEditing() }
    }

    private var editor: some View {
        MarkdownBlockTextView(
            text: Binding(
                get: { editingText },
                set: { replaceEditingBlock(with: $0) }
            ),
            fontSize: fontSize,
            initialCursorLocation: localCursorLocation,
            height: $editorHeight,
            onFinish: finishEditing,
            onCursorChange: { location in
                guard let editingRange else { return }
                onStateChange(EditorState(
                    cursorLocation: editingRange.location + location,
                    scrollOffset: restorationState.scrollOffset
                ))
            }
        )
        .frame(height: editorHeight)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
    }

    private var localCursorLocation: Int {
        guard let editingRange,
              NSLocationInRange(restorationState.cursorLocation, NSRange(
                location: editingRange.location,
                length: editingRange.length + 1
              )) else { return 0 }
        return restorationState.cursorLocation - editingRange.location
    }

    private func synchronizeBlocks(startEmptyEditor: Bool) {
        editingRange = nil
        displayBlocks = MarkdownPreviewParser.parse(markdown)
        if startEmptyEditor, markdown.isEmpty {
            editingRange = NSRange(location: 0, length: 0)
            editingText = ""
        }
    }

    private func beginEditing(_ block: MarkdownPreviewBlock) {
        finishEditing()
        let source = markdown as NSString
        guard NSMaxRange(block.sourceRange) <= source.length else { return }
        displayBlocks = MarkdownPreviewParser.parse(markdown)
        editingRange = block.sourceRange
        editingText = source.substring(with: block.sourceRange)
        editorHeight = 52
    }

    private func replaceEditingBlock(with replacement: String) {
        guard var range = editingRange else { return }
        let source = markdown as NSString
        guard NSMaxRange(range) <= source.length else {
            finishEditing()
            return
        }
        markdown = source.replacingCharacters(in: range, with: replacement)
        range.length = (replacement as NSString).length
        editingRange = range
        editingText = replacement
    }

    private func finishEditing() {
        guard editingRange != nil else { return }
        editingRange = nil
        editingText = ""
        displayBlocks = MarkdownPreviewParser.parse(markdown)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownPreviewContent) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(.system(size: headingSize(level), weight: level <= 2 ? .bold : .semibold))
                .padding(.top, level <= 2 ? 4 : 0)
        case .paragraph(let text):
            Text(inlineMarkdown(text)).font(.system(size: fontSize))
        case .unorderedList(let items):
            list(items: items, ordered: false)
        case .orderedList(let items):
            list(items: items, ordered: true)
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1).fill(.tertiary).frame(width: 3)
                Text(inlineMarkdown(text))
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
            }
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: max(11, fontSize - 1), design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(10)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        case .horizontalRule:
            Divider().padding(.vertical, 4)
        }
    }

    private func list(items: [String], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .frame(width: 22, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Text(inlineMarkdown(item)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: fontSize))
            }
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private func headingSize(_ level: Int) -> Double {
        switch level {
        case 1: return fontSize + 10
        case 2: return fontSize + 7
        case 3: return fontSize + 4
        default: return fontSize + 2
        }
    }
}

private struct MarkdownBlockTextView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double
    let initialCursorLocation: Int
    @Binding var height: CGFloat
    let onFinish: () -> Void
    let onCursorChange: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 44)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 8, height: 7)
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.string = text
        textView.setSelectedRange(NSRange(
            location: min(initialCursorLocation, (text as NSString).length),
            length: 0
        ))
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            context.coordinator.updateHeight()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.string != text, !textView.hasMarkedText() {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            ))
        }
        DispatchQueue.main.async { context.coordinator.updateHeight() }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownBlockTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(parent: MarkdownBlockTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            updateHeight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            parent.onCursorChange(textView.selectedRange().location)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onFinish()
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                parent.onFinish()
                return true
            }
            return false
        }

        func updateHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let contentHeight = layoutManager.usedRect(for: textContainer).height
                + textView.textContainerInset.height * 2
            let newHeight = max(44, ceil(contentHeight))
            if let scrollView {
                textView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: newHeight))
            }
            if abs(parent.height - newHeight) > 0.5 {
                parent.height = newHeight
            }
        }
    }
}
