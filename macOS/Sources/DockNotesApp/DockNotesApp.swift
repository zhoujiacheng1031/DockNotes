import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class DockNotesRuntime {
    static let shared = DockNotesRuntime()

    let store: NotesStore
    let settings: AppSettings
    let reminders: ReminderCoordinator
    let calendarSync: CalendarSyncCoordinator

    private init() {
        let store = NotesStore()
        let settings = AppSettings()
        self.store = store
        self.settings = settings
        reminders = ReminderCoordinator(store: store, settings: settings)
        calendarSync = CalendarSyncCoordinator(store: store, settings: settings)
    }
}

@main
struct DockNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--self-test") {
            SelfCheck.run()
        } else if CommandLine.arguments.contains("--self-test-hotkeys") {
            // The production path registers after launch. This probe must create
            // the same Carbon application event target before registering.
            NSApplication.shared.finishLaunching()
            let manager = GlobalShortcutManager()
            var callbackReceived = false
            var workspaceShortcutIndices: [Int] = []
            manager.onQuickCapture = { callbackReceived = true }
            manager.onWorkspaceShortcut = { workspaceShortcutIndices.append($0) }
            var succeeded = manager.register(shortcut: .shiftCommandSpace)
            if !succeeded, let statuses = manager.lastRegistrationStatuses {
                print("DockNotes hotkey status: quickCapture=\(statuses.quickCapture), newNote=\(statuses.newNote)")
            }
            if succeeded {
                let dispatchStatus = manager.dispatchForTesting(.quickCapture)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                succeeded = dispatchStatus == noErr && callbackReceived
                if !succeeded {
                    print("DockNotes hotkey dispatch status: \(dispatchStatus), callback=\(callbackReceived)")
                }
            }
            if succeeded {
                let firstStatus = manager.dispatchForTesting(.workspace1)
                let ninthStatus = manager.dispatchForTesting(.workspace9)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                succeeded = firstStatus == noErr
                    && ninthStatus == noErr
                    && workspaceShortcutIndices == [0, 8]
                if !succeeded {
                    print(
                        "DockNotes workspace hotkey dispatch: first=\(firstStatus), "
                            + "ninth=\(ninthStatus), indices=\(workspaceShortcutIndices)"
                    )
                }
            }
            manager.stop()
            print(succeeded ? "DockNotes global shortcut registration passed" : "DockNotes global shortcut registration failed")
            fflush(stdout)
            exit(succeeded ? EXIT_SUCCESS : EXIT_FAILURE)
        } else if CommandLine.arguments.contains("--self-test-interactions") {
            SelfCheck.runInteractionRegressions()
            print("DockNotes interaction checks passed")
            fflush(stdout)
            exit(EXIT_SUCCESS)
        } else if CommandLine.arguments.contains("--self-test-side-label-click") {
            SelfCheck.runSideLabelClickRegression()
            print("DockNotes side label click check passed")
            fflush(stdout)
            exit(EXIT_SUCCESS)
        } else if CommandLine.arguments.contains("--self-test-workspace-management") {
            SelfCheck.runWorkspaceManagementPresentationRegression()
            print("DockNotes workspace management presentation check passed")
            fflush(stdout)
            exit(EXIT_SUCCESS)
        } else if let renderIndex = CommandLine.arguments.firstIndex(of: "--render-desktop-preview"),
                  CommandLine.arguments.indices.contains(renderIndex + 1) {
            SelfCheck.renderDesktopPreview(to: URL(fileURLWithPath: CommandLine.arguments[renderIndex + 1]))
        } else if let renderIndex = CommandLine.arguments.firstIndex(of: "--render-deck-preview"),
                  CommandLine.arguments.indices.contains(renderIndex + 1) {
            let visibleTabs = CommandLine.arguments.indices.contains(renderIndex + 2)
                ? Int(CommandLine.arguments[renderIndex + 2]) ?? DeckLayout.defaultVisibleTabs
                : DeckLayout.defaultVisibleTabs
            let availableHeight = CommandLine.arguments.indices.contains(renderIndex + 3)
                ? Double(CommandLine.arguments[renderIndex + 3]).map(CGFloat.init)
                : nil
            let noteCount = CommandLine.arguments.indices.contains(renderIndex + 4)
                ? Int(CommandLine.arguments[renderIndex + 4]) ?? 11
                : 11
            SelfCheck.renderDeckPreview(
                to: URL(fileURLWithPath: CommandLine.arguments[renderIndex + 1]),
                visibleTabCount: visibleTabs,
                availableHeight: availableHeight,
                noteCount: noteCount
            )
        } else if let renderIndex = CommandLine.arguments.firstIndex(of: "--render-workspace-preview"),
                  CommandLine.arguments.indices.contains(renderIndex + 1) {
            SelfCheck.renderWorkspacePreview(to: URL(fileURLWithPath: CommandLine.arguments[renderIndex + 1]))
        } else if let renderIndex = CommandLine.arguments.firstIndex(of: "--render-workspace-management-preview"),
                  CommandLine.arguments.indices.contains(renderIndex + 1) {
            SelfCheck.renderWorkspaceManagementPreview(to: URL(fileURLWithPath: CommandLine.arguments[renderIndex + 1]))
        } else if let renderIndex = CommandLine.arguments.firstIndex(of: "--render-task-center-preview"),
                  CommandLine.arguments.indices.contains(renderIndex + 1) {
            SelfCheck.renderTaskCenterPreview(to: URL(fileURLWithPath: CommandLine.arguments[renderIndex + 1]))
        } else if let renderIndex = CommandLine.arguments.firstIndex(of: "--render-tab-hover-preview"),
                  CommandLine.arguments.indices.contains(renderIndex + 1) {
            SelfCheck.renderTabHoverPreview(to: URL(fileURLWithPath: CommandLine.arguments[renderIndex + 1]))
        } else if let renderIndex = CommandLine.arguments.firstIndex(of: "--render-ai-preview"),
                  CommandLine.arguments.indices.contains(renderIndex + 1) {
            SelfCheck.renderAIPreview(to: URL(fileURLWithPath: CommandLine.arguments[renderIndex + 1]))
        }
    }

    var body: some Scene {
        Settings {
            SettingsWindowView(
                store: DockNotesRuntime.shared.store,
                settings: DockNotesRuntime.shared.settings,
                reminders: DockNotesRuntime.shared.reminders,
                calendarSync: DockNotesRuntime.shared.calendarSync
            )
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(DockNotesRuntime.shared.settings.text(.preferences)) {
                    DockNotesRuntime.shared.store.presentSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = DockNotesRuntime.shared.store
    private let settings = DockNotesRuntime.shared.settings
    private let reminders = DockNotesRuntime.shared.reminders
    private let calendarSync = DockNotesRuntime.shared.calendarSync
    private var panelCoordinator: PanelCoordinator?
    private var statusItem: NSStatusItem?
    private let globalShortcuts = GlobalShortcutManager()
    private var shortcutCancellable: AnyCancellable?
    private var statusMenuCancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "app-icon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        UNUserNotificationCenter.current().delegate = self
        reminders.start()
        calendarSync.start()
        let coordinator = PanelCoordinator(
            store: store,
            settings: settings,
            reminders: reminders,
            calendarSync: calendarSync
        )
        panelCoordinator = coordinator
        coordinator.start()
        installGlobalShortcuts()
        installStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flushPendingSave()
        store.finalizeAllPendingDeletions()
        globalShortcuts.stop()
        shortcutCancellable = nil
        statusMenuCancellables.removeAll()
        reminders.stop()
        calendarSync.stop()
        panelCoordinator?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store.presentLibrary()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        reminders.syncNow()
        calendarSync.syncNow()
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
        item.menu = makeStatusMenu()
        statusItem = item
        panelCoordinator?.statusItemButton = item.button
        store.$workspaces
            .combineLatest(store.$activeWorkspaceID)
            .dropFirst()
            .sink { [weak self] _, _ in self?.refreshStatusMenu() }
            .store(in: &statusMenuCancellables)
        settings.$language
            .dropFirst()
            .sink { [weak self] _ in self?.refreshStatusMenu() }
            .store(in: &statusMenuCancellables)
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let workspaceRoot = NSMenuItem(
            title: "\(settings.text(.workspaces)): \(store.activeWorkspace.name)",
            action: nil,
            keyEquivalent: ""
        )
        let workspaceMenu = NSMenu(title: settings.text(.workspaces))
        for (index, workspace) in store.workspaces.enumerated() {
            let item = NSMenuItem(
                title: workspace.name,
                action: #selector(switchWorkspaceFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = workspace.id.uuidString
            item.state = workspace.id == store.activeWorkspaceID ? .on : .off
            if index < 9 {
                item.keyEquivalent = "\(index + 1)"
                item.keyEquivalentModifierMask = [.command, .option]
            }
            workspaceMenu.addItem(item)
        }
        workspaceRoot.submenu = workspaceMenu
        menu.addItem(workspaceRoot)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: settings.text(.library), action: #selector(showLibrary), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: settings.text(.taskCenter), action: #selector(showTaskCenter), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: settings.text(.newNote), action: #selector(createNote), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: settings.text(.quickCapture), action: #selector(showQuickCapture), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: settings.text(.preferences), action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit DockNotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        menu.items.dropLast().forEach { $0.target = self }
        return menu
    }

    private func refreshStatusMenu() {
        statusItem?.menu = makeStatusMenu()
    }

    @objc private func showLibrary() { store.presentLibrary() }
    @objc private func showTaskCenter() { store.presentTaskCenter() }
    @objc private func createNote() { store.addNote(language: settings.language) }
    @objc private func showQuickCapture() { store.presentQuickCapture() }
    @objc private func showPreferences() { store.presentSettings() }
    @objc private func switchWorkspaceFromMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let id = UUID(uuidString: value) else { return }
        store.switchWorkspace(to: id)
    }

    private func installGlobalShortcuts() {
        globalShortcuts.onQuickCapture = { [weak self] in
            Task { @MainActor in self?.store.presentQuickCapture() }
        }
        globalShortcuts.onNewNote = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.store.addNote(language: self.settings.language)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        globalShortcuts.onWorkspaceShortcut = { [weak self] index in
            Task { @MainActor in
                guard let self, self.store.workspaces.indices.contains(index) else { return }
                self.store.switchWorkspace(to: self.store.workspaces[index].id)
            }
        }
        settings.reportQuickCaptureShortcutRegistration(
            globalShortcuts.register(shortcut: settings.quickCaptureShortcut)
        )
        shortcutCancellable = settings.$quickCaptureShortcut
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] shortcut in
                guard let self else { return }
                self.settings.reportQuickCaptureShortcutRegistration(
                    self.globalShortcuts.register(shortcut: shortcut)
                )
            }
    }
}

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String, let value = pair.value as? String else { return }
            result[key] = value
        }
        reminders.handle(actionIdentifier: actionIdentifier, userInfo: userInfo)
        completionHandler()
    }
}
