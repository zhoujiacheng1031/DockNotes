import AppKit
import SwiftUI

private extension View {
    /// DockNotes draws its own selected/pressed state for compact chrome.
    /// Keep keyboard accessibility while suppressing AppKit's persistent blue
    /// focus halo, which does not follow the custom control shape.
    func dockNotesChromeButton() -> some View {
        buttonStyle(.plain)
            .focusEffectDisabled()
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
    @State private var hoveredNoteID: DockNote.ID?
    @StateObject private var tabDrag = TabDragCoordinator()

    private var plan: DeckPlan {
        DeckLayout.plan(
            notes: store.notes,
            activeNoteID: store.activeNoteID,
            isExpanded: store.isExpanded,
            availableHeight: availableHeight,
            preferredVisibleCount: settings.visibleTabCount,
            excludedNoteIDs: Set(store.desktopNoteIDs)
        )
    }

    private var overflowNotes: [DockNote] {
        let ids = Set(plan.overflowIDs)
        return store.notes.filter { ids.contains($0.id) }
    }

    private var positionedTabs: [PositionedTab] {
        plan.slots.enumerated().compactMap { slot, noteID in
            guard let noteID,
                  let note = store.notes.first(where: { $0.id == noteID }) else { return nil }
            return PositionedTab(note: note, slot: slot)
        }
    }

    private var tabPitch: CGFloat {
        DeckLayout.tabPitch(for: availableHeight, slotCount: plan.slots.count)
    }

    private var deckContentHeight: CGFloat {
        let controlCount = overflowNotes.isEmpty ? 3 : 4
        let controlsHeight = CGFloat(controlCount * 29 + max(0, controlCount - 1) * 7 + 10)
        return DeckLayout.tabStackHeight(slotCount: plan.slots.count, pitch: tabPitch) + controlsHeight
    }

    var body: some View {
        Group {
            if store.deckState.showsTabs {
                VStack(alignment: settings.deckEdge == .right ? .trailing : .leading, spacing: 0) {
                    ZStack(alignment: settings.deckEdge == .right ? .topTrailing : .topLeading) {
                        ForEach(positionedTabs) { positionedTab in
                            let note = positionedTab.note
                            let slot = positionedTab.slot
                            EdgeTab(
                                note: note,
                                isSelected: note.id == store.activeNoteID && !store.isExpanded,
                                edge: settings.deckEdge,
                                language: settings.language,
                                tiltDegrees: DeckLayout.tiltDegrees(for: slot),
                                isDragging: tabDrag.noteID == note.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                hoveredNoteID = nil
                                store.select(note.id)
                            }
                            .onHover { hovering in
                                guard tabDrag.noteID == nil else {
                                    hoveredNoteID = nil
                                    return
                                }
                                if hovering {
                                    hoveredNoteID = note.id
                                } else if hoveredNoteID == note.id {
                                    hoveredNoteID = nil
                                }
                            }
                            .popover(
                                isPresented: Binding(
                                    get: { hoveredNoteID == note.id },
                                    set: { isPresented in
                                        if !isPresented, hoveredNoteID == note.id {
                                            hoveredNoteID = nil
                                        }
                                    }
                                ),
                                arrowEdge: settings.deckEdge == .right ? .trailing : .leading
                            ) {
                                EdgeTabHoverCard(note: note, language: settings.language)
                            }
                            .accessibilityLabel(note.title)
                            .accessibilityAddTraits(.isButton)
                            .modifier(
                                LocalTabDragModifier(
                                    enabled: !isDesignPreview,
                                    noteID: note.id,
                                    slot: slot,
                                    slotCount: plan.slots.count,
                                    tabPitch: tabPitch,
                                    store: store,
                                    dragCoordinator: tabDrag
                                )
                            )
                            .offset(y: CGFloat(slot) * tabPitch)
                            .zIndex(tabDrag.noteID == note.id ? 100 : Double(slot))
                        }
                    }
                    .frame(
                        width: DeckLayout.windowWidth,
                        height: DeckLayout.tabStackHeight(slotCount: plan.slots.count, pitch: tabPitch),
                        alignment: .topTrailing
                    )

                    VStack(spacing: 7) {
                        if !overflowNotes.isEmpty {
                            Button {
                                isOverflowPresented.toggle()
                            } label: {
                                Text("+\(overflowNotes.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.58))
                                    .frame(width: 29, height: 29)
                                    .background(Color.white.opacity(0.88), in: Circle())
                                    .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.6))
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
                        deckButton("plus", label: settings.text(.newNote)) {
                            store.addNote(language: settings.language)
                        }
                        deckButton("rectangle.stack.fill", label: settings.text(.library)) {
                            store.presentLibrary()
                        }
                        deckButton("gearshape", label: settings.text(.preferences)) {
                            store.presentSettings()
                        }
                    }
                    .frame(width: DeckLayout.windowWidth)
                    .padding(.top, 10)
                }
                .frame(width: DeckLayout.windowWidth, height: deckContentHeight, alignment: .top)
                .transition(
                    .opacity.combined(
                        with: .move(edge: settings.deckEdge == .right ? .trailing : .leading)
                    )
                )
            } else {
                RestingDeckIndicator(notes: store.notes, availableHeight: availableHeight, edge: settings.deckEdge)
                    .transition(.opacity)
            }
        }
        .frame(width: DeckLayout.windowWidth, height: availableHeight, alignment: .center)
        .opacity(settings.collapsedOpacity)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                store.pointerEnteredDeck()
            } else {
                store.pointerExitedDeck(keepOpen: settings.keepDeckOpen)
            }
        }
        .onTapGesture {
            // Borderless non-activating panels can miss hover delivery under
            // some accessibility and remote-control configurations. The pill
            // remains directly clickable as a deterministic wake-up path.
            if store.deckState == .resting { store.pointerEnteredDeck() }
        }
        .onChange(of: tabDrag.noteID) { _, noteID in
            if noteID != nil { hoveredNoteID = nil }
        }
        .animation(.easeOut(duration: 0.16), value: store.deckState)
    }

