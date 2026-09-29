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
    static let desktopWindowStyleMask: NSWindow.StyleMask = [.borderless, .resizable]
    static let desktopWindowInitialSize = CGSize(width: 460, height: 380)
    static let desktopWindowMinimumSize = CGSize(width: 320, height: 260)
    static let desktopWindowMaximumSize = CGSize(width: 900, height: 720)
    static let transparentWindowGlassMode: DockNotesGlassRenderingMode = .stableMaterial

    static func workspaceManagementContentSize(for visibleFrame: NSRect) -> CGSize {
        CGSize(
            width: min(600, max(1, visibleFrame.width - 32)),
            height: min(480, max(1, visibleFrame.height - 64))
        )
    }

    static func workspaceManagementFrame(in visibleFrame: NSRect, windowSize: CGSize) -> NSRect {
        NSRect(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )
    }

    static func desktopWindowLevel(isPinned: Bool) -> NSWindow.Level {
        isPinned ? .floating : .normal
    }

    static func localClickIsOutsideApp(
        hasWindow: Bool,
        point: NSPoint? = nil,
        appWindowFrames: [NSRect] = []
    ) -> Bool {
        if hasWindow { return false }
        guard let point else { return true }
        return !appWindowFrames.contains { $0.contains(point) }
    }

    private enum Metrics {
        static let noteSize = CGSize(width: 460, height: 380)
        static let deckWidth: CGFloat = DeckLayout.windowWidth
        static let visibleDeckWidth: CGFloat = DeckLayout.windowWidth
        static let noteDeckGap: CGFloat = DeckLayout.windowWidth
        static let settingsSize = CGSize(width: 760, height: 560)
        static let librarySize = CGSize(width: 860, height: 560)
        static let taskCenterSize = CGSize(width: 860, height: 560)
        static let undoSize = CGSize(width: 356, height: 62)
        static let quickCaptureSize = CGSize(width: 420, height: 245)
    }

    private let store: NotesStore
    private let settings: AppSettings
    private let reminders: ReminderCoordinator
    private let calendarSync: CalendarSyncCoordinator
    private let visibleFrameOverride: NSRect?
    private var notePanel: TransparentPanel?
    private var deckPanel: TransparentPanel?
    private var settingsWindow: NSWindow?
    private var libraryWindow: NSWindow?
    private var workspaceManagementWindow: NSWindow?
    private var taskCenterWindow: NSWindow?
    private var undoPanel: TransparentPanel?
    private var quickCaptureWindow: NSWindow?
    weak var statusItemButton: NSButton?
    private var desktopNoteWindows: [DockNote.ID: NSWindow] = [:]
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var workspaceActivationObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var liveResizingDesktopWindows = Set<ObjectIdentifier>()

    var edgePanelFrameForTesting: NSRect? { deckPanel?.frame }
    var edgePanelContentViewForTesting: NSView? { deckPanel?.contentView }
    var settingsWindowForTesting: NSWindow? { settingsWindow }
    var libraryWindowForTesting: NSWindow? { libraryWindow }
    var taskCenterWindowForTesting: NSWindow? { taskCenterWindow }
    private(set) var edgeInteractionRefreshMatchesCommittedEdgeForTesting = true

    init(
        store: NotesStore,
        settings: AppSettings,
        reminders: ReminderCoordinator? = nil,
        calendarSync: CalendarSyncCoordinator? = nil,
        visibleFrameOverride: NSRect? = nil
    ) {
        self.store = store
        self.settings = settings
        self.reminders = reminders ?? ReminderCoordinator(store: store, settings: settings)
        self.calendarSync = calendarSync ?? CalendarSyncCoordinator(store: store, settings: settings)
        self.visibleFrameOverride = visibleFrameOverride
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
        workspaceManagementWindow?.orderOut(nil)
        taskCenterWindow?.orderOut(nil)
        undoPanel?.orderOut(nil)
        quickCaptureWindow?.orderOut(nil)
        deckPanel?.orderFrontRegardless()
        if store.isExpanded { showNotePanel(animated: false) }
        if store.isPreferencesPresented { showSettingsWindow() }
        if store.isLibraryPresented { showLibraryWindow() }
        if store.isWorkspaceManagementPresented { showWorkspaceManagementWindow() }
        if store.isTaskCenterPresented { showTaskCenterWindow() }
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
        undoPanel?.orderOut(nil)
        workspaceManagementWindow?.orderOut(nil)
        quickCaptureWindow?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            store.isPreferencesPresented = false
        } else if let window = notification.object as? NSWindow, window === libraryWindow {
            store.isLibraryPresented = false
        } else if let window = notification.object as? NSWindow, window === workspaceManagementWindow {
            store.isWorkspaceManagementPresented = false
        } else if let window = notification.object as? NSWindow, window === taskCenterWindow {
            store.isTaskCenterPresented = false
        } else if let window = notification.object as? NSWindow, window === quickCaptureWindow {
            store.isQuickCapturePresented = false
        } else if let window = notification.object as? NSWindow,
                  let pair = desktopNoteWindows.first(where: { $0.value === window }) {
            desktopNoteWindows.removeValue(forKey: pair.key)
            store.closeDesktopNote(pair.key)
        }
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard let window = notification.object as? DesktopNoteWindow else { return }
        liveResizingDesktopWindows.insert(ObjectIdentifier(window))
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? DesktopNoteWindow else { return }
        liveResizingDesktopWindows.remove(ObjectIdentifier(window))
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let desktopWindow = sender as? DesktopNoteWindow else { return frameSize }
        let isUserResize = desktopWindow.inLiveResize
            || liveResizingDesktopWindows.contains(ObjectIdentifier(desktopWindow))
        guard isUserResize || desktopWindow.permitsExplicitResize else {
            // NSHostingView may asynchronously push its fitting/minimum size
            // back into the window after presentation. It must not override
            // the explicit native window frame.
            return desktopWindow.frame.size
        }
        return NSSize(
            width: min(max(frameSize.width, Self.desktopWindowMinimumSize.width), Self.desktopWindowMaximumSize.width),
            height: min(max(frameSize.height, Self.desktopWindowMinimumSize.height), Self.desktopWindowMaximumSize.height)
        )
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
        workspaceManagementWindow = makeWorkspaceManagementWindow()
        taskCenterWindow = makeTaskCenterWindow()
        undoPanel = makeTransparentPanel(
            size: Metrics.undoSize,
            content: UndoDeletionBanner(store: store, settings: settings)
        )
        undoPanel?.level = NSWindow.Level(rawValue: Self.deckWindowLevel.rawValue + 1)
        quickCaptureWindow = makeQuickCaptureWindow()
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

        store.$isWorkspaceManagementPresented
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] presented in
                guard let self else { return }
                presented ? self.showWorkspaceManagementWindow() : self.workspaceManagementWindow?.orderOut(nil)
            }
            .store(in: &cancellables)

        store.$isTaskCenterPresented
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] presented in
                guard let self else { return }
                presented ? self.showTaskCenterWindow() : self.taskCenterWindow?.orderOut(nil)
            }
            .store(in: &cancellables)

        store.utilityWindowRequests
            .sink { [weak self] request in
                guard let self else { return }
                switch request {
                case .settings: self.showSettingsWindow()
                case .library: self.showLibraryWindow()
                case .taskCenter: self.showTaskCenterWindow()
                }
            }
            .store(in: &cancellables)

        store.$isQuickCapturePresented
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] presented in
                guard let self else { return }
                if presented {
                    self.showQuickCaptureWindow()
                } else {
                    self.quickCaptureWindow?.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        store.$desktopNoteIDs
            .removeDuplicates()
            .sink { [weak self] ids in self?.syncDesktopNoteWindows(with: ids) }
            .store(in: &cancellables)

        store.$pendingDeletions
            .map { !$0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] presented in
                guard let self else { return }
                if presented {
                    self.positionUndoPanel()
                    self.undoPanel?.orderFrontRegardless()
                } else {
                    self.undoPanel?.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        store.$notes
            .sink { [weak self] notes in
                self?.syncDesktopNoteWindowAttributes(with: notes)
            }
            .store(in: &cancellables)

        settings.$language
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.settingsWindow?.title = self.settings.text(.preferences)
                self.libraryWindow?.title = self.settings.text(.library)
                self.workspaceManagementWindow?.title = self.settings.text(.manageWorkspaces)
                self.taskCenterWindow?.title = self.settings.text(.taskCenter)
                self.quickCaptureWindow?.title = self.settings.text(.quickCapture)
            }
            .store(in: &cancellables)

        settings.$deckEdge
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] edge in
                // @Published emits from willSet. Use the emitted edge directly;
                // reading settings.deckEdge here would still return the old side
                // until the assignment completes, leaving the panel in place
                // until an unrelated click triggers another positioning pass.
                guard let self else { return }
                self.positionEdgeWindows(edge: edge, refreshInteractions: false)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.settings.deckEdge == edge else { return }
                    self.refreshEdgeInteractions(expectedEdge: edge)
                }
            }
            .store(in: &cancellables)
    }

    private func makeSettingsWindow() -> NSWindow {
        let hostingView = NSHostingView(rootView: SettingsWindowView(
            store: store,
            settings: settings,
            reminders: reminders,
            calendarSync: calendarSync
        ))
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
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        if let titlebar = window.standardWindowButton(.closeButton)?.superview {
            let dragHandle = SettingsTitlebarDragView(frame: NSRect(
                x: 84,
                y: 0,
                width: max(0, titlebar.bounds.width - 96),
                height: titlebar.bounds.height
            ))
            dragHandle.autoresizingMask = [.width, .height]
            titlebar.addSubview(dragHandle, positioned: .above, relativeTo: nil)
        }
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

    private func makeWorkspaceManagementWindow() -> NSWindow {
        let visible = visibleFrameOverride ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = Self.workspaceManagementContentSize(for: visible)
        let hostingView = NSHostingView(rootView: WorkspaceManagementView(
            store: store,
            settings: settings,
            size: size,
            onClose: { [weak self] in self?.store.isWorkspaceManagementPresented = false }
        ))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = settings.text(.manageWorkspaces)
        window.contentView = hostingView
        window.level = NSWindow.Level(rawValue: Self.deckWindowLevel.rawValue + 1)
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        return window
    }

    private func makeTaskCenterWindow() -> NSWindow {
        let hostingView = NSHostingView(rootView: TaskCenterView(store: store, settings: settings))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Metrics.taskCenterSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = settings.text(.taskCenter)
        window.contentView = hostingView
        window.level = .normal
        window.minSize = Metrics.taskCenterSize
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.center()
        return window
    }

    private func makeQuickCaptureWindow() -> NSWindow {
        let hostingView = NSHostingView(rootView: QuickCaptureView(store: store, settings: settings))
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.quickCaptureSize),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = settings.text(.quickCapture)
        window.contentView = hostingView
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.center()
        return window
    }

    func makeDesktopNoteWindow(for noteID: DockNote.ID) -> NSWindow {
        let hostingView = TransparentHostingView(
            rootView: DesktopNoteWindowView(noteID: noteID, store: store, settings: settings)
                .environment(\.dockNotesGlassRenderingMode, Self.transparentWindowGlassMode)
        )
        hostingView.sizingOptions = []
        let size = Self.desktopWindowInitialSize
        let containerView = NSView(frame: NSRect(origin: .zero, size: size))
        containerView.autoresizesSubviews = true
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        // The transparent window can still expose the hosting view's square
        // material and shadow pixels. Clip the actual AppKit content layer to
        // the same shape as the note card, including during live resize.
        containerView.layer?.cornerRadius = DockNotesGlassMetrics.panelRadius
        containerView.layer?.cornerCurve = .continuous
        containerView.layer?.masksToBounds = true
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingView)
        let window = DesktopNoteWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: Self.desktopWindowStyleMask,
            backing: .buffered,
            defer: false
        )
        window.title = store.note(id: noteID)?.title ?? "DockNotes"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        // Keep SwiftUI's intrinsic/fitting size out of the native live-resize
        // negotiation. The neutral AppKit container owns the window bounds;
        // the hosting view only follows those bounds.
        window.contentView = containerView
        window.minSize = Self.desktopWindowMinimumSize
        window.maxSize = Self.desktopWindowMaximumSize
        window.level = Self.desktopWindowLevel(isPinned: store.note(id: noteID)?.isPinned == true)
        window.isOpaque = false
        window.backgroundColor = .clear
        // AppKit's window shadow uses the rectangular frame and shows through
        // the transparent corners of the rounded content.
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        // With a full-content titlebar, treating the entire note as a drag
        // surface competes with AppKit's resize hit regions at the edges.
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.resizeIncrements = NSSize(width: 1, height: 1)
        window.preservesContentDuringLiveResize = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        // Assigning an NSHostingView can let its fitting size replace the
        // requested window size. Reassert the product default only after all
        // hosting and AppKit constraints have been installed.
        window.setFrame(NSRect(origin: window.frame.origin, size: size), display: false)
        window.center()
        window.setFrameOrigin(NSPoint(x: window.frame.origin.x - CGFloat(desktopNoteWindows.count * 24), y: window.frame.origin.y - CGFloat(desktopNoteWindows.count * 24)))
        window.preventImplicitResizing()
        return window
    }

    private func syncDesktopNoteWindows(with ids: [DockNote.ID]) {
        let requested = Set(ids)
        let removedIDs = desktopNoteWindows.keys.filter { !requested.contains($0) }
        for id in removedIDs {
            desktopNoteWindows[id]?.orderOut(nil)
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

    private func syncDesktopNoteWindowAttributes(with notes: [DockNote]) {
        let notesByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        for (id, window) in desktopNoteWindows {
            guard let note = notesByID[id] else { continue }
            window.title = note.title.isEmpty ? "DockNotes" : note.title
            window.level = Self.desktopWindowLevel(isPinned: note.isPinned)
            if note.isPinned {
                window.orderFrontRegardless()
            }
        }
    }

    private func makeTransparentPanel<Content: View>(size: CGSize, content: Content) -> TransparentPanel {
        // Liquid Glass's animated backdrop can leave rectangular copies when
        // these borderless, transparent panels move or change opacity. Keep the
        // same tinted glass design using the stable material renderer here.
        let hostingView = TransparentHostingView(
            rootView: content.environment(\.dockNotesGlassRenderingMode, Self.transparentWindowGlassMode)
        )
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
        panel.acceptsMouseMovedEvents = true
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

    private func positionEdgeWindows(
        edge requestedEdge: DeckEdge? = nil,
        refreshInteractions: Bool = true
    ) {
        let visible: NSRect
        if let visibleFrameOverride {
            visible = visibleFrameOverride
        } else {
            guard let screen = deckPanel?.screen ?? NSScreen.main else { return }
            visible = screen.visibleFrame
        }
        let edge = requestedEdge ?? settings.deckEdge
        let deckSize = deckPanel?.frame.size ?? CGSize(width: Metrics.deckWidth, height: 520)
        let deckX: CGFloat
        let noteX: CGFloat
        if edge == .right {
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
        if refreshInteractions {
            refreshEdgeInteractions(expectedEdge: edge)
        }
        positionUndoPanel(in: visible)
    }

    private func positionUndoPanel(in suppliedVisibleFrame: NSRect? = nil) {
        guard let panel = undoPanel else { return }
        let visible = suppliedVisibleFrame
            ?? visibleFrameOverride
            ?? deckPanel?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        guard let visible else { return }
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + 24
        ))
    }

    private func refreshEdgeInteractions(expectedEdge: DeckEdge) {
        edgeInteractionRefreshMatchesCommittedEdgeForTesting = settings.deckEdge == expectedEdge
        deckPanel?.contentView?.needsLayout = true
        deckPanel?.contentView?.layoutSubtreeIfNeeded()
        if let contentView = deckPanel?.contentView {
            refreshTrackingAreas(in: contentView)
        }
        deckPanel?.displayIfNeeded()

        guard store.deckState == .resting, let panel = deckPanel else { return }
        let activationRect: NSRect
        if expectedEdge == .right {
            activationRect = NSRect(
                x: panel.frame.maxX - DeckLayout.restingActivationWidth,
                y: panel.frame.minY,
                width: DeckLayout.restingActivationWidth,
                height: panel.frame.height
            )
        } else {
            activationRect = NSRect(
                x: panel.frame.minX,
                y: panel.frame.minY,
                width: DeckLayout.restingActivationWidth,
                height: panel.frame.height
            )
        }
        if activationRect.contains(NSEvent.mouseLocation) {
            store.pointerEnteredDeck()
        }
    }

    private func refreshTrackingAreas(in view: NSView) {
        view.updateTrackingAreas()
        for subview in view.subviews {
            refreshTrackingAreas(in: subview)
        }
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

    private func showWorkspaceManagementWindow() {
        guard let window = workspaceManagementWindow else { return }
        let visible = visibleFrameOverride ?? deckPanel?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = Self.workspaceManagementContentSize(for: visible)
        if let hostingView = window.contentView as? NSHostingView<WorkspaceManagementView> {
            hostingView.rootView = WorkspaceManagementView(
                store: store,
                settings: settings,
                size: size,
                onClose: { [weak self] in self?.store.isWorkspaceManagementPresented = false }
            )
        }
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        window.setFrame(Self.workspaceManagementFrame(in: visible, windowSize: frameSize), display: true)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
    }

    private func showTaskCenterWindow() {
        guard let window = taskCenterWindow else { return }
        window.center()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
    }

    private func showQuickCaptureWindow() {
        guard let window = quickCaptureWindow else { return }
        window.center()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
    }

    private func installOutsideClickMonitors() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp]
        ) { [weak self] event in
            if event.type == .leftMouseUp {
                NotificationCenter.default.post(name: .dockNotesPointerReleased, object: event)
            } else {
                self?.handleLocalPointerDown(event)
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp]
        ) { [weak self] event in
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                if event.type == .leftMouseUp {
                    NotificationCenter.default.post(name: .dockNotesPointerReleased, object: nil)
                } else {
                    self?.handlePointerDown(at: point)
                }
            }
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
                self?.handlePointerDown(at: NSEvent.mouseLocation)
            }
        }
    }

    private func handleLocalPointerDown(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        // Keep independent utility windows visible while interacting with
        // DockNotes controls, including the edge deck and status menu.
        if Self.localClickIsOutsideApp(
            hasWindow: event.window != nil,
            point: point,
            appWindowFrames: visibleAppWindowFrames
        ) {
            store.handleOutsideClick(keepDeckOpen: settings.keepDeckOpen)
        }
    }

    private var visibleAppWindowFrames: [NSRect] {
        var frames: [NSRect] = []
        for window in [settingsWindow, libraryWindow, workspaceManagementWindow, taskCenterWindow, quickCaptureWindow, notePanel, deckPanel, undoPanel] {
            if let window, window.isVisible { frames.append(window.frame) }
        }
        for window in desktopNoteWindows.values where window.isVisible {
            frames.append(window.frame)
        }
        if let statusWindow = statusItemButton?.window, statusWindow.isVisible {
            frames.append(statusWindow.frame)
        }
        return frames
    }

    private func handlePointerDown(at point: NSPoint) {
        guard Self.localClickIsOutsideApp(
            hasWindow: false,
            point: point,
            appWindowFrames: visibleAppWindowFrames
        ) else { return }
        store.handleOutsideClick(keepDeckOpen: settings.keepDeckOpen)
    }
}

