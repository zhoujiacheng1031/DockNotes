import AppKit
import SwiftUI

enum TabPointerEvent: Equatable {
    case dragChanged(CGFloat)
    case dragEnded(CGFloat)
    case clicked
}

struct TabPointerDragSession {
    private(set) var initialScreenY: CGFloat?
    private(set) var isDragging = false
    private var maximumDistance: CGFloat = 0
    let minimumDistance: CGFloat
    let clickTolerance: CGFloat

    init(minimumDistance: CGFloat = 1, clickTolerance: CGFloat = 6) {
        self.minimumDistance = minimumDistance
        self.clickTolerance = clickTolerance
    }

    mutating func mouseDown(screenY: CGFloat) {
        initialScreenY = screenY
        isDragging = false
        maximumDistance = 0
    }

    mutating func mouseDragged(screenY: CGFloat) -> TabPointerEvent? {
        guard let initialScreenY else { return nil }
        let translation = initialScreenY - screenY
        maximumDistance = max(maximumDistance, abs(translation))
        guard isDragging || abs(translation) >= minimumDistance else { return nil }
        isDragging = true
        return .dragChanged(translation)
    }

    mutating func mouseUp(screenY: CGFloat) -> TabPointerEvent? {
        defer {
            initialScreenY = nil
            isDragging = false
            maximumDistance = 0
        }
        guard let initialScreenY else { return nil }
        let translation = initialScreenY - screenY
        maximumDistance = max(maximumDistance, abs(translation))
        return maximumDistance < clickTolerance ? .clicked : .dragEnded(translation)
    }

    mutating func cancel() {
        initialScreenY = nil
        isDragging = false
        maximumDistance = 0
    }
}

struct TabPointerDragSurface: NSViewRepresentable {
    let preview: AnyView
    let edge: DeckEdge
    let previewsEnabled: Bool
    let onTrackingChanged: (Bool, Bool) -> Void
    let onClick: () -> Void
    let contextMenuTitle: String
    let contextMenuItems: [TabPointerContextMenuItem]
    let onContextMenuItem: (UUID) -> Void
    let onDragChanged: (CGFloat, CGPoint) -> Void
    let onDragEnded: (CGFloat, CGPoint) -> Void
    let onDragCancelled: () -> Void

    func makeNSView(context: Context) -> TabPointerTrackingView {
        let view = TabPointerTrackingView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: TabPointerTrackingView, context: Context) {
        update(nsView)
    }

    private func update(_ view: TabPointerTrackingView) {
        view.preview = preview
        view.edge = edge
        view.previewsEnabled = previewsEnabled
        view.onTrackingChanged = onTrackingChanged
        view.onClick = onClick
        view.contextMenuTitle = contextMenuTitle
        view.contextMenuItems = contextMenuItems
        view.onContextMenuItem = onContextMenuItem
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onDragCancelled = onDragCancelled
    }
}

struct TabPointerContextMenuItem: Equatable {
    let id: UUID
    let title: String
    let isCurrent: Bool
}

final class TabPointerTrackingView: NSView {
    var preview: AnyView?
    var edge: DeckEdge = .right
    var previewsEnabled = true {
        didSet { if !previewsEnabled { hidePreview() } }
    }
    var previewDelay: TimeInterval = 0.4
    var onTrackingChanged: (Bool, Bool) -> Void = { _, _ in }
    var onClick: () -> Void = {}
    var contextMenuTitle = ""
    var contextMenuItems: [TabPointerContextMenuItem] = []
    var onContextMenuItem: (UUID) -> Void = { _ in }
    var onDragChanged: (CGFloat, CGPoint) -> Void = { _, _ in }
    var onDragEnded: (CGFloat, CGPoint) -> Void = { _, _ in }
    var onDragCancelled: () -> Void = {}

