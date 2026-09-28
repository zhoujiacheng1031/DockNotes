import AppKit
import SwiftUI
import UniformTypeIdentifiers

private extension View {
    /// DockNotes draws its own selected/pressed state for compact chrome.
    /// Keep keyboard accessibility while suppressing AppKit's persistent blue
    /// focus halo, which does not follow the custom control shape.
    func dockNotesChromeButton() -> some View {
        buttonStyle(.plain)
            .focusEffectDisabled()
    }

    /// The shared DockNotes glass language. On macOS 26 this is backed by the
    /// system Liquid Glass renderer; older systems keep the same hierarchy
    /// with a material, a cool inner wash, and a luminous edge.
    @ViewBuilder
    func dockNotesGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        clear: Bool = false,
        fallbackOpacity: Double = 0.34
    ) -> some View {
        modifier(DockNotesGlassModifier(
            shape: shape,
            tint: tint,
            interactive: interactive,
            clear: clear,
            fallbackOpacity: fallbackOpacity
        ))
    }

    func dockNotesGlassPanel(
        radius: CGFloat = 16,
        tint: Color? = nil,
        interactive: Bool = false,
        clear: Bool = false,
        fallbackOpacity: Double = 0.34
    ) -> some View {
        dockNotesGlass(
            in: RoundedRectangle(cornerRadius: radius, style: .continuous),
            tint: tint,
            interactive: interactive,
            clear: clear,
            fallbackOpacity: fallbackOpacity
        )
    }

    func dockNotesGlassCapsule(
        tint: Color? = nil,
        interactive: Bool = false,
        clear: Bool = false,
        fallbackOpacity: Double = 0.34
    ) -> some View {
        dockNotesGlass(
            in: Capsule(style: .continuous),
            tint: tint,
            interactive: interactive,
            clear: clear,
            fallbackOpacity: fallbackOpacity
        )
    }
}

enum DockNotesGlassRenderingMode: Equatable {
    case system
    case stableMaterial
}

private struct DockNotesGlassRenderingModeKey: EnvironmentKey {
    static let defaultValue: DockNotesGlassRenderingMode = .system
}

extension EnvironmentValues {
    var dockNotesGlassRenderingMode: DockNotesGlassRenderingMode {
        get { self[DockNotesGlassRenderingModeKey.self] }
        set { self[DockNotesGlassRenderingModeKey.self] = newValue }
    }
}

private struct DockNotesGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.dockNotesGlassRenderingMode) private var renderingMode

    let shape: S
    let tint: Color?
    let interactive: Bool
    let clear: Bool
    let fallbackOpacity: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *),
           renderingMode == .system,
           !DockNotesGlassRuntime.isStaticRendering {
            content.glassEffect(
                (clear ? Glass.clear : Glass.regular)
                    .tint(tint)
                    .interactive(interactive),
                in: shape
            )
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background((tint ?? Color.white).opacity(fallbackOpacity), in: shape)
                .overlay {
                    shape.stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.86), Color.white.opacity(0.28), Color.black.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                }
        }
    }
}

private enum DockNotesGlassMetrics {
    static let panelRadius: CGFloat = 18
    static let controlRadius: CGFloat = 10
    static let softShadow = Color.black.opacity(0.12)
    static let hairline = Color.white.opacity(0.68)
}

private enum DockNotesGlassRuntime {
    /// SwiftUI's off-screen ImageRenderer does not composite the macOS 26
    /// backdrop pass. Preview commands therefore use the faithful material
    /// fallback while the running app continues to use native Liquid Glass.
    static let isStaticRendering = CommandLine.arguments.contains {
        $0.hasPrefix("--render-")
    }
}

/// One glass base for a whole utility window. A soft palette wash sits above
/// the system material, so the gradient colors stay visible without turning
/// the page back into an opaque card.
private struct DockNotesGlassCanvas: View {
    let accent: Color

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .dockNotesGlass(
                in: Rectangle(),
                tint: accent.opacity(0.06),
                fallbackOpacity: 0.26
            )
            .overlay {
                LinearGradient(
                    colors: [
                        Color(hex: NotePalette.gradients[0].endHex).opacity(0.30),
                        accent.opacity(0.20),
                        Color(hex: NotePalette.gradients[2].endHex).opacity(0.19),
                        Color(hex: NotePalette.gradients[1].endHex).opacity(0.24)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            }
            .allowsHitTesting(false)
    }
}

private struct DockNotesGlassWindowChrome: NSViewRepresentable {
    var backgroundColor: NSColor = .clear

    func makeNSView(context: Context) -> DockNotesGlassWindowChromeView {
        let view = DockNotesGlassWindowChromeView(frame: .zero)
        view.backgroundColor = backgroundColor
        return view
    }

    func updateNSView(_ nsView: DockNotesGlassWindowChromeView, context: Context) {
        nsView.backgroundColor = backgroundColor
        nsView.configureWindow()
    }
}

final class DockNotesGlassWindowChromeView: NSView {
    var backgroundColor: NSColor = .clear

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        window?.isOpaque = false
        window?.backgroundColor = backgroundColor
        window?.titlebarAppearsTransparent = true
        window?.isMovableByWindowBackground = true
    }
}

enum NoteSearchHighlighter {
    static func apply(to layoutManager: NSLayoutManager, text: String, query: String) -> [NSRange] {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
        let ranges = NoteSearchEngine.matchRanges(in: text, query: query)
        for range in ranges {
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.72),
                forCharacterRange: range
            )
            layoutManager.addTemporaryAttribute(
                .underlineColor,
                value: NSColor.systemOrange.withAlphaComponent(0.9),
                forCharacterRange: range
            )
            layoutManager.addTemporaryAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                forCharacterRange: range
            )
        }
        return ranges
    }
}

struct UndoDeletionBanner: View {
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        if let pending = store.latestPendingDeletion {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(settings.text(.deletedNote)) “\(pending.note.title)”")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(settings.text(.undo)) {
                    store.undoLatestDeletion(language: settings.language)
                }
                .font(.system(size: 12, weight: .bold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 14)
            .frame(width: 340, height: 46)
            .dockNotesGlassPanel(radius: 14, tint: Color.white.opacity(0.08))
            .shadow(color: Color.black.opacity(0.18), radius: 14, y: 5)
            .padding(8)
            .accessibilityElement(children: .contain)
        }
    }
}

struct QuickCaptureView: View {
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    @State private var title = ""
    @State private var bodyDraft = ""
    @FocusState private var bodyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Color.orange)
                Text(settings.text(.quickCapture))
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text(settings.text(.quickCaptureHint))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            TextField(settings.text(.newNote), text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 11)
                .frame(height: 34)
                .dockNotesGlassPanel(radius: 10, tint: Color.white.opacity(0.08), interactive: true)
            TextEditor(text: $bodyDraft)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($bodyFocused)
                .padding(8)
                .dockNotesGlassPanel(radius: 12, tint: Color.white.opacity(0.08), interactive: true)
            HStack {
                Spacer()
                Button(settings.text(.cancel)) { store.isQuickCapturePresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(settings.text(.save)) { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && bodyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 420, height: 245)
        .background(NotePalette.gradients[0].swiftUIGradient.opacity(0.28))
        .dockNotesGlassPanel(radius: 20, tint: Color(hex: NotePalette.gradients[0].startHex).opacity(0.12))
        .onAppear {
            title = ""
            bodyDraft = ""
            DispatchQueue.main.async { bodyFocused = true }
        }
        .onExitCommand { store.isQuickCapturePresented = false }
    }

    private func save() {
        _ = store.saveQuickCapture(title: title, body: bodyDraft, language: settings.language)
    }
}

struct NoteWindowView: View {
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        Group {
            if let note = store.activeNote {
                NoteCard(note: note, store: store, settings: settings)
                    .id(note.id)
                    .opacity(settings.expandedOpacity)
            }
        }
        .frame(width: 460, height: 380, alignment: .trailing)
        .animation(.easeOut(duration: 0.14), value: store.activeNoteID)
        .background(Color.clear)
    }
}

struct DesktopNoteWindowView: View {
    let noteID: DockNote.ID
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { geometry in
                Group {
                    if let note = store.note(id: noteID) {
                        NoteCard(
                            note: note,
                            store: store,
                            settings: settings,
                            closeAction: { store.closeDesktopNote(noteID) }
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .opacity(settings.expandedOpacity)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }

            DesktopWindowResizeGrip()
                .frame(width: 18, height: 18)
                .overlay {
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.28))
                        .allowsHitTesting(false)
                }
                .padding(2)
        }
    }
}

private struct DesktopWindowResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> DesktopWindowResizeGripView {
        DesktopWindowResizeGripView()
    }

    func updateNSView(_ nsView: DesktopWindowResizeGripView, context: Context) {}
}

private struct DesktopWindowDragSurface: NSViewRepresentable {
    var accessibilityIdentifier = "DockNotesDesktopDragHandle"

    func makeNSView(context: Context) -> DesktopWindowDragView {
        DesktopWindowDragView(accessibilityIdentifier: accessibilityIdentifier)
    }

    func updateNSView(_ nsView: DesktopWindowDragView, context: Context) {
        nsView.setAccessibilityIdentifier(accessibilityIdentifier)
    }
}

final class DesktopWindowDragView: NSView {
    private var startingOrigin: NSPoint?
    private var startingPointer: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(accessibilityIdentifier: String) {
        super.init(frame: .zero)
        setAccessibilityIdentifier(accessibilityIdentifier)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityIdentifier("DockNotesDesktopDragHandle")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityIdentifier("DockNotesDesktopDragHandle")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

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

private final class DesktopWindowResizeGripView: NSView {
    private var initialWindowFrame: NSRect?
    private var initialMouseLocation: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialWindowFrame = window.frame
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let initialWindowFrame,
              let initialMouseLocation else { return }
        let current = NSEvent.mouseLocation
        let width = min(
            max(initialWindowFrame.width + current.x - initialMouseLocation.x, PanelCoordinator.desktopWindowMinimumSize.width),
            PanelCoordinator.desktopWindowMaximumSize.width
        )
        let height = min(
            max(initialWindowFrame.height - current.y + initialMouseLocation.y, PanelCoordinator.desktopWindowMinimumSize.height),
            PanelCoordinator.desktopWindowMaximumSize.height
        )
        let frame = NSRect(
            x: initialWindowFrame.minX,
            y: initialWindowFrame.maxY - height,
            width: width,
            height: height
        )
        if let desktopWindow = window as? DesktopNoteWindow {
            desktopWindow.setExplicitFrame(frame, display: true)
        } else {
            window.setFrame(frame, display: true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        initialWindowFrame = nil
        initialMouseLocation = nil
    }
}

struct DeckWindowView: View {
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    let availableHeight: CGFloat
    var isDesignPreview = false
    @State private var isOverflowPresented = false
    @State private var isWorkspaceSwitcherPresented = false
    @State private var isActionsPresented = false
    @State private var workspaceCapsuleScreenFrame = CGRect.zero
    @State private var workspaceDropFrames: [NoteWorkspace.ID: CGRect] = [:]
    @State private var workspaceDropTargetID: NoteWorkspace.ID?
    @State private var isWorkspaceDropSession = false
    @StateObject private var tabDrag = TabDragCoordinator()

    private var deckNotes: [DockNote] { store.activeWorkspaceNotes }

    private var plan: DeckPlan {
        DeckLayout.plan(
            notes: deckNotes,
            activeNoteID: store.activeNoteID,
            isExpanded: store.isExpanded,
            availableHeight: availableHeight,
            preferredVisibleCount: settings.visibleTabCount,
            excludedNoteIDs: Set(store.desktopNoteIDs)
        )
    }

    private var overflowNotes: [DockNote] {
        let ids = Set(plan.overflowIDs)
        return deckNotes.filter { ids.contains($0.id) }
    }

    private var positionedTabs: [PositionedTab] {
        plan.slots.enumerated().compactMap { slot, noteID in
            guard let noteID,
                  let note = deckNotes.first(where: { $0.id == noteID }) else { return nil }
            return PositionedTab(note: note, slot: slot)
        }
    }

    private var tabPitch: CGFloat {
        DeckLayout.tabPitch(for: availableHeight, slotCount: plan.slots.count)
    }

    private var deckContentHeight: CGFloat {
        let controlCount = overflowNotes.isEmpty ? 3 : 4
        let controlsHeight = DeckLayout.controlStackHeight(count: controlCount)
        let tabAreaHeight = deckNotes.isEmpty
            ? DeckLayout.emptyDeckHeight
            : DeckLayout.deckStackHeight(noteSlotCount: plan.slots.count, pitch: tabPitch)
        return tabAreaHeight + controlsHeight
    }

    var body: some View {
        Group {
            if store.deckState.showsTabs {
                VStack(alignment: settings.deckEdge == .right ? .trailing : .leading, spacing: 0) {
                    ZStack(alignment: settings.deckEdge == .right ? .topTrailing : .topLeading) {
                        if deckNotes.isEmpty {
                            NewNoteDeckCard(
                                workspace: store.activeWorkspace,
                                edge: settings.deckEdge,
                                accessibilityLabel: settings.text(.newNote)
                            ) {
                                store.addNote(language: settings.language)
                            }
                        } else {
                            ForEach(positionedTabs) { positionedTab in
                            let note = positionedTab.note
                            let slot = positionedTab.slot
                            let isSelected = EdgeTabSelection.isSelected(
                                noteID: note.id,
                                activeNoteID: store.activeNoteID
                            )
                            EdgeTab(
                                note: note,
                                edge: settings.deckEdge,
                                language: settings.language,
                                tiltDegrees: DeckLayout.tiltDegrees(for: slot),
                                isDragging: tabDrag.noteID == note.id
                            )
                            .overlay(alignment: settings.deckEdge == .right ? .trailing : .leading) {
                                if !isDesignPreview {
                                    TabPointerDragSurface(
                                        preview: AnyView(EdgeTabHoverCard(note: note, language: settings.language)),
                                        edge: settings.deckEdge,
                                        previewsEnabled: tabDrag.noteID == nil,
                                        onTrackingChanged: { tracking, pointerInside in
                                            if tracking {
                                                store.beginTrackingDeckLabel(note.id)
                                            } else {
                                                store.endTrackingDeckLabel(
                                                    note.id, keepOpen: settings.keepDeckOpen, pointerInside: pointerInside
                                                )
                                            }
                                        },
                                        onClick: {
                                            tabDrag.recoverInterruptedDrag(noteID: note.id)
                                            store.select(note.id)
                                        },
                                        contextMenuTitle: settings.text(.moveToWorkspace),
                                        contextMenuItems: store.workspaces.map { workspace in
                                            TabPointerContextMenuItem(
                                                id: workspace.id,
                                                title: workspace.name,
                                                isCurrent: workspace.id == note.workspaceID
                                            )
                                        },
                                        onContextMenuItem: { workspaceID in
                                            store.moveNote(note.id, toWorkspace: workspaceID)
                                        },
                                        onDragChanged: { translation, screenPoint in
                                            updateTabDrag(
                                                noteID: note.id,
                                                sourceSlot: slot,
                                                translation: translation,
                                                screenPoint: screenPoint
                                            )
                                        },
                                        onDragEnded: { translation, screenPoint in
                                            finishTabDrag(
                                                noteID: note.id,
                                                sourceSlot: slot,
                                                translation: translation,
                                                screenPoint: screenPoint
                                            )
                                        },
                                        onDragCancelled: {
                                            tabDrag.recoverInterruptedDrag(noteID: note.id)
                                            resetWorkspaceDrop()
                                        }
                                    )
                                    .frame(
                                        width: DeckLayout.tabWidth,
                                        height: DeckLayout.tabVisualHeight
                                    )
                                }
                            }
                            .accessibilityLabel(note.title)
                            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
                            .modifier(
                                TabDragVisualModifier(
                                    noteID: note.id,
                                    slot: slot,
                                    tabPitch: tabPitch,
                                    dragCoordinator: tabDrag
                                )
                            )
                            .offset(y: CGFloat(slot) * tabPitch)
                            .zIndex(tabDrag.noteID == note.id ? 100 : Double(slot))
                            }
                            NewNoteDeckCard(
                                workspace: store.activeWorkspace,
                                edge: settings.deckEdge,
                                accessibilityLabel: settings.text(.newNote)
                            ) {
                                store.addNote(language: settings.language)
                            }
                            .offset(y: CGFloat(plan.slots.count) * tabPitch)
                            .zIndex(Double(plan.slots.count))
                        }
                    }
                    .frame(
                        width: DeckLayout.windowWidth,
                        height: deckNotes.isEmpty
                            ? DeckLayout.emptyDeckHeight
                            : DeckLayout.deckStackHeight(noteSlotCount: plan.slots.count, pitch: tabPitch),
                        alignment: .topTrailing
                    )

                    VStack(spacing: DeckLayout.controlSpacing) {
                        if !overflowNotes.isEmpty {
                            Button {
                                isOverflowPresented.toggle()
                            } label: {
                                Text("+\(overflowNotes.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.58))
                                    .frame(
                                        width: DeckLayout.controlButtonHeight,
                                        height: DeckLayout.controlButtonHeight
                                    )
                                    .dockNotesGlass(in: Circle(), tint: Color.white.opacity(0.08), interactive: true)
                            }
                            .dockNotesChromeButton()
                            .help(settings.text(.moreNotes))
                            .popover(
                                isPresented: $isOverflowPresented,
                                arrowEdge: settings.deckEdge == .right ? .trailing : .leading
                            ) {
                                OverflowNotesView(notes: overflowNotes, store: store, settings: settings) {
                                    isOverflowPresented = false
                                }
                            }
                        }
                        Button {
                            isWorkspaceSwitcherPresented.toggle()
                        } label: {
                            WorkspaceCapsule(workspace: store.activeWorkspace)
                                .background {
                                    if !isDesignPreview {
                                        ScreenFrameReader { frame in
                                            workspaceCapsuleScreenFrame = frame
                                        }
                                    }
                                }
                        }
                        .dockNotesChromeButton()
                        .help(settings.text(.workspaces))
                        .accessibilityLabel(settings.text(.workspaces))
                        .popover(
                            isPresented: $isWorkspaceSwitcherPresented,
                            arrowEdge: settings.deckEdge == .right ? .trailing : .leading
                        ) {
                            WorkspaceSwitcherView(
                                store: store,
                                settings: settings,
                                draggedNoteID: isWorkspaceDropSession ? tabDrag.noteID : nil,
                                dropTargetID: workspaceDropTargetID,
                                reportDropFrame: { id, frame in
                                    workspaceDropFrames[id] = frame
                                }
                            ) {
                                isWorkspaceSwitcherPresented = false
                            }
                        }
                        deckButton("rectangle.stack.fill", label: settings.text(.library)) {
                            store.presentLibrary()
                        }
                        deckButton("ellipsis", label: settings.text(.moreActions)) {
                            isActionsPresented.toggle()
                        }
                        .popover(
                            isPresented: $isActionsPresented,
                            arrowEdge: settings.deckEdge == .right ? .trailing : .leading
                        ) {
                            VStack(spacing: 4) {
                                deckActionRow("checklist", label: settings.text(.taskCenter)) {
                                    isActionsPresented = false
                                    store.presentTaskCenter()
                                }
                                deckActionRow("gearshape", label: settings.text(.preferences)) {
                                    isActionsPresented = false
                                    store.presentSettings()
                                }
                            }
                            .padding(8)
                            .frame(width: 210)
                            .dockNotesGlassPanel(radius: 14, tint: Color.white.opacity(0.07))
                        }
                    }
                    .frame(width: DeckLayout.windowWidth)
                    .padding(.top, DeckLayout.controlTopPadding)
                }
                .frame(width: DeckLayout.windowWidth, height: deckContentHeight, alignment: .top)
                .transition(
                    .opacity.combined(
                        with: .move(edge: settings.deckEdge == .right ? .trailing : .leading)
                    )
                )
            } else {
                ZStack(alignment: settings.deckEdge == .right ? .trailing : .leading) {
                    RestingDeckIndicator(
                        notes: deckNotes,
                        availableHeight: availableHeight,
                        edge: settings.deckEdge
                    )
                    .allowsHitTesting(false)

                    RestingDeckActivationSurface {
                        if store.deckState == .resting { store.pointerEnteredDeck() }
                    }
                        .frame(width: DeckLayout.restingActivationWidth, height: availableHeight)
                        .accessibilityLabel("DockNotes")
                }
                .frame(width: DeckLayout.windowWidth, height: availableHeight)
                .transition(.opacity)
            }
        }
        .frame(width: DeckLayout.windowWidth, height: availableHeight, alignment: .center)
        .opacity(settings.collapsedOpacity)
        .background(Color.clear)
        .contentShape(Rectangle())
        .background {
            if !isDesignPreview {
                DeckPointerBoundary { hovering in
                    guard store.deckState != .resting else { return }
                    if hovering {
                        store.pointerEnteredDeck()
                    } else {
                        store.pointerExitedDeck(keepOpen: settings.keepDeckOpen)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.deckState)
    }

    private func updateTabDrag(
        noteID: DockNote.ID,
        sourceSlot: Int,
        translation: CGFloat,
        screenPoint: CGPoint
    ) {
        tabDrag.begin(noteID: noteID, sourceSlot: sourceSlot)
        let target = DeckLayout.dragTarget(
            sourceSlot: tabDrag.sourceSlot,
            translation: translation,
            slotCount: plan.slots.count,
            pitch: tabPitch
        )
        tabDrag.update(translation: translation, targetSlot: target, noteID: noteID)
        updateWorkspaceDropTarget(at: screenPoint)
    }

    private func finishTabDrag(
        noteID: DockNote.ID,
        sourceSlot: Int,
        translation: CGFloat,
        screenPoint: CGPoint
    ) {
        tabDrag.begin(noteID: noteID, sourceSlot: sourceSlot)
        updateWorkspaceDropTarget(at: screenPoint)
        if isWorkspaceDropSession {
            if let workspaceDropTargetID,
               workspaceDropTargetID != store.activeWorkspaceID {
                store.moveNote(noteID, toWorkspace: workspaceDropTargetID)
            }
            tabDrag.recoverInterruptedDrag(noteID: noteID)
            resetWorkspaceDrop()
            return
        }
        let destination = DeckLayout.dragTarget(
            sourceSlot: tabDrag.sourceSlot,
            translation: translation,
            slotCount: plan.slots.count,
            pitch: tabPitch
        )
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            tabDrag.beginSettling(
                destinationSlot: destination,
                translation: translation,
                pitch: tabPitch,
                noteID: noteID
            )
            store.moveNote(noteID, toWorkspace: store.activeWorkspaceID, at: destination)
        }
        tabDrag.completeSettling(noteID: noteID)
    }

    private func updateWorkspaceDropTarget(at screenPoint: CGPoint) {
        if WorkspaceDropRouting.enteredCapsule(
            at: screenPoint,
            capsuleFrame: workspaceCapsuleScreenFrame
        ) {
            isWorkspaceDropSession = true
            if !isWorkspaceSwitcherPresented { isWorkspaceSwitcherPresented = true }
        }
        guard isWorkspaceDropSession else { return }
        workspaceDropTargetID = WorkspaceDropRouting.targetWorkspace(
            at: screenPoint,
            currentWorkspaceID: store.activeWorkspaceID,
            frames: workspaceDropFrames
        )
    }

    private func resetWorkspaceDrop() {
        isWorkspaceDropSession = false
        workspaceDropTargetID = nil
        workspaceDropFrames.removeAll()
        isWorkspaceSwitcherPresented = false
    }

    private func deckButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            deckControlLabel(symbol)
        }
        .dockNotesChromeButton()
        .help(label)
        .accessibilityLabel(label)
    }

    private func deckControlLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.58))
            .frame(
                width: DeckLayout.controlButtonHeight,
                height: DeckLayout.controlButtonHeight
            )
            .dockNotesGlass(in: Circle(), tint: Color.white.opacity(0.08), interactive: true)
    }

    private func deckActionRow(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Color.primary.opacity(0.78))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .dockNotesGlassPanel(radius: 10, tint: Color.white.opacity(0.04), interactive: true)
            .contentShape(Rectangle())
        }
        .dockNotesChromeButton()
    }
}