    private func deckButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.58))
                .frame(width: 29, height: 29)
                .background(Color.white.opacity(0.88), in: Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.6))
        }
        .dockNotesChromeButton()
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct PositionedTab: Identifiable {
    let note: DockNote
    let slot: Int
    var id: DockNote.ID { note.id }
}

@MainActor
private final class TabDragCoordinator: ObservableObject {
    @Published private(set) var noteID: DockNote.ID?
    @Published private(set) var sourceSlot = 0
    @Published private(set) var targetSlot = 0
    @Published private(set) var settlingOffset: CGFloat = 0
    @Published private(set) var isSettling = false
    private(set) var lastTranslation: CGFloat = 0

    func begin(noteID: DockNote.ID, sourceSlot: Int) {
        if self.noteID != noteID {
            self.noteID = noteID
            self.sourceSlot = sourceSlot
            targetSlot = sourceSlot
            settlingOffset = 0
            isSettling = false
            lastTranslation = 0
        }
    }

    func update(translation: CGFloat, targetSlot: Int, noteID: DockNote.ID) {
        guard self.noteID == noteID else { return }
        lastTranslation = translation
        self.targetSlot = targetSlot
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

    func updateSettlingOffset(_ offset: CGFloat, noteID: DockNote.ID) {
        guard self.noteID == noteID else { return }
        settlingOffset = offset
    }

    func finish(noteID: DockNote.ID) {
        guard self.noteID == noteID else { return }
        self.noteID = nil
        settlingOffset = 0
        isSettling = false
        lastTranslation = 0
    }
}

private struct LocalDragGestureState: Equatable {
    var isActive = false
    var translation: CGFloat = 0
}

private struct LocalTabDragModifier: ViewModifier {
    let enabled: Bool
    let noteID: DockNote.ID
    let slot: Int
    let slotCount: Int
    let tabPitch: CGFloat
    @ObservedObject var store: NotesStore
    @ObservedObject var dragCoordinator: TabDragCoordinator
    @GestureState private var gestureState = LocalDragGestureState()

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
        if gestureState.isActive {
            return gestureState.translation
        }
        return dragCoordinator.settlingOffset
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .offset(y: previewOffset)
                .animation(
                    .interactiveSpring(response: 0.24, dampingFraction: 0.82),
                    value: dragCoordinator.targetSlot
                )
                .offset(y: dragOffset)
                .scaleEffect(isDragging ? 1.045 : 1, anchor: .trailing)
                .opacity(isDragging ? 0.94 : 1)
                .zIndex(isDragging ? 100 : 0)
                .shadow(color: Color.black.opacity(isDragging ? 0.24 : 0), radius: 11, x: -4, y: 4)
                .animation(.easeOut(duration: 0.10), value: isDragging)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 6)
                        .updating($gestureState) { value, gestureState, transaction in
                            transaction.disablesAnimations = true
                            gestureState.isActive = true
                            gestureState.translation = value.translation.height
                        }
                        .onChanged { value in
                            dragCoordinator.begin(noteID: noteID, sourceSlot: slot)
                            let target = DeckLayout.dragTarget(
                                sourceSlot: dragCoordinator.sourceSlot,
                                translation: value.translation.height,
                                slotCount: slotCount,
                                pitch: tabPitch
                            )
                            dragCoordinator.update(
                                translation: value.translation.height,
                                targetSlot: target,
                                noteID: noteID
                            )
                        }
                        .onEnded { value in
                            dragCoordinator.begin(noteID: noteID, sourceSlot: slot)
                            let destination = DeckLayout.dragTarget(
                                sourceSlot: dragCoordinator.sourceSlot,
                                translation: value.translation.height,
                                slotCount: slotCount,
                                pitch: tabPitch
                            )
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                dragCoordinator.beginSettling(
                                    destinationSlot: destination,
                                    translation: value.translation.height,
                                    pitch: tabPitch,
                                    noteID: noteID
                                )
                                store.moveNote(noteID, to: destination)
                            }
                            animateSettling()
                        }
                )
                .onChange(of: gestureState.isActive) { _, isActive in
                    guard !isActive,
                          dragCoordinator.noteID == noteID,
                          !dragCoordinator.isSettling else { return }
                    // SwiftUI resets GestureState even when AppKit cancels the
                    // gesture at a panel or screen edge. Clear the shared
                    // session through the same settling path used by a drop.
                    DispatchQueue.main.async {
                        dragCoordinator.beginSettling(
                            destinationSlot: dragCoordinator.sourceSlot,
                            translation: dragCoordinator.lastTranslation,
                            pitch: tabPitch,
                            noteID: noteID
                        )
                        animateSettling()
                    }
                }
        } else {
            content
        }
    }

    private func animateSettling() {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                dragCoordinator.updateSettlingOffset(0, noteID: noteID)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                dragCoordinator.finish(noteID: noteID)
            }
        }
    }
}

