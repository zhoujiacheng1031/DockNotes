import AppKit
import SwiftUI

@main
struct DockNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--self-test") {
            SelfCheck.run()
        } else if let renderIndex = CommandLine.arguments.firstIndex(of: "--render-deck-preview"),
                  CommandLine.arguments.indices.contains(renderIndex + 1) {
            SelfCheck.renderDeckPreview(to: URL(fileURLWithPath: CommandLine.arguments[renderIndex + 1]))
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NotesStore()
    private let settings = AppSettings()
    private var panelCoordinator: PanelCoordinator?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "app-icon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        let coordinator = PanelCoordinator(store: store, settings: settings)
        panelCoordinator = coordinator
        coordinator.start()
        installStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelCoordinator?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store.presentLibrary()
        return true
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let trayURL = Bundle.main.url(forResource: "tray-icon", withExtension: "png"),
           let trayIcon = NSImage(contentsOf: trayURL) {
            // The custom three-tab mark is intentionally drawn edge-to-edge;
            // 19 pt keeps it optically balanced with Apple's heavier status icons.
            trayIcon.size = NSSize(width: 19, height: 19)
            trayIcon.isTemplate = true
            item.button?.image = trayIcon
        } else {
            item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "DockNotes")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: settings.text(.library), action: #selector(showLibrary), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: settings.text(.newNote), action: #selector(createNote), keyEquivalent: "n"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: settings.text(.preferences), action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit DockNotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        menu.items.dropLast().forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func showLibrary() { store.presentLibrary() }
    @objc private func createNote() { store.addNote(language: settings.language) }
    @objc private func showPreferences() { store.presentSettings() }
}