enum WorkspaceDropRouting {
    static func enteredCapsule(at point: CGPoint, capsuleFrame: CGRect) -> Bool {
        !capsuleFrame.isEmpty && capsuleFrame.insetBy(dx: -8, dy: -8).contains(point)
    }

    static func targetWorkspace(
        at point: CGPoint,
        currentWorkspaceID: NoteWorkspace.ID,
        frames: [NoteWorkspace.ID: CGRect]
    ) -> NoteWorkspace.ID? {
        frames.first(where: { id, frame in
            id != currentWorkspaceID && frame.insetBy(dx: -3, dy: -2).contains(point)
        })?.key
    }
}

private struct WorkspaceCapsule: View {
    let workspace: NoteWorkspace

    private var abbreviation: String {
        let compact = workspace.name.filter { !$0.isWhitespace }
        return String(compact.prefix(2))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: workspace.colorHex).opacity(0.78), Color.white.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.78), lineWidth: 0.7)
            Text(abbreviation)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.62))
                .lineLimit(1)
        }
        .frame(width: 38, height: DeckLayout.controlButtonHeight)
        .dockNotesGlassPanel(radius: 10, tint: Color(hex: workspace.colorHex).opacity(0.12), interactive: true)
        .shadow(color: Color.black.opacity(0.10), radius: 3, x: 0, y: 2)
    }
}

private struct NewNoteDeckCard: View {
    let workspace: NoteWorkspace
    let edge: DeckEdge
    let accessibilityLabel: String
    let createNote: () -> Void

    var body: some View {
        Button(action: createNote) {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: workspace.colorHex).opacity(0.34), Color.white.opacity(0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.42))
            }
            .frame(width: DeckLayout.tabWidth, height: DeckLayout.newNoteCardHeight)
            .background {
                TuckyTabShape(edge: edge)
                    .fill(Color.clear)
                    .dockNotesGlass(
                        in: TuckyTabShape(edge: edge),
                        tint: Color(hex: workspace.colorHex).opacity(0.10),
                        interactive: true,
                        fallbackOpacity: 0.18
                    )
            }
            .clipShape(TuckyTabShape(edge: edge))
            .shadow(color: Color.black.opacity(0.07), radius: 3, x: edge == .right ? -2 : 2, y: 2)
        }
        .dockNotesChromeButton()
        .frame(width: DeckLayout.windowWidth, height: 132, alignment: edge == .right ? .trailing : .leading)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct WorkspaceSwitcherView: View {
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    let draggedNoteID: DockNote.ID?
    let dropTargetID: NoteWorkspace.ID?
    let reportDropFrame: (NoteWorkspace.ID, CGRect) -> Void
    let dismiss: () -> Void
    var reportsDropFrames = true
    @State private var editingWorkspaceID: NoteWorkspace.ID?
    @State private var workspaceNameDraft = ""
    @FocusState private var focusedWorkspaceID: NoteWorkspace.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(settings.text(.workspaces))
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("\(store.workspaces.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { index, workspace in
                        HStack(spacing: 4) {
                            if editingWorkspaceID == workspace.id {
                                Circle()
                                    .fill(Color(hex: workspace.colorHex))
                                    .frame(width: 11, height: 11)
                                TextField(settings.text(.workspaceName), text: $workspaceNameDraft)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .semibold))
                                    .focused($focusedWorkspaceID, equals: workspace.id)
                                    .onSubmit { commitWorkspaceRename(workspace.id) }
                                Spacer()
                                Button {
                                    commitWorkspaceRename(workspace.id)
                                } label: {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: 22, height: 26)
                                }
                                .dockNotesChromeButton()
                                .disabled(workspaceNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .help(settings.text(.save))
                                Button {
                                    cancelWorkspaceRename()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .frame(width: 22, height: 26)
                                }
                                .dockNotesChromeButton()
                                .help(settings.text(.cancel))
                            } else {
                                Button {
                                    store.switchWorkspace(to: workspace.id)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 9) {
                                        Circle()
                                            .fill(Color(hex: workspace.colorHex))
                                            .frame(width: 11, height: 11)
                                        Text(workspace.name)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(store.notes.filter { $0.workspaceID == workspace.id }.count)")
                                            .font(.system(size: 10).monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        if workspace.id == store.activeWorkspaceID {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                        } else if index < 9 {
                                            Text("⌥⌘\(index + 1)")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .dockNotesChromeButton()
                                .disabled(draggedNoteID != nil && workspace.id == store.activeWorkspaceID)

                                if draggedNoteID == nil {
                                    Button {
                                        beginWorkspaceRename(workspace)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 10, weight: .semibold))
                                            .frame(width: 22, height: 26)
                                    }
                                    .dockNotesChromeButton()
                                    .help(settings.text(.renameWorkspace))
                                    .accessibilityLabel(settings.text(.renameWorkspace))
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 34)
                        .background(
                            workspace.id == dropTargetID
                                ? Color(hex: workspace.colorHex).opacity(0.20)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .dockNotesGlassPanel(
                            radius: 9,
                            tint: workspace.id == store.activeWorkspaceID
                                ? Color(hex: workspace.colorHex).opacity(0.10)
                                : Color.white.opacity(0.025),
                            interactive: true,
                            fallbackOpacity: 0.12
                        )
                        .background {
                            if reportsDropFrames {
                                ScreenFrameReader { frame in
                                    reportDropFrame(workspace.id, frame)
                                }
                            }
                        }
                    }
                }
                .padding(5)
            }
            Divider()
            HStack(spacing: 4) {
                Button {
                    let baseName = settings.language == .english ? "Workspace" : "工作区"
                    _ = store.createWorkspace(name: "\(baseName) \(store.workspaces.count + 1)")
                    dismiss()
                } label: {
                    Label(settings.text(.newWorkspace), systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    dismiss()
                    DispatchQueue.main.async { store.presentWorkspaceManagement() }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 24)
                }
                .help(settings.text(.manageWorkspaces))
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .dockNotesChromeButton()
        }
        .frame(width: 248, height: min(CGFloat(store.workspaces.count * 37 + 92), 360))
        .dockNotesGlassPanel(radius: 16, tint: Color.white.opacity(0.08))
    }

    private func beginWorkspaceRename(_ workspace: NoteWorkspace) {
        editingWorkspaceID = workspace.id
        workspaceNameDraft = workspace.name
        DispatchQueue.main.async { focusedWorkspaceID = workspace.id }
    }

    private func commitWorkspaceRename(_ workspaceID: NoteWorkspace.ID) {
        guard store.renameWorkspace(workspaceID, to: workspaceNameDraft) else { return }
        editingWorkspaceID = nil
        workspaceNameDraft = ""
        focusedWorkspaceID = nil
    }

    private func cancelWorkspaceRename() {
        editingWorkspaceID = nil
        workspaceNameDraft = ""
        focusedWorkspaceID = nil
    }
}

private struct ScreenFrameReader: NSViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeNSView(context: Context) -> ScreenFrameReportingView {
        let view = ScreenFrameReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ScreenFrameReportingView, context: Context) {
        nsView.onChange = onChange
        nsView.reportFrame()
    }
}

private final class ScreenFrameReportingView: NSView {
    var onChange: (CGRect) -> Void = { _ in }

    override func layout() {
        super.layout()
        reportFrame()
    }

    func reportFrame() {
        guard let window else { return }
        let windowRect = convert(bounds, to: nil)
        let screenRect = window.convertToScreen(windowRect)
        DispatchQueue.main.async { [weak self] in self?.onChange(screenRect) }
    }
}

private struct PositionedTab: Identifiable {
    let note: DockNote
    let slot: Int
    var id: DockNote.ID { note.id }
}

@MainActor
final class TabDragCoordinator: ObservableObject {
    @Published private(set) var noteID: DockNote.ID?
    @Published private(set) var sourceSlot = 0
    @Published private(set) var targetSlot = 0
    @Published private(set) var settlingOffset: CGFloat = 0
    @Published private(set) var liveTranslation: CGFloat = 0
    @Published private(set) var isSettling = false
    private(set) var lastTranslation: CGFloat = 0
    private var settlingTask: Task<Void, Never>?
    private var sessionGeneration: UInt64 = 0

    func begin(noteID: DockNote.ID, sourceSlot: Int) {
        guard self.noteID != noteID || isSettling else { return }
        settlingTask?.cancel()
        settlingTask = nil
        sessionGeneration &+= 1
        self.noteID = noteID
        self.sourceSlot = sourceSlot
        targetSlot = sourceSlot
        settlingOffset = 0
        liveTranslation = 0
        isSettling = false
        lastTranslation = 0
    }

    func update(translation: CGFloat, targetSlot: Int, noteID: DockNote.ID) {
        guard self.noteID == noteID else { return }
        lastTranslation = translation
        liveTranslation = translation
        if self.targetSlot != targetSlot {
            self.targetSlot = targetSlot
        }
    }

    func beginSettling(
        destinationSlot: Int,
        translation: CGFloat,
        pitch: CGFloat,
        noteID: DockNote.ID
    ) {
        guard self.noteID == noteID else { return }
        lastTranslation = translation
        targetSlot = destinationSlot
        settlingOffset = DeckLayout.dragResidual(
            originSlot: sourceSlot,
            currentSlot: destinationSlot,
            translation: translation,
            pitch: pitch
        )
        isSettling = true
    }