private struct RestingDeckIndicator: View {
    let notes: [DockNote]
    let availableHeight: CGFloat
    let edge: DeckEdge

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(notes.prefix(8))) { note in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(note.gradient)
                    .frame(width: 7, height: 18)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(Color.black.opacity(0.72), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.5))
        .frame(width: 22, height: availableHeight, alignment: .center)
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
    }
}

private struct EdgeTab: View {
    let note: DockNote
    let isSelected: Bool
    let edge: DeckEdge
    let language: AppLanguage
    let tiltDegrees: Double
    let isDragging: Bool

    private let ink = Color(nsColor: NSColor(deviceWhite: 0.10, alpha: 1))

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                note.gradient
                Color.white.opacity(0.13)
                LinearGradient(
                    colors: [Color.white.opacity(0.48), Color.white.opacity(0.20), Color.white.opacity(0.06)],
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
                    .stroke(
                        Color.white.opacity(0.78),
                        style: StrokeStyle(lineWidth: 0.8, dash: [2.2, 3.2])
                    )
                    .frame(width: 0.8, height: DeckLayout.tabVisualHeight - 18)
                    .frame(maxWidth: .infinity, alignment: edge == .right ? .trailing : .leading)
                    .padding(edge == .right ? .trailing : .leading, 4)

                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(0.88))
                        .frame(width: 2.5, height: 58)
                        .shadow(color: Color.white.opacity(0.65), radius: 3)
                        .frame(maxWidth: .infinity, alignment: edge == .right ? .leading : .trailing)
                        .padding(edge == .right ? .leading : .trailing, 3)
                }
            }
            .frame(width: DeckLayout.tabWidth, height: DeckLayout.tabVisualHeight - 4)
            .clipShape(TuckyTabShape(edge: edge))
            .contentShape(TuckyTabShape(edge: edge))
            .overlay {
                TuckyTabShape(edge: edge)
                    .stroke(Color.white.opacity(0.68), lineWidth: 0.8)
            }
            .overlay {
                TuckyTabShape(edge: edge)
                    .stroke(Color.black.opacity(0.055), lineWidth: 0.45)
                    .padding(0.8)
            }
            .rotationEffect(
                .degrees(isDragging ? 0 : (edge == .right ? tiltDegrees : -tiltDegrees)),
                anchor: edge == .right ? .trailing : .leading
            )
            .offset(x: isSelected ? (edge == .right ? -5 : 5) : 0)
            .saturation(isSelected ? 1.10 : 0.96)
            .shadow(
                color: Color.black.opacity(isDragging ? 0.20 : 0.15),
                radius: isDragging ? 8 : 5,
                x: edge == .right ? -3 : 3,
                y: 3
            )
            .animation(.easeOut(duration: 0.15), value: isSelected)
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
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                note.gradient.opacity(0.11)
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
        }
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

    private let palette = NotePalette.gradients

    init(
        note: DockNote,
        store: NotesStore,
        settings: AppSettings,
        closeAction: (() -> Void)? = nil,
        startsInAIMode: Bool = false
    ) {
        self.note = note
        self.store = store
        self.settings = settings
        self.closeAction = closeAction
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
                            closeAction: { isAIAssistantPresented = false }
                        )
                        .frame(height: 150)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    footer
                }
            }
            .background(NoteSurface(note: note))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.075), lineWidth: 0.65)
            }
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
        return VStack(spacing: 0) {
            HStack(spacing: 7) {
            let isDesktopNote = store.desktopNoteIDs.contains(note.id)
            tinyButton(
                isDesktopNote ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                label: settings.text(isDesktopNote ? .returnToEdge : .openOnDesktop),
                isActive: isDesktopNote
            ) {
                store.presentOnDesktop(note.id)
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
                    .background(
                        deadline?.status == .overdue ? Color.red.opacity(0.10) : Color.black.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 5)
                    )
            }
            .dockNotesChromeButton()
            .help(settings.text(.reminderHint))
            .popover(isPresented: $isDuePresented, arrowEdge: .top) {
                DueDatePopover(note: note, store: store, settings: settings)
            }

            Text(settings.text(.savedNow))
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
            tinyButton("checklist", label: settings.text(.task)) { store.insertTask(for: note.id) }
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

            HStack(spacing: 7) {
                Circle()
                    .fill(note.gradient)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.white.opacity(0.65), lineWidth: 0.5))
                TextField("", text: Binding(
                    get: { store.note(id: note.id)?.title ?? note.title },
                    set: { store.updateTitle($0, for: note.id) }
                ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityLabel("Note title")
            }
            .frame(height: 29)
        }
        .padding(.horizontal, 14)
        .frame(height: 63)
    }

    private var editor: some View {
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
            formatRequest: $formatRequest
        )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityLabel(note.title)
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
                .frame(width: 17, height: 22)
                .background(
                    isActive ? Color.white.opacity(0.60) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
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
            .background(Color.black.opacity(0.075), in: RoundedRectangle(cornerRadius: 6))
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

private enum NoteFormatCommand: Equatable {
    case bold
    case underline
    case strikethrough
    case highlight(String?)
}

private struct NoteFormatRequest: Equatable {
    let id = UUID()
    let command: NoteFormatCommand
}

private struct StableTextEditor: NSViewRepresentable {
    let text: String
    let rtfData: Data?
    let onChange: (String, Data?) -> Void
    let fontStyle: NoteFontStyle
    let fontSize: Double
    let searchQuery: String
    let searchTopInset: CGFloat
    @Binding var formatRequest: NoteFormatRequest?

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
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
        return (value as? NSNumber)?.intValue != 0
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
            NoteSurface(note: note).brightness(-0.035)
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 0.7, dash: [2, 3]))
                .foregroundStyle(Color.black.opacity(0.18))
                .frame(width: 0.7)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.text(.dueDate)).font(.system(size: 13, weight: .bold))
            DatePicker(
                "",
                selection: Binding(
                    get: { note.dueDate ?? Date().addingTimeInterval(3_600) },
                    set: { store.setDueDate($0, for: note.id, language: settings.language) }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 0.65)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 8, y: 3)
        .onAppear { isFocused = true }
    }
}

