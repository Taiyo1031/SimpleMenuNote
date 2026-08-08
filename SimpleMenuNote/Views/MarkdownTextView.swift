import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    let noteID: UUID
    let fontSize: Double
    let restorationState: EditorState
    let focusToken: Int
    let onStateChange: (EditorState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

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
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.drawsBackground = false
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.installScrollObserver()
        context.coordinator.restore(noteID: noteID, state: restorationState, focus: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let changedNote = context.coordinator.currentNoteID != noteID
        if changedNote {
            textView.string = text
            context.coordinator.restore(noteID: noteID, state: restorationState, focus: true)
        } else if textView.string != text, !textView.hasMarkedText() {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            ))
        }

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var currentNoteID: UUID?
        var lastFocusToken = -1
        private var scrollObserver: NSObjectProtocol?
        private var isRestoring = false

        init(parent: MarkdownTextView) {
            self.parent = parent
        }

        deinit {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }

        func installScrollObserver() {
            guard let contentView = scrollView?.contentView else { return }
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: contentView,
                queue: .main
            ) { [weak self] _ in
                self?.publishState()
            }
        }

        func restore(noteID: UUID, state: EditorState, focus: Bool) {
            currentNoteID = noteID
            lastFocusToken = parent.focusToken
            guard let textView, let scrollView else { return }
            isRestoring = true
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(state.cursorLocation, length), length: 0))
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let maxOffset = max(
                    0,
                    (textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0)
                        - scrollView.contentSize.height
                )
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, state.scrollOffset), maxOffset)))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                if focus { textView.window?.makeFirstResponder(textView) }
                self.isRestoring = false
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            publishState()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            publishState()
        }

        private func publishState() {
            guard !isRestoring, currentNoteID == parent.noteID, let textView, let scrollView else { return }
            parent.onStateChange(EditorState(
                cursorLocation: textView.selectedRange().location,
                scrollOffset: scrollView.contentView.bounds.origin.y
            ))
        }
    }
}
