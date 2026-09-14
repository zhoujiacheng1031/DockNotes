import AppKit
import SwiftUI

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

    private var deckContentHeight: CGFloat {
        let controlCount = overflowNotes.isEmpty ? 2 : 3
        let controlsHeight = CGFloat(controlCount * 29 + max(0, controlCount - 1) * 7 + 10)
        return CGFloat(plan.slots.count) * DeckLayout.tabHeight + controlsHeight
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
                                symbol: EdgeTab.symbol(for: note.id),
                                isSelected: note.id == store.activeNoteID && !store.isExpanded,
                                edge: settings.deckEdge
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.select(note.id)
                            }
                            .help(note.title)
                            .accessibilityLabel(note.title)
                            .accessibilityAddTraits(.isButton)
                            .modifier(
                                LocalTabDragModifier(
                                    enabled: !isDesignPreview,
                                    noteID: note.id,
                                    slot: slot,
                                    slotCount: plan.slots.count,
                                    store: store,
                                    dragCoordinator: tabDrag
                                )
                            )
                            .offset(y: CGFloat(slot) * DeckLayout.tabHeight)
                            .zIndex(tabDrag.noteID == note.id ? 100 : Double(plan.slots.count - slot))
                        }
                    }
                    .frame(
                        width: DeckLayout.windowWidth,
                        height: CGFloat(plan.slots.count) * DeckLayout.tabHeight,
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
                            .buttonStyle(.plain)
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
        .buttonStyle(.plain)
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

    func beginSettling(destinationSlot: Int, translation: CGFloat, noteID: DockNote.ID) {
        guard self.noteID == noteID else { return }
        lastTranslation = translation
        targetSlot = destinationSlot
        settlingOffset = DeckLayout.dragResidual(
            originSlot: sourceSlot,
            currentSlot: destinationSlot,
            translation: translation
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
            targetSlot: dragCoordinator.targetSlot
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
                                slotCount: slotCount
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
                                slotCount: slotCount
                            )
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                dragCoordinator.beginSettling(
                                    destinationSlot: destination,
                                    translation: value.translation.height,
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
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
    let symbol: String
    let isSelected: Bool
    let edge: DeckEdge

    static let symbols = [
        "checklist",
        "lightbulb",
        "person.2",
        "graduationcap",
        "doc.text",
        "photo",
        "bookmark"
    ]

    static func symbol(for noteID: DockNote.ID) -> String {
        let stableIndex = noteID.uuidString.unicodeScalars.reduce(0) { partial, scalar in
            (partial + Int(scalar.value)) % symbols.count
        }
        return symbols[stableIndex]
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                note.gradient
                LinearGradient(
                    colors: [Color.white.opacity(0.34), Color.white.opacity(0.06), Color.black.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 3) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.black.opacity(0.70))
                        .frame(width: 22, height: 20)

                    Text(note.title)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 61)
                        .rotationEffect(.degrees(90))
                        .frame(width: DeckLayout.tabWidth, height: 64)
                }

                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(0.88))
                        .frame(width: 2.5, height: 42)
                        .shadow(color: Color.white.opacity(0.65), radius: 3)
                        .frame(maxWidth: .infinity, alignment: edge == .right ? .leading : .trailing)
                        .padding(edge == .right ? .leading : .trailing, 3)
                }
            }
            .frame(width: DeckLayout.tabWidth, height: DeckLayout.tabHeight - 4)
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
            .offset(x: isSelected ? (edge == .right ? -4 : 4) : 0)
            .saturation(isSelected ? 1.10 : 0.96)
            .animation(.easeOut(duration: 0.15), value: isSelected)
        }
        .frame(
            width: DeckLayout.windowWidth,
            height: DeckLayout.tabHeight,
            alignment: edge == .right ? .trailing : .leading
        )
    }
}

private struct TuckyTabShape: Shape {
    let edge: DeckEdge

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 10
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

private struct NoteCard: View {
    let note: DockNote
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    var closeAction: (() -> Void)? = nil
    @StateObject private var dictation = DictationController()
    @State private var isDuePresented = false
    @State private var isFindPresented = false
    @State private var isAIInfoPresented = false
    @State private var isCustomColorPresented = false
    @State private var isFontPresented = false
    @State private var searchQuery = ""