    func completeSettling(noteID: DockNote.ID) {
        guard self.noteID == noteID, isSettling else { return }
        settlingTask?.cancel()
        withAnimation(.spring(response: 0.20, dampingFraction: 0.90)) {
            settlingOffset = 0
        }
        settlingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }
            self?.finish(noteID: noteID)
        }
    }

    func recoverInterruptedDrag(noteID: DockNote.ID) {
        guard self.noteID == noteID, !isSettling else { return }
        finish(noteID: noteID)
    }

    func recoveryGeneration(noteID: DockNote.ID) -> UInt64? {
        guard self.noteID == noteID else { return nil }
        return sessionGeneration
    }

    func recoverInterruptedDrag(noteID: DockNote.ID, sessionGeneration: UInt64) {
        guard self.sessionGeneration == sessionGeneration else { return }
        recoverInterruptedDrag(noteID: noteID)
    }

    func finish(noteID: DockNote.ID) {
        guard self.noteID == noteID else { return }
        settlingTask?.cancel()
        settlingTask = nil
        self.noteID = nil
        settlingOffset = 0
        liveTranslation = 0
        isSettling = false
        lastTranslation = 0
    }
}

private struct TabDragVisualModifier: ViewModifier {
    let noteID: DockNote.ID
    let slot: Int
    let tabPitch: CGFloat
    @ObservedObject var dragCoordinator: TabDragCoordinator

    private var isDragging: Bool { dragCoordinator.noteID == noteID }

    private var previewOffset: CGFloat {
        guard dragCoordinator.noteID != nil,
              !isDragging,
              !dragCoordinator.isSettling else { return 0 }
        return DeckLayout.dragPreviewOffset(
            for: slot,
            sourceSlot: dragCoordinator.sourceSlot,
            targetSlot: dragCoordinator.targetSlot,
            pitch: tabPitch
        )
    }

    private var dragOffset: CGFloat {
        guard isDragging else { return 0 }
        if dragCoordinator.isSettling {
            return dragCoordinator.settlingOffset
        }
        return dragCoordinator.liveTranslation
    }

    func body(content: Content) -> some View {
        content
            .offset(y: previewOffset)
            .animation(
                .interactiveSpring(response: 0.18, dampingFraction: 0.88),
                value: dragCoordinator.targetSlot
            )
            .offset(y: dragOffset)
            .scaleEffect(isDragging ? 1.035 : 1, anchor: .trailing)
            .opacity(isDragging ? 0.96 : 1)
            .zIndex(isDragging ? 100 : 0)
            .shadow(color: Color.black.opacity(isDragging ? 0.20 : 0), radius: 9, x: -3, y: 3)
            .onReceive(NotificationCenter.default.publisher(for: .dockNotesPointerReleased)) { _ in
                guard let sessionGeneration = dragCoordinator.recoveryGeneration(noteID: noteID) else {
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    dragCoordinator.recoverInterruptedDrag(
                        noteID: noteID,
                        sessionGeneration: sessionGeneration
                    )
                }
            }
            .onDisappear {
                dragCoordinator.recoverInterruptedDrag(noteID: noteID)
            }
    }
}

private struct RestingDeckIndicator: View {
    let notes: [DockNote]
    let availableHeight: CGFloat
    let edge: DeckEdge

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(notes.prefix(8))) { note in
                Capsule(style: .continuous)
                    .fill(note.gradient)
                    .frame(width: 8, height: 20)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.48), lineWidth: 0.55)
                    }
                    .shadow(color: Color(hex: note.colorHex).opacity(0.16), radius: 1.5, x: 0, y: 1)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .dockNotesGlassCapsule(tint: Color.white.opacity(0.07))
        .shadow(color: Color.black.opacity(0.14), radius: 7, x: edge == .right ? -2 : 2, y: 2)
        .frame(width: 26, height: availableHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: edge == .right ? .trailing : .leading)
        .accessibilityLabel("DockNotes")
    }
}

private struct OverflowNotesView: View {
    let notes: [DockNote]
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(settings.text(.moreNotes)).font(.system(size: 13, weight: .bold))
                Spacer()
                Text("\(notes.count)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(notes) { note in
                        Button {
                            store.select(note.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 9) {
                                Circle()
                                    .fill(note.gradient)
                                    .frame(width: 11, height: 11)
                                Text(note.title).lineLimit(1)
                                Spacer()
                                if let dueDate = note.dueDate {
                                    let deadline = DeadlinePresentation.make(for: dueDate, language: settings.language)
                                    Label(deadline.edgeLabel, systemImage: deadline.status == .overdue ? "exclamationmark.circle.fill" : "bell.fill")
                                        .font(.system(size: 8, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(deadline.status == .overdue ? Color.red.opacity(0.86) : Color.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .contentShape(Rectangle())
                        }
                        .dockNotesChromeButton()
                    }
                }
                .padding(.vertical, 5)
            }
        }
        .frame(width: 240, height: min(CGFloat(notes.count * 36 + 48), 320))
        .dockNotesGlassPanel(radius: 16, tint: Color.white.opacity(0.08))
    }
}

enum EdgeTabSelection {
    static func isSelected(noteID: DockNote.ID, activeNoteID: DockNote.ID?) -> Bool {
        noteID == activeNoteID
    }
}

private struct EdgeTab: View {
    let note: DockNote
    let edge: DeckEdge
    let language: AppLanguage
    let tiltDegrees: Double
    let isDragging: Bool

    private let ink = Color(nsColor: NSColor(deviceWhite: 0.10, alpha: 1))

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                note.gradient.opacity(0.18)
                LinearGradient(
                    colors: [Color.white.opacity(0.31), Color.white.opacity(0.09), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                ZStack(alignment: .top) {
                    Text(note.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(
                            width: EdgeTabLayout.titleContentLength,
                            height: DeckLayout.tabWidth - 14,
                            alignment: .leading
                        )
                        .rotationEffect(.degrees(edge == .right ? 90 : -90))
                        .frame(
                            width: DeckLayout.tabWidth - 14,
                            height: EdgeTabLayout.titleContentLength
                        )
                        .padding(.top, EdgeTabLayout.contentTopInset)

                    if let dueDate = note.dueDate {
                        let deadline = DeadlinePresentation.make(for: dueDate, language: language)
                        Text(deadline.edgeLabel)
                            .monospacedDigit()
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundStyle(deadline.status == .overdue ? Color.red.opacity(0.88) : ink.opacity(0.72))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.62), in: Capsule())
                        .fixedSize()
                        .frame(
                            width: EdgeTabLayout.deadlineContentLength,
                            height: 15
                        )
                        .padding(.top, EdgeTabLayout.deadlineTopInset)
                    }
                }
                .environment(\.colorScheme, .light)
                .frame(
                    width: DeckLayout.tabWidth,
                    height: DeckLayout.tabVisualHeight - 6,
                    alignment: .top
                )

                Rectangle()
                    .fill(Color.white.opacity(0.42))
                    .frame(width: 0.6, height: DeckLayout.tabVisualHeight - 18)
                    .frame(maxWidth: .infinity, alignment: edge == .right ? .trailing : .leading)
                    .padding(edge == .right ? .trailing : .leading, 4)

            }
            .frame(width: DeckLayout.tabWidth, height: DeckLayout.tabVisualHeight - 4)
            .dockNotesGlass(
                in: TuckyTabShape(edge: edge),
                tint: Color(hex: note.colorHex).opacity(0.20),
                interactive: true,
                fallbackOpacity: 0.13
            )
            .clipShape(TuckyTabShape(edge: edge))
            .contentShape(TuckyTabShape(edge: edge))
            .rotationEffect(
                .degrees(isDragging ? 0 : (edge == .right ? tiltDegrees : -tiltDegrees) * 0.25),
                anchor: edge == .right ? .trailing : .leading
            )
            .saturation(0.98)
            .shadow(
                color: Color.black.opacity(isDragging ? 0.14 : 0.06),
                radius: isDragging ? 7 : 3,
                x: edge == .right ? -2 : 2,
                y: 2
            )
            .animation(.easeOut(duration: 0.12), value: isDragging)
        }
        .frame(
            width: DeckLayout.windowWidth,
            height: DeckLayout.tabVisualHeight,
            alignment: edge == .right ? .trailing : .leading
        )
    }
}

struct EdgeTabHoverInfo: Equatable {
    let title: String
    let preview: String
    let deadline: DeadlinePresentation?
    let isPinned: Bool

    static func make(note: DockNote, language: AppLanguage) -> EdgeTabHoverInfo {
        EdgeTabHoverInfo(
            title: note.title,
            preview: note.body
                .split(whereSeparator: \Character.isWhitespace)
                .joined(separator: " "),
            deadline: note.dueDate.map { DeadlinePresentation.make(for: $0, language: language) },
            isPinned: note.isPinned
        )
    }
}

struct EdgeTabHoverCard: View {
    let note: DockNote
    let language: AppLanguage

    private var info: EdgeTabHoverInfo { .make(note: note, language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                Circle()
                    .fill(note.gradient)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 0.8))
                    .padding(.top, 3)

                Text(info.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if info.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let deadline = info.deadline {
                Label(
                    deadline.toolbarLabel,
                    systemImage: deadline.status == .overdue ? "exclamationmark.circle.fill" : "bell.fill"
                )
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(deadline.status == .overdue ? Color.red.opacity(0.88) : Color.secondary)
            }

            if !info.preview.isEmpty {
                Text(info.preview)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(note.modifiedAt, style: .relative)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 236, alignment: .leading)
        .background {
            note.gradient.opacity(0.10)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .dockNotesGlassPanel(radius: 14, tint: Color(hex: note.colorHex).opacity(0.08))
        .padding(4)
    }
}

private struct TuckyTabShape: Shape {
    let edge: DeckEdge

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 14
        var path = Path()
        if edge == .right {
            path.move(to: CGPoint(x: radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: radius, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(to: CGPoint(x: radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

struct NoteCard: View {
    let note: DockNote
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    var closeAction: (() -> Void)? = nil
    @StateObject private var dictation = DictationController()
    @State private var isDuePresented = false
    @State private var isFindPresented = false
    @State private var isAIAssistantPresented: Bool
    @State private var isCustomColorPresented = false
    @State private var isFontPresented = false
    @State private var isHighlightPalettePresented = false
    @State private var selectedHighlightHex = NoteHighlightPalette.defaultHex
    @State private var customHighlightColor = Color(hex: NoteHighlightPalette.defaultHex)
    @State private var searchQuery = ""
    @State private var formatRequest: NoteFormatRequest?
    @State private var taskInsertRequest: UUID?
    private let isDesignPreview: Bool

    private let palette = NotePalette.gradients

    init(
        note: DockNote,
        store: NotesStore,
        settings: AppSettings,
        closeAction: (() -> Void)? = nil,
        startsInAIMode: Bool = false,
        isDesignPreview: Bool = false
    ) {
        self.note = note
        self.store = store
        self.settings = settings
        self.closeAction = closeAction
        self.isDesignPreview = isDesignPreview
        _isAIAssistantPresented = State(initialValue: startsInAIMode)
    }

    var body: some View {
        let regions = NotePresentationPolicy.regions(
            searchVisible: isFindPresented,
            aiVisible: isAIAssistantPresented
        )
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                NoteSpine(note: note)
                    .overlay {
                        if store.desktopNoteIDs.contains(note.id) && !isDesignPreview {
                            DesktopWindowDragSurface(accessibilityIdentifier: "DockNotesDesktopDragRegion")
                                .help(settings.text(.moveDesktopNote))
                                .accessibilityLabel(settings.text(.moveDesktopNote))
                        }
                    }
                VStack(spacing: 0) {
                    toolbar
                    Divider().opacity(0.13)
                    ZStack(alignment: .topTrailing) {
                        if regions.contains(.editor) {
                            editor
                        }
                        if regions.contains(.searchOverlay) {
                            InNoteSearchBar(
                                query: $searchQuery,
                                matchCount: NoteSearchEngine.matchRanges(in: note.body, query: searchQuery).count,
                                settings: settings,
                                closeAction: closeSearch
                            )
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if regions.contains(.aiDrawer) {
                        Divider().opacity(0.12)
                        AIAssistantPanel(
                            note: note,
                            store: store,
                            settings: settings,
                            isDesignPreview: isDesignPreview,
                            closeAction: { isAIAssistantPresented = false }
                        )
                        .frame(height: 150)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    footer
                }
            }
            .background {
                RoundedRectangle(cornerRadius: DockNotesGlassMetrics.panelRadius, style: .continuous)
                    .fill(Color.clear)
                    .dockNotesGlassPanel(
                        radius: DockNotesGlassMetrics.panelRadius,
                        tint: Color(hex: note.colorHex).opacity(0.10),
                        fallbackOpacity: 0.24
                    )
                    .overlay {
                        NoteSurface(note: note)
                            .opacity(0.40)
                            .clipShape(RoundedRectangle(cornerRadius: DockNotesGlassMetrics.panelRadius, style: .continuous))
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: DockNotesGlassMetrics.panelRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.72), lineWidth: 0.8)
                            .allowsHitTesting(false)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: DockNotesGlassMetrics.panelRadius, style: .continuous))
            .shadow(color: Color(hex: note.colorHex).opacity(0.16), radius: 20, x: 0, y: 9)
            .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 6)
        }
        // The caller owns the card's dimensions. The edge editor proposes its
        // fixed 460 x 380 size, while a detached desktop window can grow well
        // beyond that default and the complete note surface follows it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.16), value: isAIAssistantPresented)
    }

    private var toolbar: some View {
        let deadline = note.dueDate.map {
            DeadlinePresentation.make(for: $0, language: settings.language)
        }
        let isDesktopNote = store.desktopNoteIDs.contains(note.id)
        return VStack(spacing: 0) {
            HStack(spacing: 7) {
            tinyButton(
                isDesktopNote ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                label: settings.text(isDesktopNote ? .returnToEdge : .openOnDesktop),
                isActive: isDesktopNote
            ) {
                store.presentOnDesktop(note.id)
            }

            if isDesktopNote && !isDesignPreview {
                DesktopWindowDragSurface()
                    .frame(width: 28, height: 24)
                    .overlay {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.46))
                            .allowsHitTesting(false)
                    }
                    .help(settings.text(.moveDesktopNote))
                    .accessibilityLabel(settings.text(.moveDesktopNote))
            }

            Spacer(minLength: 2)

            Button { isDuePresented.toggle() } label: {
                Label(
                    deadline?.toolbarLabel ?? settings.text(.due),
                    systemImage: deadline == nil ? "calendar.badge.plus" : "calendar.badge.clock"
                )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(deadline?.status == .overdue ? Color.red.opacity(0.86) : Color.black.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .dockNotesGlassCapsule(
                        tint: deadline?.status == .overdue ? Color.red.opacity(0.12) : Color.white.opacity(0.06),
                        interactive: true
                    )
            }
            .dockNotesChromeButton()
            .help(settings.text(.reminderHint))
            .popover(isPresented: $isDuePresented, arrowEdge: .top) {
                DueDatePopover(note: note, store: store, settings: settings)
            }

            saveStatusLabel
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize()

            tinyButton(
                note.isPinned ? "pin.fill" : "pin",
                label: settings.text(note.isPinned ? .unpin : .pin),
                isActive: note.isPinned
            ) {
                store.togglePinned(note.id)
            }
            tinyButton("checklist", label: settings.text(.task)) { taskInsertRequest = UUID() }
            tinyButton(
                "magnifyingglass",
                label: settings.text(.search),
                isActive: isFindPresented
            ) {
                if isFindPresented {
                    closeSearch()
                } else {
                    isFindPresented = true
                }
            }
            tinyButton(dictation.isRecording ? "stop.circle.fill" : "mic", label: settings.text(.dictate)) {
                let locale = settings.language == .english ? Locale(identifier: "en-US") : Locale(identifier: "zh-CN")
                let base = note.body
                dictation.toggle(locale: locale) { transcript in
                    store.updateBodyWithDictation(base: base, transcript: transcript, for: note.id)
                }
            }
            .foregroundStyle(dictation.isRecording ? Color.red : Color.black.opacity(0.46))
            tinyButton("rectangle.stack.fill", label: settings.text(.library)) {
                store.presentLibrary()
            }
            tinyButton(
                "sparkles",
                label: settings.text(.askAI),
                isActive: isAIAssistantPresented
            ) {
                isAIAssistantPresented.toggle()
            }
            }
            .frame(height: 34)
            .background {
                if isDesktopNote && !isDesignPreview {
                    DesktopWindowDragSurface(
                        accessibilityIdentifier: "DockNotesDesktopTopDragRegion"
                    )
                    .help(settings.text(.moveDesktopNote))
                    .accessibilityLabel(settings.text(.moveDesktopNote))
                }
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(note.gradient)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.white.opacity(0.65), lineWidth: 0.5))
                if isDesignPreview {
                    Text(note.title)
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("", text: Binding(
                        get: { store.note(id: note.id)?.title ?? note.title },
                        set: { store.updateTitle($0, for: note.id) }
                    ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .bold))
                        .accessibilityLabel("Note title")
                }
            }
            .frame(height: 29)
        }
        .padding(.horizontal, 14)
        .frame(height: 63)
        .background(Color.white.opacity(0.055))
    }

    @ViewBuilder
    private var saveStatusLabel: some View {
        switch store.saveState {
        case .saving:
            Text(settings.text(.saving))
        case .saved:
            Text(settings.text(.savedNow))
        case let .failed(message):
            Button {
                store.retrySave()
            } label: {
                Text(settings.text(.saveFailed))
                    .foregroundStyle(Color.red.opacity(0.82))
            }
            .buttonStyle(.plain)
            .help(message)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if isDesignPreview {
            VStack(alignment: .leading, spacing: 13) {
                Text("把今天最重要的事情收进一张安静的便签。")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("确认版本说明与发布清单")
                }
                HStack(spacing: 8) {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                    Text("同步任务时间与系统日历")
                }
                HStack(spacing: 8) {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                    Text("整理工作区中的零散灵感")
                }
                Spacer()
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.black.opacity(0.72))
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .accessibilityHidden(true)
        } else {
            StableTextEditor(
                text: store.note(id: note.id)?.body ?? note.body,
                rtfData: store.note(id: note.id)?.bodyRTF ?? note.bodyRTF,
                onChange: { body, rtfData in
                    store.updateRichBody(body, rtfData: rtfData, for: note.id)
                },
                fontStyle: note.fontStyle,
                fontSize: note.fontSize,
                searchQuery: isFindPresented ? searchQuery : "",
                searchTopInset: isFindPresented ? 46 : 4,
                formatRequest: $formatRequest,
                taskInsertRequest: $taskInsertRequest
            )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .accessibilityLabel(note.title)
        }
    }

    private func closeSearch() {
        isFindPresented = false
        searchQuery = ""
    }

    private var footer: some View {
        HStack(spacing: 6) {
            ForEach(palette, id: \.self) { gradient in
                Button { store.setGradient(gradient, for: note.id) } label: {
                    Circle()
                        .fill(gradient.swiftUIGradient)
                        .frame(width: 12, height: 12)
                        .overlay {
                            if note.colorHex.uppercased() == gradient.startHex,
                               note.gradientEndHex?.uppercased() == gradient.endHex {
                                Circle().stroke(Color.black.opacity(0.45), lineWidth: 1.5).padding(-2)
                            }
                        }
                }
                .dockNotesChromeButton()
                .accessibilityLabel("\(gradient.startHex) – \(gradient.endHex)")
            }

            Divider().frame(height: 17).padding(.horizontal, 2)
            Button { isCustomColorPresented.toggle() } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 10))
                    .frame(width: 23, height: 20)
            }
            .dockNotesChromeButton()
            .help(settings.text(.customColor))
            .accessibilityLabel(settings.text(.customColor))
            .popover(isPresented: $isCustomColorPresented, arrowEdge: .bottom) {
                CustomColorEditor(note: note, store: store, settings: settings)
            }