private final class TransparentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SettingsTitlebarDragView: NSView {
    private var startingOrigin: NSPoint?
    private var startingPointer: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startingOrigin = window.frame.origin
        startingPointer = window.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let startingOrigin, let startingPointer else { return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(NSPoint(
            x: startingOrigin.x + pointer.x - startingPointer.x,
            y: startingOrigin.y + pointer.y - startingPointer.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        startingOrigin = nil
        startingPointer = nil
    }
}

final class DesktopNoteWindow: NSWindow {
    private(set) var permitsExplicitResize = false
    private var rejectsImplicitResize = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func preventImplicitResizing() {
        rejectsImplicitResize = true
    }

    func setExplicitFrame(_ frame: NSRect, display: Bool) {
        permitsExplicitResize = true
        setFrame(frame, display: display)
        permitsExplicitResize = false
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard rejectsImplicitResize,
              !inLiveResize,
              !permitsExplicitResize,
              frameRect.size != frame.size else {
            super.setFrame(frameRect, display: flag)
            return
        }
        // A nested NSHostingView can repeatedly write its minimum fitting
        // height through this method after the window is already visible.
        // Preserve the current user/native size while still allowing moves.
        super.setFrame(NSRect(origin: frameRect.origin, size: frame.size), display: flag)
    }

    override func setContentSize(_ size: NSSize) {
        guard !rejectsImplicitResize || inLiveResize || permitsExplicitResize else { return }
        super.setContentSize(size)
    }
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
