import AppKit
import Combine
import SwiftUI

/// Owns presentation only. Note data and user intent remain in `NotesStore`.
/// Keeping these boundaries separate prevents opening Settings from implicitly
/// changing the active note or the deck's slot order.
@MainActor
final class PanelCoordinator: NSObject, NSWindowDelegate {
    static let noteWindowLevel = NSWindow.Level.floating
    static let deckWindowLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

    static func localClickIsOutsideApp(hasWindow: Bool) -> Bool {
        !hasWindow
    }

    private enum Metrics {
        static let noteSize = CGSize(width: 460, height: 380)
        static let deckWidth: CGFloat = DeckLayout.windowWidth
        static let visibleDeckWidth: CGFloat = DeckLayout.windowWidth
        static let noteDeckGap: CGFloat = DeckLayout.windowWidth
        static let settingsSize = CGSize(width: 620, height: 470)
        static let librarySize = CGSize(width: 680, height: 520)
    }

    private let store: NotesStore
    private let settings: AppSettings
    private var notePanel: TransparentPanel?
    private var deckPanel: TransparentPanel?
    private var settingsWindow: NSWindow?
    private var libraryWindow: NSWindow?
    private var desktopNoteWindows: [DockNote.ID: NSWindow] = [:]
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var workspaceActivationObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    init(store: NotesStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    func start() {
        createWindows()
        observePresentation()
        installOutsideClickMonitors()
        installApplicationActivationFallback()
        positionEdgeWindows()

        // Initial visibility must be state-driven. Ordering the note panel here
        // unconditionally was the cause of Settings appearing with a note.
        notePanel?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        libraryWindow?.orderOut(nil)
        deckPanel?.orderFrontRegardless()
        if store.isExpanded { showNotePanel(animated: false) }
        if store.isPreferencesPresented { showSettingsWindow() }
        if store.isLibraryPresented { showLibraryWindow() }
    }

    func stop() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
        localMouseMonitor = nil
        globalMouseMonitor = nil
        workspaceActivationObserver = nil
        cancellables.removeAll()
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            store.isPreferencesPresented = false
        } else if let window = notification.object as? NSWindow, window === libraryWindow {
            store.isLibraryPresented = false
        } else if let window = notification.object as? NSWindow,
                  let pair = desktopNoteWindows.first(where: { $0.value === window }) {
            desktopNoteWindows.removeValue(forKey: pair.key)
            store.closeDesktopNote(pair.key)
        }
    }

    private func createWindows() {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 800
        let deckHeight = min(max(640, visibleHeight - 20), 1_040)

        notePanel = makeTransparentPanel(
            size: Metrics.noteSize,
            content: NoteWindowView(store: store, settings: settings)
        )
        deckPanel = makeTransparentPanel(
            size: CGSize(width: Metrics.deckWidth, height: deckHeight),
            content: DeckWindowView(store: store, settings: settings, availableHeight: deckHeight)
        )
        deckPanel?.level = Self.deckWindowLevel
        notePanel?.level = Self.noteWindowLevel
        settingsWindow = makeSettingsWindow()
        libraryWindow = makeLibraryWindow()
    }

    private func observePresentation() {
        store.$deckState
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                self.positionEdgeWindows()
                if state.openNoteID != nil {
                    // The deck stays behind the full note. Ordering it last made
                    // unopened tabs cover the note and intercept its controls.
                    self.deckPanel?.orderFrontRegardless()
                    if self.notePanel?.isVisible != true {
                        self.showNotePanel(animated: true)
                    } else {
                        self.notePanel?.orderFrontRegardless()
                    }
                } else if self.notePanel?.isVisible == true {
                    self.hideNotePanel(animated: true)
                    self.deckPanel?.orderFrontRegardless()
                } else {
                    self.deckPanel?.orderFrontRegardless()
                }
            }
            .store(in: &cancellables)

        store.$isPreferencesPresented
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] presented in
                guard let self else { return }
                presented ? self.showSettingsWindow() : self.settingsWindow?.orderOut(nil)
            }
            .store(in: &cancellables)

        store.$isLibraryPresented
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] presented in
                guard let self else { return }
                presented ? self.showLibraryWindow() : self.libraryWindow?.orderOut(nil)
            }
            .store(in: &cancellables)

        store.$desktopNoteIDs
            .removeDuplicates()
            .sink { [weak self] ids in self?.syncDesktopNoteWindows(with: ids) }
            .store(in: &cancellables)

        settings.$language
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.settingsWindow?.title = self.settings.text(.preferences)
                self.libraryWindow?.title = self.settings.text(.library)
            }
            .store(in: &cancellables)

        settings.$deckEdge
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.positionEdgeWindows() }
            .store(in: &cancellables)
    }

    private func makeSettingsWindow() -> NSWindow {
        let hostingView = NSHostingView(rootView: SettingsWindowView(store: store, settings: settings))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Metrics.settingsSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = settings.text(.preferences)
        window.contentView = hostingView
        window.level = .normal
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.center()
        return window
    }

    private func makeLibraryWindow() -> NSWindow {
        let hostingView = NSHostingView(rootView: NotesLibraryView(store: store, settings: settings))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Metrics.librarySize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = settings.text(.library)
        window.contentView = hostingView
        window.level = .normal
        window.minSize = Metrics.librarySize
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.center()
        return window
    }

    private func makeDesktopNoteWindow(for noteID: DockNote.ID) -> NSWindow {
        let hostingView = NSHostingView(rootView: DesktopNoteWindowView(noteID: noteID, store: store, settings: settings))
        let size = CGSize(width: 460, height: 380)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = store.note(id: noteID)?.title ?? "DockNotes"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = hostingView
        window.minSize = size
        window.maxSize = size
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.center()
        window.setFrameOrigin(NSPoint(x: window.frame.origin.x - CGFloat(desktopNoteWindows.count * 24), y: window.frame.origin.y - CGFloat(desktopNoteWindows.count * 24)))
        return window
    }

    private func syncDesktopNoteWindows(with ids: [DockNote.ID]) {
        let requested = Set(ids)
        for (id, window) in desktopNoteWindows where !requested.contains(id) {
            window.orderOut(nil)
            desktopNoteWindows.removeValue(forKey: id)
        }
        for id in ids where desktopNoteWindows[id] == nil {
            let window = makeDesktopNoteWindow(for: id)
            desktopNoteWindows[id] = window
            window.orderFrontRegardless()
            window.makeKey()
        }
        if !ids.isEmpty { NSApp.activate(ignoringOtherApps: true) }
    }

    private func makeTransparentPanel<Content: View>(size: CGSize, content: Content) -> TransparentPanel {
        let hostingView = TransparentHostingView(rootView: content)
        let panel = TransparentPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = NSRect(origin: .zero, size: size)
        return panel
    }

    private func positionEdgeWindows() {
        guard let screen = deckPanel?.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let deckSize = deckPanel?.frame.size ?? CGSize(width: Metrics.deckWidth, height: 520)
        let deckX: CGFloat
        let noteX: CGFloat
        if settings.deckEdge == .right {
            deckX = visible.maxX - Metrics.visibleDeckWidth
            noteX = deckX - Metrics.noteDeckGap - Metrics.noteSize.width
        } else {
            deckX = visible.minX
            noteX = deckX + Metrics.visibleDeckWidth + Metrics.noteDeckGap
        }
        deckPanel?.setFrame(
            NSRect(x: deckX, y: visible.midY - deckSize.height / 2, width: deckSize.width, height: deckSize.height),
            display: true
        )
        notePanel?.setFrame(
            NSRect(x: noteX, y: visible.midY - Metrics.noteSize.height / 2, width: Metrics.noteSize.width, height: Metrics.noteSize.height),
            display: true
        )
    }

    private func showNotePanel(animated: Bool) {
        guard let panel = notePanel else { return }
        let target = panel.frame
        guard animated else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        var start = target
        start.origin.x += settings.deckEdge == .right ? 18 : -18
        panel.alphaValue = 0
        panel.setFrame(start, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    private func hideNotePanel(animated: Bool) {
        guard let panel = notePanel, panel.isVisible else { return }
        let target = panel.frame
        guard animated else {
            panel.orderOut(nil)
            return
        }
        var end = target
        end.origin.x += settings.deckEdge == .right ? 18 : -18
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(end, display: true)
        } completionHandler: { [weak panel] in
            Task { @MainActor in
                panel?.orderOut(nil)
                panel?.alphaValue = 1
                panel?.setFrame(target, display: false)
            }
        }
    }

    private func showSettingsWindow() {
        guard let window = settingsWindow else { return }
        window.center()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
    }

    private func showLibraryWindow() {
        guard let window = libraryWindow else { return }
        window.center()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
    }

    private func installOutsideClickMonitors() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleLocalPointerDown(event)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.handlePointerDown(at: NSEvent.mouseLocation) }
        }
    }

    private func installApplicationActivationFallback() {
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor in
                self?.store.handleOutsideClick(keepDeckOpen: self?.settings.keepDeckOpen ?? true)
            }
        }
    }

    private func handleLocalPointerDown(_ event: NSEvent) {
        guard !Self.localClickIsOutsideApp(hasWindow: event.window != nil), let window = event.window else {
            store.handleOutsideClick(keepDeckOpen: settings.keepDeckOpen)
            return
        }
        if window === settingsWindow || window === libraryWindow { return }

        // Local events already belong to DockNotes. This includes SwiftUI's
        // separate popover window used by More Notes, so it must not be treated
        // as an outside click before the row button receives the same event.
        if store.isPreferencesPresented { store.isPreferencesPresented = false }
    }

    private func handlePointerDown(at point: NSPoint) {
        if settingsWindow?.isVisible == true, settingsWindow?.frame.contains(point) == true { return }
        if libraryWindow?.isVisible == true, libraryWindow?.frame.contains(point) == true { return }
        if notePanel?.isVisible == true, notePanel?.frame.contains(point) == true { return }
        if deckPanel?.isVisible == true, deckPanel?.frame.contains(point) == true { return }
        store.handleOutsideClick(keepDeckOpen: settings.keepDeckOpen)
    }
}

private final class TransparentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }
}
