import AppKit
import Combine
import SwiftUI

@main
struct SimpleMenuNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            ApplicationCommands(
                model: appDelegate.model,
                openSettings: { appDelegate.openSettings() }
            )
            TextEditingCommands()
        }
    }
}

private struct ApplicationCommands: Commands {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("\(model.localized("settings"))…") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}

private struct TextEditingCommands: Commands {
    var body: some Commands {
        CommandMenu("Edit") {
            Button("Undo") {
                sendAction(Selector(("undo:")))
            }
            .keyboardShortcut("z", modifiers: [.command])

            Button("Redo") {
                sendAction(Selector(("redo:")))
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Divider()

            Button("Cut") {
                sendAction(#selector(NSText.cut(_:)))
            }
            .keyboardShortcut("x", modifiers: [.command])

            Button("Copy") {
                sendAction(#selector(NSText.copy(_:)))
            }
            .keyboardShortcut("c", modifiers: [.command])

            Button("Paste") {
                sendAction(#selector(NSText.paste(_:)))
            }
            .keyboardShortcut("v", modifiers: [.command])

            Divider()

            Button("Select All") {
                sendAction(#selector(NSText.selectAll(_:)))
            }
            .keyboardShortcut("a", modifiers: [.command])
        }
    }

    private func sendAction(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var managementWindowController: ManagementWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()

        model.requestManagementWindow = { [weak self] section in
            self?.showManagement(section: section)
        }
        model.requestPopoverClose = { [weak self] in
            self?.popover.performClose(nil)
        }
        model.$popoverHeight
            .removeDuplicates()
            .sink { [weak self] height in
                self?.popover.contentSize = NSSize(width: 380, height: height)
            }
            .store(in: &cancellables)
        model.bootstrap()

        // A menu-bar-only app otherwise has no visible first-launch surface. Show
        // onboarding once the status item has joined the menu bar so users can
        // select storage immediately and can see where the item is anchored.
        if model.folderURL == nil {
            DispatchQueue.main.async { [weak self] in
                self?.showPopover()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshFromExternalChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.applicationWillTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func popoverDidClose(_ notification: Notification) {
        model.flushPendingSave()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    @objc private func openNotes() {
        showManagement(section: .notes)
    }

    @objc func openSettings() {
        showManagement(section: .settings)
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.isVisible = true
        guard let button = item.button else { return }

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(
            systemSymbolName: "note.text",
            accessibilityDescription: "SimpleMenuNote"
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        if let image {
            button.image = image
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        } else {
            // This should only be reached on an OS missing the SF Symbol, but a
            // text fallback is preferable to an invisible status item.
            button.title = "N"
            button.font = .systemFont(ofSize: 13, weight: .semibold)
        }
        button.toolTip = "SimpleMenuNote"
        button.setAccessibilityLabel("SimpleMenuNote")
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: model.popoverHeight)
        popover.contentViewController = NSHostingController(
            rootView: NoteModeView()
                .environmentObject(model)
        )
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        showPopover()
    }

    private func showPopover() {
        guard !popover.isShown, let button = statusItem?.button else { return }
        model.refreshFromExternalChanges()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        model.requestEditorFocus()
    }

    private func showStatusMenu() {
        guard let statusItem, let button = statusItem.button else { return }
        let menu = NSMenu()
        let notesItem = menu.addItem(
            withTitle: model.localized("open_management"),
            action: #selector(openNotes),
            keyEquivalent: ""
        )
        notesItem.target = self
        let settingsItem = menu.addItem(
            withTitle: model.localized("settings"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(
            withTitle: model.localized("quit_app"),
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func showManagement(section: ManagementSection) {
        popover.performClose(nil)
        model.managementSection = section
        if managementWindowController == nil {
            managementWindowController = ManagementWindowController(model: model)
        }
        NSApp.activate(ignoringOtherApps: true)
        managementWindowController?.showWindow(nil)
        managementWindowController?.window?.makeKeyAndOrderFront(nil)
        model.refreshFromExternalChanges()
    }
}

final class ManagementWindowController: NSWindowController {
    init(model: AppModel) {
        let content = ManagementView()
            .environmentObject(model)
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "SimpleMenuNote"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 920, height: 620))
        window.minSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