    private let palette = NotePalette.gradients

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                NoteSpine(note: note)
                VStack(spacing: 0) {
                    toolbar
                    Divider().opacity(0.13)
                    editor
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
    }

    private var toolbar: some View {
        HStack(spacing: 7) {
            let isDesktopNote = store.desktopNoteIDs.contains(note.id)
            tinyButton(
                isDesktopNote ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                label: settings.text(isDesktopNote ? .returnToEdge : .openOnDesktop),
                isActive: isDesktopNote
            ) {
                store.presentOnDesktop(note.id)
            }

            TextField("", text: Binding(
                get: { store.note(id: note.id)?.title ?? note.title },
                set: { store.updateTitle($0, for: note.id) }
            ))
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .bold))
                .accessibilityLabel("Note title")

            Button { isDuePresented.toggle() } label: {
                Label(
                    note.dueDate?.formatted(date: .numeric, time: .omitted) ?? settings.text(.due),
                    systemImage: "calendar"
                )
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
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
            tinyButton("magnifyingglass", label: settings.text(.search)) { isFindPresented.toggle() }
                .popover(isPresented: $isFindPresented, arrowEdge: .top) {
                    FindPopover(noteBody: note.body, query: $searchQuery, settings: settings)
                }
            tinyButton(dictation.isRecording ? "stop.circle.fill" : "mic", label: settings.text(.dictate)) {
                let locale = settings.language == .english ? Locale(identifier: "en-US") : Locale(identifier: "zh-CN")
                let base = note.body
                dictation.toggle(locale: locale) { transcript in
                    store.updateBodyWithDictation(base: base, transcript: transcript, for: note.id)
                }
            }
            .foregroundStyle(dictation.isRecording ? Color.red : Color.black.opacity(0.46))
            tinyButton("sparkles", label: settings.text(.askAI)) { isAIInfoPresented.toggle() }
                .popover(isPresented: $isAIInfoPresented, arrowEdge: .top) {
                    AIAssistantPopover(note: note, store: store, settings: settings)
                }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    private var editor: some View {
        StableTextEditor(
            text: Binding(
                get: { store.note(id: note.id)?.body ?? note.body },
                set: { store.updateBody($0, for: note.id) }
            ),
            fontStyle: note.fontStyle,
            fontSize: note.fontSize
        )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityLabel(note.title)
    }

    private var footer: some View {
        HStack(spacing: 8) {
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
                .buttonStyle(.plain)
                .accessibilityLabel("\(gradient.startHex) – \(gradient.endHex)")
            }

            Divider().frame(height: 17).padding(.horizontal, 2)
            Button { isCustomColorPresented.toggle() } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 10))
                    .frame(width: 23, height: 20)
            }
            .buttonStyle(.plain)
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
            .buttonStyle(.plain)
            .help(settings.text(.font))
            .accessibilityLabel(settings.text(.font))
            .popover(isPresented: $isFontPresented, arrowEdge: .bottom) {
                FontEditorPopover(note: note, store: store, settings: settings)
            }