            Button { isFontPresented.toggle() } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 23, height: 20)
            }
            .dockNotesChromeButton()
            .help(settings.text(.font))
            .accessibilityLabel(settings.text(.font))
            .popover(isPresented: $isFontPresented, arrowEdge: .bottom) {
                FontEditorPopover(note: note, store: store, settings: settings)
            }

            formatButton("bold", label: settings.text(.bold), command: .bold)
            formatButton("underline", label: settings.text(.underline), command: .underline)
            formatButton("strikethrough", label: settings.text(.strikethrough), command: .strikethrough)
            highlightButton

            Spacer()
            footerIconButton("archivebox", label: settings.text(.archive)) {
                store.archive(
                    note.id,
                    obsidianDirectory: settings.obsidianVaultURL,
                    obsidianBackupEnabled: settings.obsidianBackupEnabled
                )
            }
            footerIconButton("trash", label: settings.text(.delete)) { store.delete(note.id) }
            footerIconButton("chevron.down", label: settings.text(.close)) {
                if let closeAction {
                    closeAction()
                } else {
                    store.collapseActive(keepDeckOpen: settings.keepDeckOpen)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 43)
        .background(Color.white.opacity(0.07))
    }

    private func formatButton(_ symbol: String, label: String, command: NoteFormatCommand) -> some View {
        Button {
            formatRequest = NoteFormatRequest(command: command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 19, height: 20)
                .contentShape(Rectangle())
        }
        .dockNotesChromeButton()
        .foregroundStyle(Color.black.opacity(0.62))
        .help(label)
        .accessibilityLabel(label)
    }

    private var highlightButton: some View {
        Button {
            isHighlightPalettePresented.toggle()
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "paintbrush")
                    .font(.system(size: 9, weight: .semibold))
                Capsule()
                    .fill(Color(hex: selectedHighlightHex))
                    .frame(width: 12, height: 2.5)
            }
            .frame(width: 19, height: 20)
            .contentShape(Rectangle())
        }
        .dockNotesChromeButton()
        .foregroundStyle(Color.black.opacity(0.62))
        .help(settings.text(.highlight))
        .accessibilityLabel(settings.text(.highlight))
        .popover(isPresented: $isHighlightPalettePresented, arrowEdge: .bottom) {
            highlightPalette
        }
    }

    private var highlightPalette: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(settings.text(.highlight))
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 9) {
                ForEach(NoteHighlightPalette.colors, id: \.self) { hex in
                    Button {
                        applyHighlight(hex)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 22, height: 22)
                            .overlay {
                                if selectedHighlightHex == hex {
                                    Circle()
                                        .stroke(Color.primary.opacity(0.58), lineWidth: 1.4)
                                        .padding(-2)
                                }
                            }
                            .overlay(Circle().stroke(Color.black.opacity(0.10), lineWidth: 0.6))
                    }
                    .dockNotesChromeButton()
                    .accessibilityLabel(hex)
                }
            }

            Divider()

            HStack(spacing: 8) {
                ColorPicker(settings.text(.customColor), selection: $customHighlightColor, supportsOpacity: false)
                    .font(.system(size: 11))

                Button(settings.text(.apply)) {
                    applyHighlight(NoteHighlightPalette.hex(from: customHighlightColor))
                }
                .controlSize(.small)
            }

            Button(settings.text(.clear)) {
                formatRequest = NoteFormatRequest(command: .highlight(nil))
                isHighlightPalettePresented = false
            }
            .controlSize(.small)
        }
        .padding(13)
        .frame(width: 230)
    }

    private func applyHighlight(_ hex: String) {
        selectedHighlightHex = hex
        customHighlightColor = Color(hex: hex)
        formatRequest = NoteFormatRequest(command: .highlight(hex))
        isHighlightPalettePresented = false
    }

    private func tinyButton(
        _ symbol: String,
        label: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .dockNotesGlassPanel(
                    radius: 8,
                    tint: isActive ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.035),
                    interactive: true,
                    fallbackOpacity: isActive ? 0.44 : 0.18
                )
                .contentShape(Rectangle())
        }
        .dockNotesChromeButton()
        .foregroundStyle(isActive ? Color.black.opacity(0.88) : Color.black.opacity(0.46))
        .help(label)
        .accessibilityLabel(label)
    }

    private func footerIconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 25)
                .contentShape(Rectangle())
        }
            .dockNotesChromeButton()
            .dockNotesGlassPanel(radius: 8, tint: Color.white.opacity(0.035), interactive: true, fallbackOpacity: 0.20)
            .help(label)
            .accessibilityLabel(label)
    }
}

enum NoteHighlightPalette {
    static let colors = [
        "#FFD966",
        "#FFB86B",
        "#FFA6BD",
        "#C9B6FF",
        "#93C5FD",
        "#9BE3B2"
    ]
    static let defaultHex = colors[0]

    static func appKitColor(hex: String) -> NSColor {
        let components = ColorInput.components(from: hex)
        return NSColor(
            red: CGFloat(components.red) / 255,
            green: CGFloat(components.green) / 255,
            blue: CGFloat(components.blue) / 255,
            alpha: 0.72
        )
    }

    static func hex(from color: Color) -> String {
        guard let resolved = NSColor(color).usingColorSpace(.sRGB) else { return defaultHex }
        let red = Int((min(max(resolved.redComponent, 0), 1) * 255).rounded())
        let green = Int((min(max(resolved.greenComponent, 0), 1) * 255).rounded())
        let blue = Int((min(max(resolved.blueComponent, 0), 1) * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

enum NoteHighlightFormatter {
    static func apply(hex: String?, to storage: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }
        if let hex {
            storage.addAttribute(
                .backgroundColor,
                value: NoteHighlightPalette.appKitColor(hex: hex),
                range: range
            )
        } else {
            storage.removeAttribute(.backgroundColor, range: range)
        }
    }
}

enum NoteFormatCommand: Equatable {
    case bold
    case underline
    case strikethrough
    case highlight(String?)
}

struct NoteFormatRequest: Equatable {
    let id = UUID()
    let command: NoteFormatCommand
}

struct StableTextEditor: NSViewRepresentable {
    let text: String
    let rtfData: Data?
    let onChange: (String, Data?) -> Void
    let fontStyle: NoteFontStyle
    let fontSize: Double
    let searchQuery: String
    let searchTopInset: CGFloat
    @Binding var formatRequest: NoteFormatRequest?
    @Binding var taskInsertRequest: UUID?

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = TaskCheckboxTextView(frame: .zero)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textColor = Self.editorTextColor
        textView.textContainerInset = NSSize(width: 2, height: searchTopInset)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true

        let baseFont = makeBaseFont()
        load(text: text, rtfData: rtfData, into: textView, baseFont: baseFont)
        context.coordinator.lastRTFData = rtfData
        context.coordinator.fontIdentity = FontIdentity(style: fontStyle, size: fontSize)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        let baseFont = makeBaseFont()

        if rtfData != coordinator.lastRTFData || (rtfData == nil && textView.string != text) {
            let selection = textView.selectedRange()
            load(text: text, rtfData: rtfData, into: textView, baseFont: baseFont)
            let maximum = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, maximum), length: 0))
            coordinator.lastRTFData = rtfData
        }

        let identity = FontIdentity(style: fontStyle, size: fontSize)
        if coordinator.fontIdentity != identity {
            applyBaseFont(baseFont, to: textView)
            coordinator.fontIdentity = identity
            coordinator.persist(textView, asynchronously: true)
        }

        if let request = formatRequest, coordinator.lastFormatRequestID != request.id {
            apply(request.command, to: textView, baseFont: baseFont)
            coordinator.lastFormatRequestID = request.id
            coordinator.persist(textView, asynchronously: true)
            DispatchQueue.main.async {
                if formatRequest?.id == request.id { formatRequest = nil }
            }
        }

        if let request = taskInsertRequest, coordinator.lastTaskInsertRequestID != request {
            coordinator.lastTaskInsertRequestID = request
            DispatchQueue.main.async { [weak textView] in
                textView.flatMap { $0 as? TaskCheckboxTextView }?.insertTaskAtSelection()
                if taskInsertRequest == request { taskInsertRequest = nil }
            }
        }

        applySearchHighlights(to: textView, coordinator: coordinator)
    }

    private static let editorTextColor = NSColor.black.withAlphaComponent(0.82)
    struct FontIdentity: Equatable {
        let style: NoteFontStyle
        let size: Double
    }

    private func makeBaseFont() -> NSFont {
        let size = CGFloat(min(max(fontSize, 11), 28))
        let system = NSFont.systemFont(ofSize: size)
        switch fontStyle {
        case .system:
            return system
        case .rounded:
            return system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        case .serif:
            return system.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        case .monospaced:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .handwriting:
            return NSFont(name: "Noteworthy", size: size) ?? system
        }
    }

    private func load(text: String, rtfData: Data?, into textView: NSTextView, baseFont: NSFont) {
        let attributed: NSAttributedString
        if let rtfData,
           let decoded = try? NSAttributedString(
               data: rtfData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ),
           decoded.string == text {
            attributed = decoded
        } else {
            attributed = NSAttributedString(
                string: text,
                attributes: [.font: baseFont, .foregroundColor: Self.editorTextColor]
            )
        }
        textView.textStorage?.setAttributedString(attributed)
        var typingAttributes = textView.typingAttributes
        typingAttributes[.font] = baseFont
        typingAttributes[.foregroundColor] = Self.editorTextColor
        textView.typingAttributes = typingAttributes
    }

    private func applyBaseFont(_ baseFont: NSFont, to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        var runs: [(NSRange, Bool)] = []
        storage.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let font = value as? NSFont
            runs.append((range, font?.fontDescriptor.symbolicTraits.contains(.bold) == true))
        }
        storage.beginEditing()
        for (range, isBold) in runs {
            let font = isBold
                ? NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                : baseFont
            storage.addAttribute(.font, value: font, range: range)
        }
        storage.endEditing()
        var typingAttributes = textView.typingAttributes
        let typingFont = typingAttributes[.font] as? NSFont
        typingAttributes[.font] = typingFont?.fontDescriptor.symbolicTraits.contains(.bold) == true
            ? NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            : baseFont
        textView.typingAttributes = typingAttributes
    }

    private func apply(_ command: NoteFormatCommand, to textView: NSTextView, baseFont: NSFont) {
        switch command {
        case .bold:
            toggleBold(in: textView, baseFont: baseFont)
        case .underline:
            toggleAttribute(.underlineStyle, activeValue: NSUnderlineStyle.single.rawValue, in: textView)
        case .strikethrough:
            toggleAttribute(.strikethroughStyle, activeValue: NSUnderlineStyle.single.rawValue, in: textView)
        case .highlight(let hex):
            applyHighlight(hex: hex, in: textView)
        }
    }

    private func applyHighlight(hex: String?, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        if selection.length == 0 {
            var attributes = textView.typingAttributes
            if let hex {
                attributes[.backgroundColor] = NoteHighlightPalette.appKitColor(hex: hex)
            } else {
                attributes.removeValue(forKey: .backgroundColor)
            }
            textView.typingAttributes = attributes
            return
        }

        NoteHighlightFormatter.apply(hex: hex, to: storage, range: selection)
    }

    private func toggleBold(in textView: NSTextView, baseFont: NSFont) {
        guard let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        if selection.length == 0 {
            var attributes = textView.typingAttributes
            let current = attributes[.font] as? NSFont ?? baseFont
            let isBold = current.fontDescriptor.symbolicTraits.contains(.bold)
            attributes[.font] = isBold
                ? NSFontManager.shared.convert(current, toNotHaveTrait: .boldFontMask)
                : NSFontManager.shared.convert(current, toHaveTrait: .boldFontMask)
            textView.typingAttributes = attributes
            return
        }

        var runs: [(NSRange, NSFont)] = []
        var allBold = true
        storage.enumerateAttribute(.font, in: selection) { value, range, _ in
            let font = value as? NSFont ?? baseFont
            if !font.fontDescriptor.symbolicTraits.contains(.bold) { allBold = false }
            runs.append((range, font))
        }
        storage.beginEditing()
        for (range, font) in runs {
            let replacement = allBold
                ? NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                : NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            storage.addAttribute(.font, value: replacement, range: range)
        }
        storage.endEditing()
    }

    private func toggleAttribute(_ key: NSAttributedString.Key, activeValue: Any, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        if selection.length == 0 {
            var attributes = textView.typingAttributes
            if Self.attributeIsActive(attributes[key], key: key) {
                attributes.removeValue(forKey: key)
            } else {
                attributes[key] = activeValue
            }
            textView.typingAttributes = attributes
            return
        }

        var allActive = true
        storage.enumerateAttribute(key, in: selection) { value, _, stop in
            if !Self.attributeIsActive(value, key: key) {
                allActive = false
                stop.pointee = true
            }
        }
        if allActive {
            storage.removeAttribute(key, range: selection)
        } else {
            storage.addAttribute(key, value: activeValue, range: selection)
        }
    }

    private static func attributeIsActive(_ value: Any?, key: NSAttributedString.Key) -> Bool {
        if key == .backgroundColor { return value is NSColor }
        guard let number = value as? NSNumber else { return false }
        return number.intValue != 0
    }

    private func applySearchHighlights(to textView: NSTextView, coordinator: Coordinator) {
        guard let layoutManager = textView.layoutManager else { return }
        let ranges = NoteSearchHighlighter.apply(to: layoutManager, text: textView.string, query: searchQuery)
        textView.textContainerInset = NSSize(width: 2, height: searchTopInset)
        if coordinator.lastSearchQuery != searchQuery {
            coordinator.lastSearchQuery = searchQuery
            if let first = ranges.first { textView.scrollRangeToVisible(first) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String, Data?) -> Void
        var lastRTFData: Data?
        var lastSearchQuery = ""
        var lastFormatRequestID: UUID?
        var lastTaskInsertRequestID: UUID?
        var fontIdentity: FontIdentity?

        init(onChange: @escaping (String, Data?) -> Void) {
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            persist(textView)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let result = OrderedListEditing.insertingReturn(
                in: textView.string,
                selectedRange: textView.selectedRange()
            )
            replaceTextPreservingAttributes(in: textView, with: result.text)
            textView.setSelectedRange(result.selectedRange)
            persist(textView)
            return true
        }

        func persist(_ textView: NSTextView, asynchronously: Bool = false) {
            let text = textView.string
            let range = NSRange(location: 0, length: (text as NSString).length)
            let data = try? textView.textStorage?.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            let flattenedData = data ?? nil
            lastRTFData = flattenedData
            let change = onChange
            if asynchronously {
                DispatchQueue.main.async { change(text, flattenedData) }
            } else {
                change(text, flattenedData)
            }
        }

        private func replaceTextPreservingAttributes(in textView: NSTextView, with replacement: String) {
            guard let storage = textView.textStorage else { return }
            let old = textView.string as NSString
            let new = replacement as NSString
            var prefix = 0
            while prefix < min(old.length, new.length), old.character(at: prefix) == new.character(at: prefix) {
                prefix += 1
            }
            var suffix = 0
            while suffix < old.length - prefix,
                  suffix < new.length - prefix,
                  old.character(at: old.length - suffix - 1) == new.character(at: new.length - suffix - 1) {
                suffix += 1
            }
            let oldRange = NSRange(location: prefix, length: old.length - prefix - suffix)
            let newRange = NSRange(location: prefix, length: new.length - prefix - suffix)
            let inserted = new.substring(with: newRange)
            var attributes = textView.typingAttributes
            if prefix > 0, storage.length > 0 {
                attributes.merge(storage.attributes(at: min(prefix - 1, storage.length - 1), effectiveRange: nil)) { current, _ in current }
            }
            storage.replaceCharacters(
                in: oldRange,
                with: NSAttributedString(string: inserted, attributes: attributes)
            )
        }
    }
}