private struct AIAssistantPanel: View {
    let note: DockNote
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
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

            if settings.isAIConfigured {
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
                            TextEditor(text: $prompt)
                                .font(.system(size: 12))
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 3)
                                .frame(minHeight: 46, maxHeight: 72)
                            if prompt.isEmpty {
                                Text(settings.text(.aiPrompt))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 11)
                                    .allowsHitTesting(false)
                            }
                        }
                        .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 0.6)
                        }

                        Button(action: sendRequest) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 28, height: 28)
                                .background(Color.accentColor, in: Circle())
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
        .background(Color.white.opacity(0.10))
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

struct NotesLibraryView: View {
    private enum Collection: String, CaseIterable { case all, archived }

    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    @State private var collection: Collection = .all
    @State private var searchQuery = ""

    private var sourceNotes: [DockNote] {
        collection == .all ? store.notes : store.archivedNotes
    }

    private var displayedNotes: [DockNote] {
        NoteSearchEngine.rankedNotes(sourceNotes, query: searchQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Label(settings.text(.library), systemImage: "rectangle.stack.fill")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
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
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.black.opacity(0.07), lineWidth: 0.6)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            if displayedNotes.isEmpty {
                ContentUnavailableView(
                    searchQuery.isEmpty ? settings.text(.noArchivedNotes) : settings.text(.noSearchResults),
                    systemImage: searchQuery.isEmpty ? "archivebox" : "magnifyingglass",
                    description: Text(searchQuery.isEmpty ? settings.text(.archivedNotes) : settings.text(.searchLibrary))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(displayedNotes) { note in
                            HStack(spacing: 13) {
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
                                }
                                Spacer()
                                Text(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                if collection == .archived {
                                    Button(settings.text(.restore)) {
                                        store.restoreArchived(note.id, language: settings.language)
                                    }
                                        .buttonStyle(.borderless)
                                } else {
                                    Button {
                                        store.openFromLibrary(note.id)
                                    } label: {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    }
                                    .buttonStyle(.borderless)
                                    .help(settings.text(.allNotes))
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 64)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.52), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 680, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsWindowView: View {
    private enum Section: String, CaseIterable {
        case general
        case deck
        case notes
        case ai
        case archive
    }

    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    @State private var selection: Section = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                settingsTab(.general, symbol: "gearshape", title: settings.text(.general))
                settingsTab(.deck, symbol: "rectangle.stack", title: settings.text(.deck))
                settingsTab(.notes, symbol: "note.text", title: settings.text(.notes))
                settingsTab(.ai, symbol: "sparkles", title: settings.text(.ai))
                settingsTab(.archive, symbol: "archivebox", title: settings.text(.archive))
                settingsAction(symbol: "rectangle.stack.fill", title: settings.text(.library)) {
                    store.presentLibrary()
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(height: 72)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))

            Divider()

            Group {
                switch selection {
                case .general: generalSettings
                case .deck: deckSettings
                case .notes: noteSettings
                case .ai: aiSettings
                case .archive: archiveSettings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
        }
        .frame(width: 680, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func settingsTab(_ section: Section, symbol: String, title: String) -> some View {
        Button { selection = section } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 16))
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(selection == section ? Color.accentColor : Color.secondary)
            .frame(width: 82, height: 54)
            .background(selection == section ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .dockNotesChromeButton()
        .accessibilityLabel(title)
    }

    private func settingsAction(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 16))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(Color.secondary)
            .frame(width: 82, height: 54)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .dockNotesChromeButton()
        .accessibilityLabel(title)
    }

    private var generalSettings: some View {
        settingsPage(title: settings.text(.general), subtitle: settings.text(.generalHint)) {
            formRow(title: settings.text(.language)) {
                Picker("", selection: $settings.language) {
                    Text(settings.text(.systemDefault)).tag(AppLanguage.system)
                    Text(settings.text(.simplifiedChinese)).tag(AppLanguage.simplifiedChinese)
                    Text(settings.text(.english)).tag(AppLanguage.english)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 330)
            }
            Text(settings.text(.languageHint))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 150)
        }
    }

    private var deckSettings: some View {
        settingsPage(title: settings.text(.deck), subtitle: settings.text(.deckHint)) {
            formRow(title: settings.text(.deckBehavior)) {
                Toggle(settings.text(.keepDeckOpen), isOn: $settings.keepDeckOpen)
                    .toggleStyle(.checkbox)
                    .fixedSize()
            }
            formRow(title: settings.text(.visibleTabs)) {
                Stepper(value: $settings.visibleTabCount, in: 1...7) {
                    Text("\(settings.visibleTabCount)")
                        .font(.system(size: 13).monospacedDigit())
                        .frame(width: 20, alignment: .leading)
                }
                .fixedSize()
            }
            formRow(title: settings.text(.deckPosition)) {
                Picker("", selection: $settings.deckEdge) {
                    Text(settings.text(.leftEdge)).tag(DeckEdge.left)
                    Text(settings.text(.rightEdge)).tag(DeckEdge.right)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
            opacityRow(settings.text(.expanded), value: $settings.expandedOpacity)
            opacityRow(settings.text(.collapsed), value: $settings.collapsedOpacity)
            Text(settings.text(.opacityHint))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 150)
        }
    }

    private var noteSettings: some View {
        settingsPage(title: settings.text(.notes), subtitle: settings.text(.notesHint)) {
            HStack(spacing: 14) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.text(.customColor)).font(.system(size: 13, weight: .medium))
                    Text(settings.text(.noteAppearanceHint)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var aiSettings: some View {
        settingsPage(title: settings.text(.ai), subtitle: settings.text(.aiSettingsHint)) {
            formRow(title: settings.text(.aiProvider)) {
                Picker("", selection: $settings.aiProvider) {
                    Text(settings.text(.openAICompatible)).tag(AIProvider.openAICompatible)
                    Text(settings.text(.anthropic)).tag(AIProvider.anthropic)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 390)
            }
            formRow(title: settings.text(.aiServiceURL)) {
                TextField(
                    settings.aiProvider == .anthropic
                        ? "https://api.anthropic.com/v1"
                        : "https://api.openai.com/v1",
                    text: $settings.aiEndpoint
                )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 390)
            }
            formRow(title: settings.text(.aiModel)) {
                TextField(settings.aiProvider == .anthropic ? "claude-model-name" : "model-name", text: $settings.aiModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 390)
            }
            formRow(title: settings.text(.aiAPIKey)) {
                SecureField("sk-…", text: $settings.aiAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 390)
            }
            Text(settings.text(.aiAPIKeyHint))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 150)
        }
    }

    private var archiveSettings: some View {
        settingsPage(title: settings.text(.archiveSettings), subtitle: settings.text(.archiveSettingsHint)) {
            formRow(title: settings.text(.obsidianBackup)) {
                Toggle("", isOn: $settings.obsidianBackupEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            formRow(title: settings.text(.obsidianFolder)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(settings.obsidianVaultPath.isEmpty ? settings.text(.noFolderSelected) : settings.obsidianVaultPath)
                            .font(.system(size: 11))
                            .foregroundStyle(settings.obsidianVaultPath.isEmpty ? .secondary : .primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(width: 280, alignment: .leading)
                        Button(settings.text(.chooseFolder)) { chooseObsidianFolder() }
                    }
                    Text(settings.text(.obsidianBackupHint))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let url = store.lastObsidianBackupURL {
                Label("\(settings.text(.lastBackup)): \(url.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                    .padding(.leading, 150)
            } else if let failure = store.lastObsidianBackupError {
                Label("\(settings.text(.backupFailed)): \(obsidianFailureText(failure))", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.leading, 150)
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

    private func settingsPage<Content: View>(title _: String, subtitle _: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            content()
        }
    }

    private func formRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 132, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func opacityRow(_ title: String, value: Binding<Double>) -> some View {
        formRow(title: title) {
            Slider(value: value, in: 0.20...1.0, step: 0.01)
                .frame(width: 285)
            Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
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