    private var dragSession = TabPointerDragSession()
    private var hoverTrackingArea: NSTrackingArea?
    private var releaseObserver: NSObjectProtocol?
    private var pressGeneration: UInt64 = 0
    private var previewTask: DispatchWorkItem?
    private var previewPanel: TabHoverPreviewPanel?

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        hidePreview()
        guard previewsEnabled, dragSession.initialScreenY == nil else { return }
        let task = DispatchWorkItem { [weak self] in self?.showPreview() }
        previewTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + previewDelay, execute: task)
    }

    override func mouseExited(with event: NSEvent) {
        hidePreview()
    }

    func showPreviewForTesting() {
        hidePreview()
        showPreview()
    }

    override func mouseDown(with event: NSEvent) {
        hidePreview()
        removeReleaseObserver()
        pressGeneration &+= 1
        let generation = pressGeneration
        dragSession.mouseDown(screenY: screenY(for: event))
        onTrackingChanged(true, true)
        releaseObserver = NotificationCenter.default.addObserver(
            forName: .dockNotesPointerReleased, object: nil, queue: .main
        ) { [weak self] notification in
            // The app monitor runs before the view's normal mouseUp. Give it
            // one event-loop turn to finish before recovering a missed release.
            let releaseWindowNumber = (notification.object as? NSEvent)?.windowNumber
            let releaseLocation = (notification.object as? NSEvent)?.locationInWindow
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pressGeneration == generation,
                      self.dragSession.initialScreenY != nil else { return }
                let releasePoint: NSPoint
                if let releaseWindowNumber, let releaseLocation,
                   let window = self.window, releaseWindowNumber == window.windowNumber {
                    releasePoint = window.convertPoint(toScreen: releaseLocation)
                } else {
                    releasePoint = NSEvent.mouseLocation
                }
                self.recoverRelease(at: releasePoint)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard case let .dragChanged(translation)? = dragSession.mouseDragged(
            screenY: screenY(for: event)
        ) else { return }
        hidePreview()
        onDragChanged(translation, NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragSession.initialScreenY != nil else { return }
        removeReleaseObserver()
        let result = dragSession.mouseUp(screenY: screenY(for: event))
        let releasePoint = screenPoint(for: event)
        onTrackingChanged(false, window?.frame.contains(releasePoint) == true)
        switch result {
        case .clicked:
            if containsScreenPoint(releasePoint) { onClick() }
        case let .dragEnded(translation):
            onDragEnded(translation, NSEvent.mouseLocation)
        case .dragChanged, .none:
            break
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !contextMenuItems.isEmpty else {
            super.rightMouseDown(with: event)
            return
        }
        hidePreview()
        let menu = NSMenu(title: contextMenuTitle)
        let heading = NSMenuItem(title: contextMenuTitle, action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        for entry in contextMenuItems {
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(selectContextWorkspace(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = entry.id.uuidString
            item.state = entry.isCurrent ? .on : .off
            item.isEnabled = !entry.isCurrent
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func selectContextWorkspace(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let id = UUID(uuidString: value) else { return }
        onContextMenuItem(id)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { hidePreview() }
        if newWindow == nil, dragSession.initialScreenY != nil {
            cancelTracking()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func showPreview() {
        guard previewsEnabled, dragSession.initialScreenY == nil,
              let preview, let window else { return }
        let host = NSHostingView(rootView: preview)
        let size = host.fittingSize
        let panel = TabHoverPreviewPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let anchor = window.convertToScreen(convert(bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? anchor
        let x = edge == .right ? anchor.minX - size.width - 8 : anchor.maxX + 8
        panel.setFrameOrigin(NSPoint(
            x: min(max(x, screen.minX), screen.maxX - size.width),
            y: min(max(anchor.midY - size.height / 2, screen.minY), screen.maxY - size.height)
        ))
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        previewPanel = panel
    }

    private func hidePreview() {
        previewTask?.cancel()
        previewTask = nil
        if let previewPanel {
            previewPanel.parent?.removeChildWindow(previewPanel)
            previewPanel.orderOut(nil)
        }
        previewPanel = nil
    }

    private func removeReleaseObserver() {
        if let releaseObserver { NotificationCenter.default.removeObserver(releaseObserver) }
        releaseObserver = nil
    }

    private func cancelTracking() {
        removeReleaseObserver()
        dragSession.cancel()
        onTrackingChanged(false, window?.frame.contains(NSEvent.mouseLocation) == true)
        onDragCancelled()
    }

    private func recoverRelease(at screenPoint: NSPoint) {
        guard window?.frame.contains(screenPoint) == true else {
            cancelTracking()
            return
        }
        removeReleaseObserver()
        let result = dragSession.mouseUp(screenY: screenPoint.y)
        onTrackingChanged(false, true)
        switch result {
        case .clicked:
            if containsScreenPoint(screenPoint) { onClick() }
        case let .dragEnded(translation):
            onDragEnded(translation, screenPoint)
        case .dragChanged, .none:
            break
        }
    }

    private func containsScreenPoint(_ screenPoint: NSPoint) -> Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.convertPoint(fromScreen: screenPoint), from: nil))
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        if let window, event.windowNumber == window.windowNumber {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        return event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    private func screenY(for event: NSEvent) -> CGFloat {
        guard let window else { return event.locationInWindow.y }
        return window.convertPoint(toScreen: event.locationInWindow).y
    }
}

private final class TabHoverPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct RestingDeckActivationSurface: NSViewRepresentable {
    let onActivate: () -> Void

    func makeNSView(context: Context) -> RestingDeckActivationView {
        let view = RestingDeckActivationView()
        view.onActivate = onActivate
        return view
    }

    func updateNSView(_ view: RestingDeckActivationView, context: Context) {
        view.onActivate = onActivate
        view.updateTrackingAreas()
    }
}

final class RestingDeckActivationView: NSView {
    var onActivate: () -> Void = {}
    private var area: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        if let area { removeTrackingArea(area) }
        let newArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        area = newArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { onActivate() }
    override func mouseDown(with event: NSEvent) { onActivate() }
}

// Keep hover ownership on a stationary rectangle. Reordering/animating labels
// must not manufacture a deck-exit event while the pointer remains inside it.
struct DeckPointerBoundary: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> DeckPointerBoundaryView {
        let view = DeckPointerBoundaryView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: DeckPointerBoundaryView, context: Context) {
        view.onHover = onHover
    }
}

final class DeckPointerBoundaryView: NSView {
    var onHover: (Bool) -> Void = { _ in }
    private var area: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        if let area { removeTrackingArea(area) }
        let newArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self, userInfo: nil
        )
        addTrackingArea(newArea)
        area = newArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
}