final class TaskCheckboxTextView: NSTextView {
    func insertTaskAtSelection() {
        let replacement = "☐ "
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: replacement),
              let storage = textStorage else { return }
        storage.replaceCharacters(
            in: range,
            with: NSAttributedString(string: replacement, attributes: typingAttributes)
        )
        setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
        didChangeText()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        guard let markerRange = taskMarker(at: convert(event.locationInWindow, from: nil)),
              let storage = textStorage else {
            super.mouseDown(with: event)
            return
        }
        let current = (storage.string as NSString).substring(with: markerRange)
        let replacement = current == "☐" ? "☑" : "☐"
        guard shouldChangeText(in: markerRange, replacementString: replacement) else { return }
        let selection = selectedRange()
        storage.replaceCharacters(in: markerRange, with: replacement)
        let line = (storage.string as NSString).lineRange(for: markerRange)
        let contentStart = markerRange.location + 2
        let lineText = (storage.string as NSString).substring(with: line)
        let contentEnd = NSMaxRange(line) - (lineText.hasSuffix("\n") ? 1 : 0)
        if contentEnd > contentStart {
            let contentRange = NSRange(location: contentStart, length: contentEnd - contentStart)
            if replacement == "☑" {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            } else {
                storage.removeAttribute(.strikethroughStyle, range: contentRange)
            }
        }
        setSelectedRange(selection)
        didChangeText()
    }

    private func taskMarker(at point: NSPoint) -> NSRange? {
        guard let layoutManager, let textContainer else { return nil }
        let location = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(for: location, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer
        )
        guard glyphRect.contains(location) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let body = string as NSString
        guard index < body.length,
              index + 1 < body.length, body.character(at: index + 1) == 32 else { return nil }
        let marker = body.substring(with: NSRange(location: index, length: 1))
        guard marker == "☐" || marker == "☑" else { return nil }
        return NSRange(location: index, length: 1)
    }
}

private struct FontEditorPopover: View {
    let note: DockNote
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(settings.text(.font)).font(.system(size: 13, weight: .bold))
            Picker(settings.text(.fontFamily), selection: Binding(
                get: { note.fontStyle },
                set: { store.setFontStyle($0, for: note.id) }
            )) {
                Text(settings.text(.fontSystem)).tag(NoteFontStyle.system)
                Text(settings.text(.fontRounded)).tag(NoteFontStyle.rounded)
                Text(settings.text(.fontSerif)).tag(NoteFontStyle.serif)
                Text(settings.text(.fontMonospaced)).tag(NoteFontStyle.monospaced)
                Text(settings.text(.fontHandwriting)).tag(NoteFontStyle.handwriting)
            }
            .pickerStyle(.menu)

            HStack {
                Text(settings.text(.fontSize))
                Slider(value: Binding(
                    get: { note.fontSize },
                    set: { store.setFontSize($0, for: note.id) }
                ), in: 11...28, step: 1)
                Text("\(Int(note.fontSize))")
                    .font(.system(size: 11).monospacedDigit())
                    .frame(width: 24, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(width: 265)
    }
}

private struct NoteSpine: View {
    let note: DockNote

    var body: some View {
        ZStack(alignment: .trailing) {
            NoteSurface(note: note)
                .opacity(0.40)
                .brightness(-0.025)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.62), Color.white.opacity(0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 0.8)
            Text(note.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.74))
                .lineLimit(1)
                .frame(width: 160)
                .rotationEffect(.degrees(90))
        }
        .frame(width: 26)
    }
}

private struct NoteSurface: View {
    let note: DockNote

    var body: some View {
        ZStack {
            note.gradient
            LinearGradient(
                colors: [Color.white.opacity(0.24), Color.white.opacity(0.06), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if note.material == .paper {
                Image(nsImage: PaperTexture.image)
                    .resizable(resizingMode: .tile)
                    .opacity(0.18)
                    .blendMode(.multiply)
            }
        }
    }
}

private extension DockNote {
    var gradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: colorHex), Color(hex: gradientEndHex ?? colorHex)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private extension NoteGradient {
    var swiftUIGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: startHex), Color(hex: endHex)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct DueDatePopover: View {
    let note: DockNote
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    @State private var timeText: String
    @State private var showsInvalidTime = false
    @FocusState private var isTimeFieldFocused: Bool

    init(note: DockNote, store: NotesStore, settings: AppSettings) {
        self.note = note
        self.store = store
        self.settings = settings
        let initialDate = note.dueDate ?? Date().addingTimeInterval(3_600)
        _timeText = State(initialValue: ReminderTimeInput.format(initialDate))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.text(.dueDate)).font(.system(size: 13, weight: .bold))
            DatePicker(
                "",
                selection: Binding(
                    get: { note.dueDate ?? Date().addingTimeInterval(3_600) },
                    set: { date in
                        timeText = ReminderTimeInput.format(date)
                        showsInvalidTime = false
                        store.setDueDate(date, for: note.id, language: settings.language)
                    }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 5) {
                Text(settings.text(.timeInput))
                    .font(.system(size: 11, weight: .semibold))
                HStack(spacing: 8) {
                    TextField(settings.text(.timeInputHint), text: $timeText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12).monospacedDigit())
                        .focused($isTimeFieldFocused)
                        .onSubmit(applyManualTime)
                        .onChange(of: timeText) { _, _ in showsInvalidTime = false }
                    Button(settings.text(.apply), action: applyManualTime)
                }
                Text(showsInvalidTime ? settings.text(.invalidTime) : settings.text(.timeInputHint))
                    .font(.system(size: 9.5))
                    .foregroundStyle(showsInvalidTime ? Color.red : Color.secondary)
            }
            Text(settings.text(.reminderHint))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(settings.text(.clear)) {
                    store.setDueDate(nil, for: note.id, language: settings.language)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
        .dockNotesGlassPanel(radius: 16, tint: Color.white.opacity(0.08))
        .onChange(of: note.dueDate) { _, date in
            guard !isTimeFieldFocused, let date else { return }
            timeText = ReminderTimeInput.format(date)
            showsInvalidTime = false
        }
    }

    private func applyManualTime() {
        let baseDate = note.dueDate ?? Date().addingTimeInterval(3_600)
        guard let date = ReminderTimeInput.parse(timeText, on: baseDate) else {
            showsInvalidTime = true
            return
        }
        timeText = ReminderTimeInput.format(date)
        showsInvalidTime = false
        store.setDueDate(date, for: note.id, language: settings.language)
    }
}

private struct InNoteSearchBar: View {
    @Binding var query: String
    let matchCount: Int
    @ObservedObject var settings: AppSettings
    let closeAction: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(settings.text(.findInNote), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($isFocused)
            Text(String(format: settings.text(.matches), matchCount))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
            Button(action: closeAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .dockNotesChromeButton()
            .help(settings.text(.close))
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(width: 270, height: 32)
        .dockNotesGlassPanel(radius: 11, tint: Color.white.opacity(0.08), interactive: true)
        .shadow(color: Color.black.opacity(0.10), radius: 8, y: 3)
        .onAppear { isFocused = true }
    }
}

private struct AIAssistantPanel: View {
    let note: DockNote
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    var isDesignPreview = false
    let closeAction: () -> Void
    @State private var prompt = ""
    @State private var response = ""
    @State private var errorMessage = ""
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label(settings.text(.askAI), systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if !settings.aiModel.isEmpty {
                    Text(settings.aiModel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button(action: closeAction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .dockNotesChromeButton()
                .help(settings.text(.close))
            }
            .padding(.horizontal, 14)
            .frame(height: 35)

            Divider().opacity(0.12)

            if settings.isAIConfigured || isDesignPreview {
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        if isLoading {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(settings.text(.aiResponse))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        } else if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if !response.isEmpty {
                            ScrollView {
                                Text(response)
                                    .font(.system(size: 12))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(settings.text(.aiPrompt))
                                    .font(.system(size: 13, weight: .medium))
                                Text(note.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    if !response.isEmpty && !isLoading {
                        HStack {
                            Button(settings.text(.copy)) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(response, forType: .string)
                            }
                            .dockNotesChromeButton()
                            Spacer()
                            Button(settings.text(.appendToNote)) {
                                let currentBody = store.note(id: note.id)?.body ?? note.body
                                let separator = currentBody.isEmpty || currentBody.hasSuffix("\n") ? "" : "\n\n"
                                store.appendBody(separator + response, for: note.id)
                            }
                            .dockNotesChromeButton()
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .bottom, spacing: 9) {
                        ZStack(alignment: .topLeading) {
                            if isDesignPreview {
                                Text(settings.text(.aiPrompt))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 11)
                            } else {
                                TextEditor(text: $prompt)
                                    .font(.system(size: 12))
                                    .scrollContentBackground(.hidden)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 3)
                                    .frame(minHeight: 46, maxHeight: 72)
                            }
                            if prompt.isEmpty {
                                Text(isDesignPreview ? "" : settings.text(.aiPrompt))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 11)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(minHeight: 46, maxHeight: 72, alignment: .topLeading)
                        .dockNotesGlassPanel(radius: 13, tint: Color.white.opacity(0.07), interactive: true)

                        Button(action: sendRequest) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 28, height: 28)
                                .background(Color.accentColor.opacity(0.82), in: Circle())
                                .dockNotesGlass(in: Circle(), tint: Color.accentColor.opacity(0.22), interactive: true)
                                .contentShape(Circle())
                        }
                        .dockNotesChromeButton()
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        .opacity(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading ? 0.35 : 1)
                        .help(settings.text(.send))
                    }
                }
                .padding(14)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(settings.text(.aiNotConfigured))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(settings.text(.openAISettings)) {
                        store.collapseActive(keepDeckOpen: settings.keepDeckOpen)
                        store.presentSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dockNotesGlassPanel(
            radius: 16,
            tint: Color(hex: note.gradientEndHex ?? note.colorHex).opacity(0.08),
            clear: true,
            fallbackOpacity: 0.18
        )
    }

    private func sendRequest() {
        let requestPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestPrompt.isEmpty else { return }
        isLoading = true
        response = ""
        errorMessage = ""
        let configuration = AIConfiguration(
            provider: settings.aiProvider,
            endpoint: settings.aiEndpoint,
            model: settings.aiModel,
            apiKey: settings.aiAPIKey
        )
        Task {
            do {
                response = try await AIClient.ask(
                    configuration: configuration,
                    note: store.note(id: note.id) ?? note,
                    prompt: requestPrompt,
                    language: settings.language
                )
            } catch {
                if let aiError = error as? AIClientError {
                    errorMessage = aiError.userMessage(language: settings.language)
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }
}

private struct CustomColorEditor: View {
    enum InputMode: String, CaseIterable { case rgb = "RGB"; case hex = "HEX" }

    let note: DockNote
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    @State private var mode: InputMode = .rgb
    @State private var red: String
    @State private var green: String
    @State private var blue: String
    @State private var hex: String
    @State private var endRed: String
    @State private var endGreen: String
    @State private var endBlue: String
    @State private var endHex: String
    @State private var isGradient: Bool
    @State private var showsError = false

    init(note: DockNote, store: NotesStore, settings: AppSettings) {
        self.note = note
        self.store = store
        self.settings = settings
        let components = ColorInput.components(from: note.colorHex)
        _red = State(initialValue: String(components.red))
        _green = State(initialValue: String(components.green))
        _blue = State(initialValue: String(components.blue))
        _hex = State(initialValue: note.colorHex)
        let endColor = note.gradientEndHex ?? note.colorHex
        let endComponents = ColorInput.components(from: endColor)
        _endRed = State(initialValue: String(endComponents.red))
        _endGreen = State(initialValue: String(endComponents.green))
        _endBlue = State(initialValue: String(endComponents.blue))
        _endHex = State(initialValue: endColor)
        _isGradient = State(initialValue: endColor.uppercased() != note.colorHex.uppercased())
    }

    private var candidate: String? {
        mode == .rgb
            ? ColorInput.hex(red: red, green: green, blue: blue)
            : ColorInput.normalizedHex(hex)
    }

    private var endCandidate: String? {
        mode == .rgb
            ? ColorInput.hex(red: endRed, green: endGreen, blue: endBlue)
            : ColorInput.normalizedHex(endHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(settings.text(.customColor)).font(.system(size: 13, weight: .bold))
                Spacer()
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: candidate ?? note.colorHex),
                                Color(hex: isGradient ? (endCandidate ?? note.gradientEndHex ?? note.colorHex) : (candidate ?? note.colorHex))
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.15), lineWidth: 0.7))
            }
            Picker("", selection: $mode) {
                ForEach(InputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Picker("", selection: $isGradient) {
                Text(settings.text(.solidColor)).tag(false)
                Text(settings.text(.gradient)).tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Picker(
                settings.text(.material),
                selection: Binding(
                    get: { note.material },
                    set: { store.setMaterial($0, for: note.id) }
                )
            ) {
                Text(settings.text(.plain)).tag(NoteMaterial.plain)
                Text(settings.text(.paper)).tag(NoteMaterial.paper)
            }
            .pickerStyle(.segmented)

            if mode == .rgb {
                rgbRow(settings.text(.startColor), red: $red, green: $green, blue: $blue)
                if isGradient {
                    rgbRow(settings.text(.endColor), red: $endRed, green: $endGreen, blue: $endBlue)
                }
            } else {
                hexRow(settings.text(.startColor), text: $hex)
                if isGradient { hexRow(settings.text(.endColor), text: $endHex) }
            }

            if showsError {
                Text(settings.text(.invalidColor))
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(settings.text(.apply)) {
                    guard let candidate, !isGradient || endCandidate != nil else {
                        showsError = true
                        return
                    }
                    showsError = false
                    if isGradient, let endCandidate {
                        store.setGradient(NoteGradient(startHex: candidate, endHex: endCandidate), for: note.id)
                    } else {
                        store.setColor(candidate, for: note.id)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 310)
    }

    private func rgbRow(_ label: String, red: Binding<String>, green: Binding<String>, blue: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 7) {
                colorField("R", text: red)
                colorField("G", text: green)
                colorField("B", text: blue)
            }
        }
    }

    private func hexRow(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            TextField("#RRGGBB", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func colorField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .semibold))
            TextField("0", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
        }
    }
}

struct TaskCenterView: View {
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    @State private var section: TaskCenterSection = .inbox
    @State private var searchQuery = ""

    private var counts: TaskCenterCounts {
        TaskCenterQuery.counts(in: store.notes)
    }

    private var displayedItems: [ChecklistItem] {
        TaskCenterQuery.apply(to: store.notes, section: section, query: searchQuery)
    }

    private var weekDayGroups: [TaskPlanDayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: displayedItems) { item in
            calendar.startOfDay(for: item.dueDate ?? .distantFuture)
        }
        return grouped.keys.sorted().map { day in
            TaskPlanDayGroup(day: day, items: grouped[day] ?? [])
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                summary
                if displayedItems.isEmpty {
                    ContentUnavailableView(
                        settings.text(.noTasks),
                        systemImage: section == .completed ? "checkmark.circle" : "checklist",
                        description: Text(searchQuery.isEmpty ? sectionTitle(section) : settings.text(.searchTasks))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            if section == .week {
                                ForEach(weekDayGroups) { group in
                                    HStack(spacing: 8) {
                                        Text(Calendar.current.isDateInToday(group.day)
                                            ? settings.text(.today)
                                            : group.day.formatted(.dateTime.weekday(.wide).month().day()))
                                            .font(.system(size: 11, weight: .bold))
                                        Text("\(group.items.count)")
                                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 3)
                                    .padding(.top, 8)
                                    ForEach(group.items) { item in
                                        TaskCenterRow(item: item, store: store, settings: settings)
                                    }
                                }
                            } else {
                                ForEach(displayedItems) { item in
                                    TaskCenterRow(item: item, store: store, settings: settings)
                                }
                            }
                        }
                        .padding(18)
                    }
                }
            }
        }
        .frame(width: 860, height: 560)
        .background(DockNotesGlassCanvas(accent: Color(hex: NotePalette.gradients[0].startHex)))
        .background {
            if !DockNotesGlassRuntime.isStaticRendering {
                DockNotesGlassWindowChrome().frame(width: 0, height: 0)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(NotePalette.gradients[0].swiftUIGradient)
                    Image(systemName: "checklist")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.64))
                }
                .frame(width: 34, height: 34)
                Text(settings.text(.taskCenter))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 18)

            VStack(spacing: 6) {
                sectionButton(.inbox, symbol: "tray.full")
                sectionButton(.today, symbol: "sun.max")
                sectionButton(.week, symbol: "calendar.badge.clock")
                sectionButton(.upcoming, symbol: "calendar")
                sectionButton(.overdue, symbol: "exclamationmark.circle")
                sectionButton(.completed, symbol: "checkmark.circle")
            }
            .padding(.horizontal, 10)
            Spacer()
            Button {
                store.presentLibrary()
            } label: {
                Label(settings.text(.library), systemImage: "rectangle.stack.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .dockNotesGlassPanel(radius: 10, tint: Color.white.opacity(0.05), interactive: true)
            }
            .dockNotesChromeButton()
            .padding(10)
        }
        .frame(width: 184)
        .background(Color.white.opacity(0.09))
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sectionTitle(section))
                    .font(.system(size: 18, weight: .semibold))
                Text("\(displayedItems.count)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(settings.text(.searchTasks), text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .dockNotesChromeButton()
                    .accessibilityLabel(settings.text(.clear))
                }
            }
            .padding(.horizontal, 11)
            .frame(width: 280, height: 34)
            .dockNotesGlassPanel(radius: 10, tint: Color.white.opacity(0.05), interactive: true)
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
    }