            Spacer()
            footerButton(settings.text(.archive)) {
                store.archive(
                    note.id,
                    obsidianDirectory: settings.obsidianVaultURL,
                    obsidianBackupEnabled: settings.obsidianBackupEnabled
                )
            }
            footerButton(settings.text(.delete)) { store.delete(note.id) }
            footerButton(settings.text(.close)) {
                if let closeAction {
                    closeAction()
                } else {
                    store.collapseActive(keepDeckOpen: settings.keepDeckOpen)
                }
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 43)
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
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.black.opacity(0.88) : Color.black.opacity(0.46))
        .help(label)
        .accessibilityLabel(label)
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.075), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct StableTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontStyle: NoteFontStyle
    let fontSize: Double

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textColor = NSColor.black.withAlphaComponent(0.82)
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        applyFont(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let maxLocation = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, maxLocation), length: 0))
        }
        applyFont(to: textView)
    }

    private func applyFont(to textView: NSTextView) {
        let size = CGFloat(min(max(fontSize, 11), 28))
        let system = NSFont.systemFont(ofSize: size)
        switch fontStyle {
        case .system:
            textView.font = system
        case .rounded:
            textView.font = system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        case .serif:
            textView.font = system.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        case .monospaced:
            textView.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .handwriting:
            textView.font = NSFont(name: "Noteworthy", size: size) ?? system
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if text.wrappedValue != textView.string { text.wrappedValue = textView.string }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let result = OrderedListEditing.insertingReturn(
                in: textView.string,
                selectedRange: textView.selectedRange()
            )
            textView.string = result.text
            textView.setSelectedRange(result.selectedRange)
            if text.wrappedValue != result.text { text.wrappedValue = result.text }
            return true
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
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.70))
                .lineLimit(1)
                .frame(width: 160)
                .rotationEffect(.degrees(90))
        }
        .frame(width: 32)
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
                    get: { note.dueDate ?? Date() },
                    set: { store.setDueDate($0, for: note.id) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            HStack {
                Spacer()
                Button(settings.text(.clear)) { store.setDueDate(nil, for: note.id) }
            }
        }
        .padding(14)
        .frame(width: 250)
    }
}

private struct FindPopover: View {
    let noteBody: String
    @Binding var query: String
    @ObservedObject var settings: AppSettings

    private var matchCount: Int {
        guard !query.isEmpty else { return 0 }
        return noteBody.lowercased().components(separatedBy: query.lowercased()).count - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(settings.text(.findInNote)).font(.system(size: 13, weight: .bold))
            TextField(settings.text(.search), text: $query)
                .textFieldStyle(.roundedBorder)
            Text(String(format: settings.text(.matches), matchCount))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 240)
    }

}

private struct AIAssistantPopover: View {
    let note: DockNote
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: AppSettings
    @State private var prompt = ""
    @State private var response = ""
    @State private var errorMessage = ""
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(settings.text(.askAI), systemImage: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                if !settings.aiModel.isEmpty {
                    Text(settings.aiModel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if settings.isAIConfigured {
                TextEditor(text: $prompt)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(height: 68)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text(settings.text(.aiPrompt))
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 15)
                                .allowsHitTesting(false)
                        }
                    }

                HStack {
                    Spacer()
                    Button(settings.text(.send)) { sendRequest() }
                        .buttonStyle(.borderedProminent)
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }

                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(settings.text(.aiResponse)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } else if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !response.isEmpty {
                    Text(settings.text(.aiResponse)).font(.system(size: 11, weight: .semibold))
                    ScrollView {
                        Text(response)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 145)
                    HStack {
                        Button(settings.text(.copy)) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(response, forType: .string)
                        }
                        Spacer()
                        Button(settings.text(.appendToNote)) {
                            let currentBody = store.note(id: note.id)?.body ?? note.body
                            let separator = currentBody.isEmpty || currentBody.hasSuffix("\n") ? "" : "\n\n"
                            store.updateBody(currentBody + separator + response, for: note.id)
                        }
                    }
                }
            } else {
                Text(settings.text(.aiNotConfigured))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(settings.text(.openAISettings)) {
                    store.collapseActive(keepDeckOpen: settings.keepDeckOpen)
                    store.presentSettings()
                }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 360)
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

    private var displayedNotes: [DockNote] {
        collection == .all ? store.notes : store.archivedNotes
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

            if displayedNotes.isEmpty {
                ContentUnavailableView(
                    settings.text(.noArchivedNotes),
                    systemImage: "archivebox",
                    description: Text(settings.text(.archivedNotes))
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
                                    Text(note.title.isEmpty ? settings.text(.newNote) : note.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
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
                                    Button(settings.text(.restore)) { store.restoreArchived(note.id) }
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
        }
        .buttonStyle(.plain)
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

    private func settingsPage<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 20, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Divider()
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