    private var summary: some View {
        HStack(spacing: 8) {
            summaryPill(.today, color: Color(hex: NotePalette.gradients[0].startHex))
            summaryPill(.week, color: Color(hex: NotePalette.gradients[1].startHex))
            summaryPill(.overdue, color: Color(hex: NotePalette.gradients[4].endHex))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func sectionButton(_ value: TaskCenterSection, symbol: String) -> some View {
        Button { section = value } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text(sectionTitle(value))
                    .font(.system(size: 12, weight: section == value ? .bold : .medium))
                Spacer()
                Text("\(counts[value])")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(section == value ? Color.primary : Color.secondary)
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(
                section == value ? Color.accentColor.opacity(0.13) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .dockNotesGlassPanel(
                radius: 10,
                tint: section == value ? Color.accentColor.opacity(0.10) : Color.white.opacity(0.02),
                interactive: true,
                fallbackOpacity: 0.12
            )
        }
        .dockNotesChromeButton()
    }

    private func summaryPill(_ value: TaskCenterSection, color: Color) -> some View {
        Button { section = value } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(sectionTitle(value))
                Text("\(counts[value])").monospacedDigit()
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 27)
            .dockNotesGlassCapsule(tint: color.opacity(0.08), interactive: true, fallbackOpacity: 0.16)
        }
        .dockNotesChromeButton()
    }

    private func sectionTitle(_ value: TaskCenterSection) -> String {
        switch value {
        case .inbox: settings.text(.taskInbox)
        case .today: settings.text(.today)
        case .week: settings.text(.weekPlan)
        case .upcoming: settings.text(.upcoming)
        case .overdue: settings.text(.overdue)
        case .completed: settings.text(.completed)
        }
    }
}

private struct TaskPlanDayGroup: Identifiable {
    let day: Date
    let items: [ChecklistItem]
    var id: Date { day }
}

private struct TaskCenterRow: View {
    let item: ChecklistItem
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    @State private var duePopoverPresented = false
    @State private var dueDraft = Date().addingTimeInterval(3_600)
    @State private var repeatEnabledDraft = false
    @State private var recurrenceFrequencyDraft: TaskRecurrenceFrequency = .daily
    @State private var recurrenceIntervalDraft = 1

    private var deadline: DeadlinePresentation? {
        item.dueDate.map { DeadlinePresentation.make(for: $0, language: settings.language) }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if !item.isProjectedOccurrence {
                    store.setChecklistItemCompleted(item.id, completed: !item.isCompleted)
                }
            } label: {
                Image(systemName: item.isProjectedOccurrence
                    ? "circle.dashed"
                    : (item.isCompleted ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(item.isCompleted ? Color.green : Color.secondary)
                    .contentShape(Rectangle())
            }
            .dockNotesChromeButton()
            .accessibilityIdentifier(
                "DockNotesTaskCheckbox-\(item.noteID.uuidString)-\(item.id.markerUTF16Offset)"
            )
            .accessibilityLabel(item.isCompleted ? settings.text(.incomplete) : settings.text(.completed))
            .disabled(item.isProjectedOccurrence)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.text.isEmpty ? settings.text(.addTask) : item.text)
                    .font(.system(size: 13, weight: .medium))
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                    .lineLimit(2)
                Button {
                    store.openFromTaskCenter(item.noteID)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "note.text")
                        Text(item.noteTitle.isEmpty ? settings.text(.newNote) : item.noteTitle)
                            .lineLimit(1)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .dockNotesChromeButton()
                .help(settings.text(.sourceNote))
                if let rule = item.recurrenceRule {
                    HStack(spacing: 5) {
                        Image(systemName: "repeat")
                        Text(recurrenceLabel(rule))
                        if item.isProjectedOccurrence {
                            Text("· \(settings.text(.projectedOccurrence))")
                        }
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Button {
                prepareScheduleDraft()
                duePopoverPresented = true
            } label: {
                Label(
                    deadline?.toolbarLabel ?? settings.text(.unscheduled),
                    systemImage: deadline?.status == .overdue ? "exclamationmark.circle" : "calendar"
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(deadline?.status == .overdue ? Color.red.opacity(0.78) : Color.secondary)
                .padding(.horizontal, 9)
                .frame(height: 29)
                .background(Color.primary.opacity(0.045), in: Capsule())
            }
            .dockNotesChromeButton()
            .popover(isPresented: $duePopoverPresented, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(settings.text(.dueDate))
                        .font(.system(size: 13, weight: .bold))
                    DatePicker(
                        "",
                        selection: $dueDraft,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    Divider()
                    Toggle(settings.text(.repeatTask), isOn: $repeatEnabledDraft)
                        .toggleStyle(.switch)
                    if repeatEnabledDraft {
                        Picker("", selection: $recurrenceFrequencyDraft) {
                            ForEach(TaskRecurrenceFrequency.allCases, id: \.self) { frequency in
                                Text(recurrenceTitle(frequency)).tag(frequency)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        HStack {
                            Text(settings.text(.repeatInterval))
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Stepper(
                                "\(recurrenceIntervalDraft)",
                                value: $recurrenceIntervalDraft,
                                in: 1...365
                            )
                            .fixedSize()
                        }
                    }
                    if item.recurrenceRule != nil {
                        Divider()
                        HStack {
                            Button(settings.text(.skipThisOccurrence)) {
                                store.skipTaskOccurrence(item.id)
                                duePopoverPresented = false
                            }
                            Button(settings.text(.stopRepeating), role: .destructive) {
                                store.stopTaskRecurrence(item.id)
                                duePopoverPresented = false
                            }
                            Spacer()
                        }
                    }
                    HStack {
                        if item.dueDate != nil && item.recurrenceRule == nil {
                            Button(settings.text(.clear)) {
                                store.setChecklistItemDueDate(item.id, date: nil)
                                duePopoverPresented = false
                            }
                        }
                        Spacer()
                        if item.recurrenceRule != nil {
                            Button(settings.text(.onlyThisOccurrence)) {
                                store.rescheduleTaskOccurrence(item.id, to: dueDraft)
                                duePopoverPresented = false
                            }
                        }
                        Button(item.recurrenceRule == nil
                            ? settings.text(.apply)
                            : settings.text(.entireSeries)) {
                            applyScheduleDraft()
                            duePopoverPresented = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(14)
                .frame(width: 360)
            }

            Button {
                store.openFromTaskCenter(item.noteID)
            } label: {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            }
            .dockNotesChromeButton()
            .accessibilityLabel(settings.text(.openNote))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .dockNotesGlassPanel(radius: 13, tint: Color.white.opacity(0.04), interactive: true)
    }

    private func prepareScheduleDraft() {
        dueDraft = item.dueDate ?? Date().addingTimeInterval(3_600)
        repeatEnabledDraft = item.recurrenceRule != nil
        recurrenceFrequencyDraft = item.recurrenceRule?.frequency ?? .daily
        recurrenceIntervalDraft = item.recurrenceRule?.interval ?? 1
    }

    private func applyScheduleDraft() {
        guard repeatEnabledDraft else {
            if item.recurrenceRule != nil {
                _ = store.stopTaskRecurrence(item.id)
            }
            _ = store.setChecklistItemDueDate(item.id, date: dueDraft)
            return
        }
        let rule = TaskRecurrenceRule(
            frequency: recurrenceFrequencyDraft,
            interval: recurrenceIntervalDraft
        )
        if item.recurrenceRule == nil {
            _ = store.setTaskRecurrence(item.id, rule: rule, startingAt: dueDraft)
        } else {
            _ = store.updateTaskRecurrenceSeries(item.id, rule: rule, startingAt: dueDraft)
        }
    }

    private func recurrenceTitle(_ frequency: TaskRecurrenceFrequency) -> String {
        switch frequency {
        case .daily: settings.text(.repeatDaily)
        case .weekdays: settings.text(.repeatWeekdays)
        case .weekly: settings.text(.repeatWeekly)
        case .monthly: settings.text(.repeatMonthly)
        }
    }

    private func recurrenceLabel(_ rule: TaskRecurrenceRule) -> String {
        let title = recurrenceTitle(rule.frequency)
        return rule.interval == 1 ? title : "\(title) × \(rule.interval)"
    }
}

struct NotesLibraryView: View {
    private enum Collection: String, CaseIterable { case all, archived }
    private enum WorkspaceScope: String, CaseIterable { case all, current }

    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    @State private var collection: Collection = .all
    @State private var workspaceScope: WorkspaceScope = .all
    @State private var workspaceFilterID: NoteWorkspace.ID?
    @State private var searchQuery = ""
    @State private var filter: LibraryFilter = .all
    @State private var sort: LibrarySort = .modified
    @State private var selectedNoteID: DockNote.ID?
    @State private var selectedNoteIDs: Set<DockNote.ID> = []
    @State private var isWorkspaceManagerPresented = false
    @State private var transferMessage: String?
    @State private var transferSucceeded = true

    private var sourceNotes: [DockNote] {
        let collectionNotes = collection == .all ? store.notes : store.archivedNotes
        let scopedNotes = workspaceScope == .current
            ? collectionNotes.filter { $0.workspaceID == store.activeWorkspaceID }
            : collectionNotes
        guard let workspaceFilterID, workspaceScope == .all else { return scopedNotes }
        return scopedNotes.filter { $0.workspaceID == workspaceFilterID }
    }

    private var displayedNotes: [DockNote] {
        LibraryQuery.apply(to: sourceNotes, query: searchQuery, filter: filter, sort: sort)
    }

    private var selectedNote: DockNote? {
        displayedNotes.first(where: { $0.id == selectedNoteID }) ?? displayedNotes.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Label(settings.text(.library), systemImage: "rectangle.stack.fill")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    store.presentTaskCenter()
                } label: {
                    Label(settings.text(.taskCenter), systemImage: "checklist")
                }
                Button(action: importNoteFiles) {
                    Label(settings.text(.importNotes), systemImage: "square.and.arrow.down")
                }
                Menu {
                    Button(settings.text(.exportMarkdown)) { exportDisplayedNotes(as: .markdown) }
                    Button(settings.text(.exportText)) { exportDisplayedNotes(as: .text) }
                } label: {
                    Label(settings.text(.exportNotes), systemImage: "square.and.arrow.up")
                }
                .disabled(displayedNotes.isEmpty)
                if !selectedNoteIDs.isEmpty {
                    Menu {
                        ForEach(store.workspaces) { workspace in
                            Button(workspace.name) {
                                store.moveNotes(selectedNoteIDs, toWorkspace: workspace.id)
                                selectedNoteIDs.removeAll()
                            }
                        }
                    } label: {
                        Label("\(settings.text(.moveToWorkspace)) · \(selectedNoteIDs.count)", systemImage: "folder")
                    }
                }
                Picker("", selection: $collection) {
                    Text("\(settings.text(.allNotes))  \(store.notes.count)").tag(Collection.all)
                    Text("\(settings.text(.archivedNotes))  \(store.archivedNotes.count)").tag(Collection.archived)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
                Button {
                    store.addNote(language: settings.language)
                    store.isLibraryPresented = false
                } label: {
                    Label(settings.text(.newNote), systemImage: "plus")
                }
            }
            .padding(.horizontal, 22)
            .frame(height: 64)
            .dockNotesGlassPanel(radius: 0, tint: Color.white.opacity(0.05))

            Divider()

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(settings.text(.searchLibrary), text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchQuery.isEmpty {
                    Text("\(displayedNotes.count)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                    .dockNotesChromeButton()
                    .accessibilityLabel(settings.text(.clear))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .dockNotesGlassPanel(radius: 11, tint: Color.white.opacity(0.05), interactive: true)
            .padding(.horizontal, 18)
            .padding(.top, 10)

            HStack(spacing: 10) {
                Picker("", selection: $workspaceScope) {
                    Text(settings.text(.allWorkspaces)).tag(WorkspaceScope.all)
                    Text(settings.text(.currentWorkspace)).tag(WorkspaceScope.current)
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                Picker(settings.text(.workspaces), selection: $workspaceFilterID) {
                    Text(settings.text(.allWorkspaces)).tag(Optional<NoteWorkspace.ID>.none)
                    ForEach(store.workspaces) { workspace in
                        Text(workspace.name).tag(Optional(workspace.id))
                    }
                }
                .frame(width: 170)
                .disabled(workspaceScope == .current)
                Picker(settings.text(.filter), selection: $filter) {
                    Text(settings.text(.allNotes)).tag(LibraryFilter.all)
                    Text(settings.text(.pin)).tag(LibraryFilter.pinned)
                    Text(settings.text(.incomplete)).tag(LibraryFilter.incomplete)
                    Text(settings.text(.overdue)).tag(LibraryFilter.overdue)
                }
                Picker(settings.text(.sort), selection: $sort) {
                    Text(settings.text(.recentModified)).tag(LibrarySort.modified)
                    Text(settings.text(.dueFirst)).tag(LibrarySort.due)
                    Text(settings.text(.newestCreated)).tag(LibrarySort.created)
                }
                Spacer()
                Button {
                    isWorkspaceManagerPresented = true
                } label: {
                    Label(settings.text(.manageWorkspaces), systemImage: "slider.horizontal.3")
                }
            }
            .labelsHidden()
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            if displayedNotes.isEmpty {
                ContentUnavailableView(
                    searchQuery.isEmpty ? settings.text(.noArchivedNotes) : settings.text(.noSearchResults),
                    systemImage: searchQuery.isEmpty ? "archivebox" : "magnifyingglass",
                    description: Text(searchQuery.isEmpty ? settings.text(.archivedNotes) : settings.text(.searchLibrary))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                        ForEach(displayedNotes) { note in
                            HStack(spacing: 13) {
                                Button {
                                    if selectedNoteIDs.contains(note.id) {
                                        selectedNoteIDs.remove(note.id)
                                    } else {
                                        selectedNoteIDs.insert(note.id)
                                    }
                                } label: {
                                    Image(systemName: selectedNoteIDs.contains(note.id)
                                        ? "checkmark.circle.fill"
                                        : "circle")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(selectedNoteIDs.contains(note.id) ? Color.accentColor : Color.secondary)
                                }
                                .dockNotesChromeButton()
                                .accessibilityLabel(settings.text(.selectedNotes))
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(note.gradient)
                                    .frame(width: 9, height: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 7) {
                                        Text(note.title.isEmpty ? settings.text(.newNote) : note.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .lineLimit(1)
                                        if !searchQuery.isEmpty {
                                            Text(settings.text(NoteSearchEngine.matchesTitle(note, query: searchQuery) ? .titleMatch : .contentMatch))
                                                .font(.system(size: 8, weight: .semibold))
                                                .foregroundStyle(NoteSearchEngine.matchesTitle(note, query: searchQuery) ? Color.accentColor : Color.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.white.opacity(0.58), in: Capsule())
                                        }
                                    }
                                    Text(note.body.replacingOccurrences(of: "\n", with: " "))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    if let workspaceID = note.workspaceID,
                                       let workspace = store.workspace(id: workspaceID) {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Color(hex: workspace.colorHex))
                                                .frame(width: 6, height: 6)
                                            Text(workspace.name)
                                                .lineLimit(1)
                                        }
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                Text(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                if collection == .archived {
                                    libraryActionButton(
                                        "arrow.uturn.backward",
                                        label: settings.text(.restore)
                                    ) {
                                        store.restoreArchived(note.id, language: settings.language)
                                    }
                                    libraryActionButton(
                                        "trash",
                                        label: settings.text(.delete),
                                        destructive: true
                                    ) {
                                        store.delete(note.id)
                                    }
                                } else {
                                    libraryActionButton(
                                        "arrow.up.left.and.arrow.down.right",
                                        label: settings.text(.allNotes)
                                    ) {
                                        store.openFromLibrary(note.id)
                                    }
                                    libraryActionButton(
                                        "archivebox",
                                        label: settings.text(.archive)
                                    ) {
                                        store.archive(
                                            note.id,
                                            obsidianDirectory: settings.obsidianVaultURL,
                                            obsidianBackupEnabled: settings.obsidianBackupEnabled
                                        )
                                    }
                                    libraryActionButton(
                                        "trash",
                                        label: settings.text(.delete),
                                        destructive: true
                                    ) {
                                        store.delete(note.id)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 64)
                            .background(
                                selectedNote?.id == note.id
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.white.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                            .dockNotesGlassPanel(
                                radius: 12,
                                tint: selectedNote?.id == note.id
                                    ? Color.accentColor.opacity(0.10)
                                    : Color.white.opacity(0.025),
                                interactive: true,
                                fallbackOpacity: 0.16
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .onTapGesture(count: 2) {
                                guard collection == .all else { return }
                                store.openFromLibrary(note.id)
                            }
                            .onTapGesture { selectedNoteID = note.id }
                        }
                    }
                    .padding(16)
                    }
                    .frame(minWidth: 540)
                    Divider()
                    libraryPreview
                        .frame(width: 270)
                }
                .id(collection)
            }
        }
        .frame(width: 860, height: 560, alignment: .top)
        .background(DockNotesGlassCanvas(accent: Color(hex: NotePalette.gradients[2].startHex)))
        .background {
            if !DockNotesGlassRuntime.isStaticRendering {
                DockNotesGlassWindowChrome().frame(width: 0, height: 0)
            }
        }
        .onChange(of: collection) { _, _ in
            selectedNoteID = nil
            selectedNoteIDs.removeAll()
            filter = .all
        }
        .onChange(of: workspaceScope) { _, _ in
            workspaceFilterID = nil
            selectedNoteID = nil
            selectedNoteIDs.removeAll()
        }
        .onChange(of: workspaceFilterID) { _, _ in
            selectedNoteID = nil
            selectedNoteIDs.removeAll()
        }
        .sheet(isPresented: $isWorkspaceManagerPresented) {
            WorkspaceManagementView(store: store, settings: settings)
        }
        .alert(
            settings.text(transferSucceeded ? .transferComplete : .transferFailed),
            isPresented: Binding(
                get: { transferMessage != nil },
                set: { if !$0 { transferMessage = nil } }
            )
        ) {
            Button("OK") { transferMessage = nil }
        } message: {
            Text(transferMessage ?? "")
        }
    }

    @ViewBuilder
    private var libraryPreview: some View {
        if let note = selectedNote {
            VStack(alignment: .leading, spacing: 12) {
                Text(settings.text(.preview))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 8)
                    .fill(note.gradient)
                    .frame(height: 8)
                Text(note.title.isEmpty ? settings.text(.newNote) : note.title)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(2)
                ScrollView {
                    Text(note.body.isEmpty ? "—" : note.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                if collection == .all {
                    Button(settings.text(.openNote)) { store.openFromLibrary(note.id) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .dockNotesGlassPanel(radius: 16, tint: Color(hex: note.colorHex).opacity(0.06))
            .padding(10)
        }
    }

    private func libraryActionButton(
        _ symbol: String,
        label: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(destructive ? Color.red.opacity(0.82) : Color.secondary)
                .frame(width: 26, height: 26)
                .dockNotesGlassPanel(
                    radius: 8,
                    tint: destructive ? Color.red.opacity(0.06) : Color.white.opacity(0.03),
                    interactive: true,
                    fallbackOpacity: 0.15
                )
                .contentShape(Rectangle())
        }
        .dockNotesChromeButton()
        .help(label)
        .accessibilityLabel(label)
    }

    private func importNoteFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["md", "markdown", "txt"].compactMap {
            UTType(filenameExtension: $0)
        }
        guard panel.runModal() == .OK else { return }
        let accessedURLs = panel.urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
        do {
            let count = try store.importNotes(from: panel.urls)
            transferSucceeded = true
            transferMessage = "\(settings.text(.importNotes)): \(count)"
        } catch {
            transferSucceeded = false
            transferMessage = error.localizedDescription
        }
    }

    private func exportDisplayedNotes(as format: NoteExportFormat) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        let accessed = directory.startAccessingSecurityScopedResource()
        defer { if accessed { directory.stopAccessingSecurityScopedResource() } }
        do {
            let urls = try store.exportNotes(displayedNotes, to: directory, format: format)
            transferSucceeded = true
            transferMessage = "\(settings.text(.exportNotes)): \(urls.count)"
        } catch {
            transferSucceeded = false
            transferMessage = error.localizedDescription
        }
    }
}

private struct WorkspaceColorPaletteView: View {
    let selectedHex: String
    let language: AppLanguage
    let onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    private let chineseNames = ["晨光", "雾绿", "杏子", "藤紫", "柠檬", "青绿"]
    private let englishNames = ["Sunrise", "Sage", "Apricot", "Lavender", "Citrus", "Mint"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language == .english ? "Workspace color" : "工作区颜色")
                .font(.system(size: 12, weight: .semibold))

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(NotePalette.gradients.enumerated()), id: \.offset) { index, gradient in
                    let isSelected = selectedHex.caseInsensitiveCompare(gradient.startHex) == .orderedSame
                    Button {
                        onSelect(gradient.startHex)
                    } label: {
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color(hex: gradient.startHex))
                                .frame(height: 42)
                                .overlay(alignment: .topLeading) {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.46), .clear],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .allowsHitTesting(false)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(
                                            isSelected ? Color.accentColor : Color.black.opacity(0.16),
                                            lineWidth: isSelected ? 2 : 0.7
                                        )
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color.accentColor, Color.white)
                                            .padding(4)
                                    }
                                }
                            Text(language == .english ? englishNames[index] : chineseNames[index])
                                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(language == .english ? englishNames[index] : chineseNames[index]), \(gradient.startHex)")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
        .padding(14)
        .frame(width: 280)
        .dockNotesGlassPanel(radius: 14, tint: Color.white.opacity(0.07))
    }
}

struct WorkspaceManagementView: View {
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    var size = CGSize(width: 600, height: 480)
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var workspacePendingDeletion: NoteWorkspace?
    @State private var colorPickerWorkspaceID: NoteWorkspace.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.text(.manageWorkspaces))
                        .font(.system(size: 18, weight: .bold))
                    Text(settings.language == .english
                        ? "Each note belongs to one workspace. Deleting a workspace never deletes its notes."
                        : "每张便签属于一个工作区；删除工作区不会删除其中的便签。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(settings.text(.close)) {
                    if let onClose { onClose() } else { dismiss() }
                }
                    .dockNotesChromeButton()
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .dockNotesGlassPanel(radius: 10, tint: Color.white.opacity(0.05), interactive: true)
            }
            .padding(18)
            .background(Color.white.opacity(0.08))
            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { index, workspace in
                        HStack(spacing: 12) {
                            Button {
                                colorPickerWorkspaceID = workspace.id
                            } label: {
                                Circle()
                                    .fill(Color(hex: workspace.colorHex))
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                                    .shadow(color: Color.black.opacity(0.10), radius: 2, y: 1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(settings.language == .english ? "Change workspace color" : "更改工作区颜色")
                            .popover(
                                isPresented: Binding(
                                    get: { colorPickerWorkspaceID == workspace.id },
                                    set: { if !$0 { colorPickerWorkspaceID = nil } }
                                ),
                                arrowEdge: .trailing
                            ) {
                                WorkspaceColorPaletteView(
                                    selectedHex: workspace.colorHex,
                                    language: settings.language
                                ) { colorHex in
                                    _ = store.setWorkspaceColor(workspace.id, colorHex: colorHex)
                                    colorPickerWorkspaceID = nil
                                }
                            }
                            .frame(width: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                TextField(
                                    settings.text(.workspaceName),
                                    text: Binding(
                                        get: { store.workspace(id: workspace.id)?.name ?? workspace.name },
                                        set: { _ = store.renameWorkspace(workspace.id, to: $0) }
                                    )
                                )
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .semibold))
                                HStack(spacing: 6) {
                                    Text("\(store.notes.filter { $0.workspaceID == workspace.id }.count)")
                                    if workspace.id == store.defaultWorkspaceID {
                                        Text(settings.language == .english ? "Default" : "默认")
                                    }
                                    if workspace.id == store.activeWorkspaceID {
                                        Text(settings.language == .english ? "Current" : "当前")
                                    }
                                }
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            }

                            Spacer()
                            Button { store.moveWorkspace(workspace.id, to: index - 1) } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(index == 0)
                            .frame(width: 26, height: 26)
                            .dockNotesGlass(in: Circle(), tint: Color.white.opacity(0.04), interactive: true)
                            Button { store.moveWorkspace(workspace.id, to: index + 1) } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(index == store.workspaces.count - 1)
                            .frame(width: 26, height: 26)
                            .dockNotesGlass(in: Circle(), tint: Color.white.opacity(0.04), interactive: true)
                            Button(role: .destructive) {
                                workspacePendingDeletion = workspace
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(workspace.id == store.defaultWorkspaceID
                                        ? Color.secondary
                                        : Color.red.opacity(0.82))
                            }
                            .disabled(workspace.id == store.defaultWorkspaceID)
                            .frame(width: 26, height: 26)
                            .dockNotesGlass(in: Circle(), tint: Color.red.opacity(0.05), interactive: true)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .frame(height: 66)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: workspace.colorHex).opacity(
                                    workspace.id == store.activeWorkspaceID ? 0.15 : 0.055
                                ))
                                .dockNotesGlassPanel(
                                    radius: 12,
                                    tint: Color(hex: workspace.colorHex).opacity(0.08),
                                    clear: true,
                                    fallbackOpacity: 0.17
                                )
                        }
                    }
                }
                .padding(16)
            }

            Divider()
            HStack {
                if store.latestPendingWorkspaceDeletion != nil {
                    Text(settings.text(.workspaceDeleted))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Button(settings.text(.undo)) { store.undoLatestWorkspaceDeletion() }
                }
                Spacer()
                Button {
                    let baseName = settings.language == .english ? "Workspace" : "工作区"
                    _ = store.createWorkspace(
                        name: "\(baseName) \(store.workspaces.count + 1)",
                        makeActive: false
                    )
                } label: {
                    Label(settings.text(.newWorkspace), systemImage: "plus")
                }
                .dockNotesChromeButton()
                .padding(.horizontal, 12)
                .frame(height: 32)
                .dockNotesGlassPanel(radius: 10, tint: Color.white.opacity(0.07), interactive: true)
            }
            .padding(16)
            .background(Color.white.opacity(0.08))
        }
        .frame(width: size.width, height: size.height)
        .background(DockNotesGlassCanvas(accent: Color(hex: NotePalette.gradients[0].startHex)))
        .alert(
            workspacePendingDeletion.map {
                settings.language == .english
                    ? "Delete \($0.name)?"
                    : "删除“\($0.name)”？"
            } ?? settings.text(.delete),
            isPresented: Binding(
                get: { workspacePendingDeletion != nil },
                set: { if !$0 { workspacePendingDeletion = nil } }
            )
        ) {
            Button(settings.text(.cancel), role: .cancel) { workspacePendingDeletion = nil }
            Button(settings.text(.delete), role: .destructive) {
                if let workspacePendingDeletion {
                    _ = store.deleteWorkspace(workspacePendingDeletion.id)
                }
                workspacePendingDeletion = nil
            }
        } message: {
            Text(settings.language == .english
                ? "Its notes will move to the default workspace and can be restored with Undo."
                : "其中的便签会移到默认工作区，并可通过“撤销”恢复。")
        }
    }
}

struct SettingsWindowView: View {
    private enum Section: String, CaseIterable {
        case appearance
        case reminders
        case ai
        case archive
    }

    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var reminders: ReminderCoordinator
    @ObservedObject var calendarSync: CalendarSyncCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: Section = .appearance
    @State private var aiProviderDraft: AIProvider = .openAICompatible
    @State private var aiEndpointDraft = ""
    @State private var aiModelDraft = ""
    @State private var aiAPIKeyDraft = ""
    @State private var aiSaveResult: Bool?
    @State private var dailySummaryTimeDraft = ""
    @State private var dailySummaryTimeInvalid = false

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            ScrollView {
                Group {
                    switch selection {
                    case .appearance: appearanceSettings
                    case .reminders: reminderSettings
                    case .ai: aiSettings
                    case .archive: archiveSettings
                    }
                }
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 760, height: 560)
        .background {
            DockNotesGlassCanvas(accent: Color(hex: NotePalette.gradients[0].startHex))
                .overlay {
                    if colorScheme == .dark {
                        Color.black.opacity(0.24).allowsHitTesting(false)
                    }
                }
        }
        .background {
            if !DockNotesGlassRuntime.isStaticRendering {
                DockNotesGlassWindowChrome(
                    backgroundColor: colorScheme == .dark
                        ? NSColor(deviceWhite: 0.11, alpha: 0.78)
                        : NSColor(deviceWhite: 1, alpha: 0.30)
                )
                .frame(width: 0, height: 0)
            }
        }
        .onAppear {
            loadAIDraft(provider: settings.aiProvider)
            dailySummaryTimeDraft = ReminderTimeInput.format(dailySummaryDateBinding.wrappedValue)
            reminders.syncNow()
            calendarSync.refreshPermissionAndCalendars()
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(NotePalette.gradients[0].swiftUIGradient)
                    Image(systemName: "note.text")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.64))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("DockNotes")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(settings.text(.preferences))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 24)

            VStack(spacing: 9) {
                sidebarButton(
                    .appearance,
                    symbol: "slider.horizontal.3",
                    title: settings.text(.appearance),
                    gradient: NotePalette.gradients[0].swiftUIGradient
                )
                sidebarButton(
                    .reminders,
                    symbol: "bell.badge",
                    title: settings.text(.reminders),
                    gradient: NotePalette.gradients[3].swiftUIGradient
                )
                sidebarButton(
                    .ai,
                    symbol: "sparkles",
                    title: settings.text(.ai),
                    gradient: NotePalette.gradients[4].swiftUIGradient
                )
                sidebarButton(
                    .archive,
                    symbol: "archivebox",
                    title: settings.text(.archiveSettings),
                    gradient: NotePalette.gradients[1].swiftUIGradient
                )
            }
            .padding(.horizontal, 12)

            Spacer()

            Button {
                store.presentLibrary()
            } label: {
                Label(settings.text(.library), systemImage: "rectangle.stack.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .dockNotesGlassPanel(radius: 10, tint: Color.white.opacity(0.04), interactive: true)
            }
            .dockNotesChromeButton()
            .padding(12)
        }
        .frame(width: 188)
        .background(Color.white.opacity(0.09))
        .overlay(alignment: .trailing) { Divider() }
    }

    private func sidebarButton(
        _ section: Section,
        symbol: String,
        title: String,
        gradient: LinearGradient
    ) -> some View {
        Button { selection = section } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12, weight: selection == section ? .bold : .medium))
                    .lineLimit(1)
                Spacer()
                if selection == section {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .opacity(0.46)
                }
            }
            .foregroundStyle(selection == section ? Color.black.opacity(0.72) : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background {
                if selection == section {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(gradient)
                        .opacity(0.58)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.72), lineWidth: 0.7)
                        }
                        .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
                }
            }
            .dockNotesGlassPanel(
                radius: 12,
                tint: selection == section ? Color.white.opacity(0.08) : Color.white.opacity(0.02),
                interactive: true,
                fallbackOpacity: selection == section ? 0.24 : 0.10
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .dockNotesChromeButton()
        .accessibilityLabel(title)
    }

    private var appearanceSettings: some View {
        settingsPage(title: settings.text(.appearance), subtitle: settings.text(.appearanceSettingsHint)) {
            settingsCard(title: settings.text(.general), symbol: "globe", gradient: NotePalette.gradients[0].swiftUIGradient) {
                settingLine(title: settings.text(.language), detail: settings.text(.languageHint)) {
                    Picker("", selection: $settings.language) {
                        Text(settings.text(.systemDefault)).tag(AppLanguage.system)
                        Text(settings.text(.simplifiedChinese)).tag(AppLanguage.simplifiedChinese)
                        Text(settings.text(.english)).tag(AppLanguage.english)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 292)
                }
                settingLine(
                    title: settings.text(.quickCaptureShortcut),
                    detail: settings.quickCaptureShortcutRegistrationFailed
                        ? settings.text(.shortcutConflict)
                        : settings.text(.quickCaptureHint)
                ) {
                    Picker("", selection: $settings.quickCaptureShortcut) {
                        ForEach(QuickCaptureShortcut.allCases) { shortcut in
                            Text(shortcut.displayName).tag(shortcut)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            settingsCard(title: settings.text(.deck), symbol: "rectangle.stack", gradient: NotePalette.gradients[4].swiftUIGradient) {
                settingLine(title: settings.text(.deckPosition)) {
                    Picker("", selection: $settings.deckEdge) {
                        Text(settings.text(.leftEdge)).tag(DeckEdge.left)
                        Text(settings.text(.rightEdge)).tag(DeckEdge.right)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }
                settingLine(title: settings.text(.visibleTabs)) {
                    Stepper(value: $settings.visibleTabCount, in: 1...7) {
                        Text("\(settings.visibleTabCount)")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .frame(width: 22)
                    }
                    .fixedSize()
                }
                settingLine(title: settings.text(.deckBehavior)) {
                    Toggle(settings.text(.keepDeckOpen), isOn: Binding(
                        get: { !settings.keepDeckOpen },
                        set: { settings.keepDeckOpen = !$0 }
                    ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                opacityLine(settings.text(.collapsed), value: $settings.collapsedOpacity)
            }

            settingsCard(title: settings.text(.notes), symbol: "note.text", gradient: NotePalette.gradients[2].swiftUIGradient) {
                opacityLine(settings.text(.expanded), value: $settings.expandedOpacity)
                HStack(spacing: 12) {
                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(Color.black.opacity(0.48))
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(NotePalette.gradients[2].swiftUIGradient)
                                .opacity(0.55)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.text(.customColor)).font(.system(size: 12, weight: .semibold))
                        Text(settings.text(.noteAppearanceHint)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private var aiSettings: some View {
        settingsPage(title: settings.text(.ai), subtitle: settings.text(.aiSettingsHint)) {
            settingsCard(title: settings.text(.aiConnection), symbol: "network", gradient: NotePalette.gradients[4].swiftUIGradient) {
                settingLine(title: settings.text(.aiProvider)) {
                    Picker("", selection: $aiProviderDraft) {
                        Text(settings.text(.openAICompatible)).tag(AIProvider.openAICompatible)
                        Text(settings.text(.anthropic)).tag(AIProvider.anthropic)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 292)
                    .onChange(of: aiProviderDraft) { _, provider in
                        loadAIDraft(provider: provider)
                    }
                }
                settingLine(title: settings.text(.aiServiceURL)) {
                    HStack(spacing: 8) {
                        TextField(aiProviderDraft.defaultEndpoint, text: $aiEndpointDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11).monospaced())
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .dockNotesGlassPanel(radius: 9, tint: Color.white.opacity(0.04), interactive: true)
                        Button(settings.text(.restoreDefault)) { aiEndpointDraft = aiProviderDraft.defaultEndpoint }
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(width: 330)
                }
            }

            settingsCard(title: settings.text(.recommendedModels), symbol: "cpu", gradient: NotePalette.gradients[0].swiftUIGradient) {
                HStack(spacing: 8) {
                    ForEach(aiProviderDraft.suggestedModels, id: \.self) { model in
                        Button {
                            aiModelDraft = model
                        } label: {
                            Text(model)
                                .font(.system(size: 10, weight: aiModelDraft == model ? .bold : .medium).monospaced())
                                .foregroundStyle(Color.black.opacity(0.70))
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .dockNotesGlassCapsule(
                                    tint: aiModelDraft == model
                                        ? Color(hex: NotePalette.gradients[0].startHex).opacity(0.18)
                                        : Color.white.opacity(0.04),
                                    interactive: true
                                )
                        }
                        .dockNotesChromeButton()
                    }
                }
                TextField(settings.text(.customModel), text: $aiModelDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12).monospaced())
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .dockNotesGlassPanel(radius: 9, tint: Color.white.opacity(0.04), interactive: true)
            }

            settingsCard(title: settings.text(.aiAPIKey), symbol: "key.fill", gradient: NotePalette.gradients[1].swiftUIGradient) {
                SecureField("sk-…", text: $aiAPIKeyDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12).monospaced())
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .dockNotesGlassPanel(radius: 9, tint: Color.white.opacity(0.04), interactive: true)

                HStack(spacing: 9) {
                    Label(settings.text(.aiAPIKeyHint), systemImage: "lock.shield.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(settings.text(.saveConfiguration)) { saveAIConfiguration() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                }

                if let aiSaveResult {
                    Label(
                        settings.text(aiSaveResult ? .configurationSaved : .configurationSaveFailed),
                        systemImage: aiSaveResult ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(aiSaveResult ? Color.green : Color.red)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var reminderSettings: some View {
        settingsPage(title: settings.text(.reminders), subtitle: settings.text(.reminderSettingsHint)) {
            settingsCard(
                title: settings.text(.notificationPermission),
                symbol: "bell.badge.fill",
                gradient: NotePalette.gradients[3].swiftUIGradient
            ) {
                settingLine(title: settings.text(.notificationPermission)) {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(permissionColor)
                            .frame(width: 8, height: 8)
                        Text(permissionText)
                            .font(.system(size: 11, weight: .semibold))
                        if reminders.permissionState == .allowed {
                            Text(String(
                                format: settings.text(.scheduledNotifications),
                                reminders.scheduledRequestCount
                            ))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                if reminders.permissionState == .notRequested {
                    Button(settings.text(.enableNotifications)) { reminders.requestPermission() }
                        .buttonStyle(.borderedProminent)
                } else if reminders.permissionState == .denied {
                    Button(settings.text(.openNotificationSettings)) {
                        reminders.openSystemNotificationSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            settingsCard(
                title: settings.text(.taskReminders),
                symbol: "checklist.checked",
                gradient: NotePalette.gradients[0].swiftUIGradient
            ) {
                settingLine(title: settings.text(.taskReminders), detail: settings.text(.taskRemindersHint)) {
                    Toggle("", isOn: $settings.taskRemindersEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            settingsCard(
                title: calendarText("系统日历", "System Calendar"),
                symbol: "calendar.badge.clock",
                gradient: NotePalette.gradients[2].swiftUIGradient
            ) {
                settingLine(
                    title: calendarText("日历权限", "Calendar access"),
                    detail: calendarText(
                        "DockNotes 是任务主数据源；日历只显示带日期的任务。",
                        "DockNotes remains the task source; Calendar displays dated tasks."
                    )
                ) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(calendarPermissionColor)
                            .frame(width: 8, height: 8)
                        Text(calendarPermissionText)
                            .font(.system(size: 11, weight: .semibold))
                    }
                }

                if calendarSync.permissionState == .notRequested {
                    Button(calendarText("允许访问并创建专用日历", "Allow access and create calendar")) {
                        calendarSync.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                } else if calendarSync.permissionState == .denied
                            || calendarSync.permissionState == .restricted {
                    Button(calendarText("打开系统日历权限设置", "Open Calendar privacy settings")) {
                        calendarSync.openSystemCalendarSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }

                settingLine(
                    title: calendarText("同步到系统日历", "Sync to Calendar"),
                    detail: calendarText("默认关闭；开启后自动保持任务与事件一致。", "Off by default; keeps task events in sync when enabled.")
                ) {
                    Toggle("", isOn: $settings.calendarSyncEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(
                            calendarSync.permissionState != .allowed
                                && !settings.calendarSyncEnabled
                        )
                }

                if calendarSync.permissionState == .allowed {
                    settingLine(title: calendarText("目标日历", "Target calendar")) {
                        HStack(spacing: 8) {
                            Picker("", selection: Binding(
                                get: { settings.calendarIdentifier ?? "" },
                                set: { settings.calendarIdentifier = $0.isEmpty ? nil : $0 }
                            )) {
                                Text(calendarText("请选择", "Choose…")).tag("")
                                ForEach(calendarSync.calendars) { calendar in
                                    Text("\(calendar.title) · \(calendar.sourceTitle)").tag(calendar.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 235)
                            Button(calendarText("创建 DockNotes 日历", "Create DockNotes calendar")) {
                                calendarSync.createDockNotesCalendar()
                            }
                            .font(.system(size: 10, weight: .semibold))
                        }
                    }

                    HStack(spacing: 9) {
                        Button(calendarText("立即同步", "Sync now")) { calendarSync.syncNow() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!settings.calendarSyncEnabled || settings.calendarIdentifier == nil)
                        Button(calendarText("重建受管事件", "Rebuild managed events")) { calendarSync.rebuild() }
                            .buttonStyle(.bordered)
                            .disabled(!settings.calendarSyncEnabled || settings.calendarIdentifier == nil)
                        Spacer()
                        Text(String(
                            format: calendarText("已同步 %d 个事件", "%d events synced"),
                            calendarSync.synchronizedEventCount
                        ))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                if !calendarSync.statusMessage.isEmpty {
                    Label(calendarSync.statusMessage, systemImage: calendarSync.conflicts.isEmpty ? "checkmark.circle" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(calendarSync.conflicts.isEmpty ? Color.secondary : Color.orange)
                }

                ForEach(calendarSync.conflicts) { conflict in
                    VStack(alignment: .leading, spacing: 7) {
                        Label(
                            conflict.kind == .deleted
                                ? calendarText("事件已在系统日历中删除", "Event was deleted in Calendar")
                                : calendarText("事件已在系统日历中修改", "Event was changed in Calendar"),
                            systemImage: "exclamationmark.arrow.triangle.2.circlepath"
                        )
                        .font(.system(size: 11, weight: .semibold))
                        Text(conflict.localTitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button(calendarText("重新同步", "Resync")) {
                                calendarSync.resolveByResyncing(conflict)
                            }
                            .buttonStyle(.borderedProminent)
                            Button(calendarText("采用日历更改", "Use Calendar change")) {
                                calendarSync.resolveByAdoptingCalendar(conflict)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            settingsCard(
                title: settings.text(.dailySummary),
                symbol: "sunrise.fill",
                gradient: NotePalette.gradients[1].swiftUIGradient
            ) {
                settingLine(title: settings.text(.dailySummary), detail: settings.text(.dailySummaryHint)) {
                    Toggle("", isOn: $settings.dailySummaryEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                settingLine(title: settings.text(.dailySummaryTime)) {
                    HStack(spacing: 8) {
                        DatePicker("", selection: dailySummaryDateBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .disabled(!settings.dailySummaryEnabled)
                        TextField(settings.text(.timeInputHint), text: $dailySummaryTimeDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11).monospacedDigit())
                            .padding(.horizontal, 9)
                            .frame(width: 112, height: 30)
                            .dockNotesGlassPanel(radius: 9, tint: Color.white.opacity(0.04), interactive: true)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(dailySummaryTimeInvalid ? Color.red.opacity(0.8) : Color.black.opacity(0.08), lineWidth: 0.8)
                            }
                            .disabled(!settings.dailySummaryEnabled)
                            .onSubmit { applyDailySummaryTimeDraft() }
                    }
                }
                if dailySummaryTimeInvalid {
                    Label(settings.text(.invalidTime), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var dailySummaryDateBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = AppSettings.clampDailySummaryMinutes(settings.dailySummaryMinutes)
                return Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let calendar = Calendar.current
                settings.dailySummaryMinutes = calendar.component(.hour, from: date) * 60
                    + calendar.component(.minute, from: date)
                dailySummaryTimeDraft = ReminderTimeInput.format(date, calendar: calendar)
                dailySummaryTimeInvalid = false
            }
        )
    }

    private var permissionText: String {
        switch reminders.permissionState {
        case .allowed: settings.text(.notificationsAllowed)
        case .denied: settings.text(.notificationsDenied)
        case .notRequested: settings.text(.notificationsNotRequested)
        case .unknown: settings.text(.notificationsUnknown)
        }
    }

    private var permissionColor: Color {
        switch reminders.permissionState {
        case .allowed: .green
        case .denied: .red
        case .notRequested: .orange
        case .unknown: .secondary
        }
    }

    private var calendarPermissionText: String {
        switch calendarSync.permissionState {
        case .allowed: calendarText("已允许", "Allowed")
        case .denied: calendarText("已拒绝", "Denied")
        case .restricted: calendarText("受系统限制", "Restricted")
        case .notRequested: calendarText("尚未请求", "Not requested")
        case .unknown: calendarText("未知", "Unknown")
        }
    }

    private var calendarPermissionColor: Color {
        switch calendarSync.permissionState {
        case .allowed: .green
        case .denied, .restricted: .red
        case .notRequested: .orange
        case .unknown: .secondary
        }
    }

    private func calendarText(_ chinese: String, _ english: String) -> String {
        switch settings.language {
        case .english: english
        case .simplifiedChinese: chinese
        case .system: Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
        }
    }

    private func applyDailySummaryTimeDraft() {
        guard let date = ReminderTimeInput.parse(dailySummaryTimeDraft, on: Date()) else {
            dailySummaryTimeInvalid = true
            return
        }
        let calendar = Calendar.current
        settings.dailySummaryMinutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        dailySummaryTimeDraft = ReminderTimeInput.format(date, calendar: calendar)
        dailySummaryTimeInvalid = false
    }

    private var archiveSettings: some View {
        settingsPage(title: settings.text(.archiveSettings), subtitle: settings.text(.archiveSettingsHint)) {
            settingsCard(title: settings.text(.obsidianBackup), symbol: "externaldrive.fill", gradient: NotePalette.gradients[1].swiftUIGradient) {
                settingLine(title: settings.text(.obsidianBackup)) {
                    Toggle("", isOn: $settings.obsidianBackupEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                settingLine(title: settings.text(.obsidianFolder)) {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(settings.obsidianVaultPath.isEmpty ? settings.text(.noFolderSelected) : settings.obsidianVaultPath)
                            .font(.system(size: 11))
                            .foregroundStyle(settings.obsidianVaultPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 292, alignment: .trailing)
                        Button(settings.text(.chooseFolder)) { chooseObsidianFolder() }
                            .controlSize(.small)
                    }
                }

                Text(settings.text(.obsidianBackupHint))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                if let url = store.lastObsidianBackupURL {
                    Label("\(settings.text(.lastBackup)): \(url.lastPathComponent)", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                } else if let failure = store.lastObsidianBackupError {
                    Label("\(settings.text(.backupFailed)): \(obsidianFailureText(failure))", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func loadAIDraft(provider: AIProvider) {
        aiProviderDraft = provider
        aiEndpointDraft = settings.storedAIEndpoint(for: provider)
        aiModelDraft = settings.storedAIModel(for: provider)
        let initialKey = settings.storedAIAPIKey(for: provider)
        aiAPIKeyDraft = initialKey
        aiSaveResult = nil
        Task {
            let loadedKey = await settings.loadAIAPIKey(for: provider)
            guard aiProviderDraft == provider, aiAPIKeyDraft == initialKey else { return }
            aiAPIKeyDraft = loadedKey
        }
    }

    private func saveAIConfiguration() {
        let provider = aiProviderDraft
        let endpoint = aiEndpointDraft
        let model = aiModelDraft
        let apiKey = aiAPIKeyDraft
        Task {
            let saved = await settings.saveAIConfiguration(
                provider: provider,
                endpoint: endpoint,
                model: model,
                apiKey: apiKey
            )
            withAnimation(.easeOut(duration: 0.18)) {
                aiSaveResult = saved
            }
        }
    }

    private func chooseObsidianFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = settings.text(.chooseFolder)
        if let existing = settings.obsidianVaultURL {
            panel.directoryURL = existing
        }
        if panel.runModal() == .OK {
            settings.setObsidianVault(panel.url)
            settings.obsidianBackupEnabled = true
        }
    }

    private func obsidianFailureText(_ failure: ObsidianBackupFailure) -> String {
        switch failure {
        case .missingFolder: settings.text(.noFolderSelected)
        case let .writeFailed(message): message
        }
    }

    private func settingsPage<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsCard<Content: View>(
        title: String,
        symbol: String,
        gradient: LinearGradient,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.58))
                    .frame(width: 26, height: 26)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(gradient)
                            .opacity(0.58)
                    }
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            content()
        }
        .padding(16)
        .dockNotesGlassPanel(radius: 16, tint: Color.white.opacity(0.04), clear: true)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.62), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(0.07), radius: 10, y: 4)
    }

    private func settingLine<Content: View>(
        title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }

    private func opacityLine(_ title: String, value: Binding<Double>) -> some View {
        settingLine(title: title) {
            Slider(value: value, in: 0.20...1.0, step: 0.01)
                .frame(width: 220)
            Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var result: UInt64 = 0
        Scanner(string: value).scanHexInt64(&result)
        self.init(
            red: Double((result >> 16) & 0xFF) / 255,
            green: Double((result >> 8) & 0xFF) / 255,
            blue: Double(result & 0xFF) / 255
        )
    }
}

@MainActor
private enum PaperTexture {
    static let image: NSImage = {
        if let bundled = Bundle.main.url(forResource: "paper-texture", withExtension: "png"), let image = NSImage(contentsOf: bundled) {
            return image
        }
        let developmentPath = FileManager.default.currentDirectoryPath + "/Sources/DockNotesApp/Resources/paper-texture.png"
        return NSImage(contentsOfFile: developmentPath) ?? NSImage(size: NSSize(width: 2, height: 2))
    }()
}
