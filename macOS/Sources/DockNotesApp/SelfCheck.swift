import Darwin
import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications

@MainActor
enum SelfCheck {
    static func runWorkspaceManagementPresentationRegression() {
        for visible in [
            NSRect(x: 0, y: 0, width: 620, height: 900),
            NSRect(x: 100, y: 40, width: 1440, height: 900),
            NSRect(x: 0, y: 0, width: 800, height: 550)
        ] {
            let size = PanelCoordinator.workspaceManagementContentSize(for: visible)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            let outerSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
            let frame = PanelCoordinator.workspaceManagementFrame(in: visible, windowSize: outerSize)
            check(visible.contains(frame),
                  "the workspace management window fits and centers on a visible screen")
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockNotes-workspace-presentation-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NotesStore(fileURL: folder.appendingPathComponent("notes.json"))
        store.presentWorkspaceManagement()
        check(store.isWorkspaceManagementPresented,
              "the workspace switcher can request an independent management window")
    }

    static func runSideLabelClickRegression() {
        let surface = TabPointerTrackingView(frame: NSRect(x: 0, y: 0, width: 48, height: 190))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 48, height: 190),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = surface
        panel.orderBack(nil)
        defer { panel.orderOut(nil) }
        var clickCount = 0
        var trackingHeld = false
        surface.onClick = { clickCount += 1 }
        surface.onTrackingChanged = { tracking, _ in trackingHeld = tracking }
        let point = NSPoint(x: 24, y: 95)
        func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1
            )!
        }
        surface.mouseDown(with: event(.leftMouseDown, at: point))
        NotificationCenter.default.post(
            name: .dockNotesPointerReleased,
            object: event(.leftMouseUp, at: point)
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        check(clickCount == 1 && !trackingHeld,
              "a side label opens when the panel misses mouse-up after a normal click")

        surface.mouseDown(with: event(.leftMouseDown, at: point))
        NotificationCenter.default.post(
            name: .dockNotesPointerReleased,
            object: event(.leftMouseUp, at: point)
        )
        surface.mouseUp(with: event(.leftMouseUp, at: point))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        check(clickCount == 2 && !trackingHeld,
              "a normally delivered mouse-up opens exactly once")

        surface.mouseDown(with: event(.leftMouseDown, at: point))
        NotificationCenter.default.post(
            name: .dockNotesPointerReleased,
            object: event(.leftMouseUp, at: NSPoint(x: 80, y: point.y))
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        check(clickCount == 2 && !trackingHeld,
              "releasing outside the label does not open a note")

        var endedTranslation: CGFloat?
        surface.onDragEnded = { translation, _ in endedTranslation = translation }
        surface.mouseDown(with: event(.leftMouseDown, at: point))
        surface.mouseDragged(with: event(.leftMouseDragged, at: NSPoint(x: point.x, y: point.y - 30)))
        NotificationCenter.default.post(
            name: .dockNotesPointerReleased,
            object: event(.leftMouseUp, at: NSPoint(x: point.x, y: point.y - 30))
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        check(endedTranslation == 30 && clickCount == 2 && !trackingHeld,
              "a recovered drag completes without opening a note")
        check(
            !PanelCoordinator.localClickIsOutsideApp(
                hasWindow: false,
                point: NSPoint(x: panel.frame.midX, y: panel.frame.midY),
                appWindowFrames: [panel.frame]
            ),
            "an app activation over the edge panel cannot close the selected note"
        )
    }

    static func runInteractionRegressions() {
        let settingsWindowProbe = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let glassChromeProbe = DockNotesGlassWindowChromeView(frame: .zero)
        settingsWindowProbe.contentView?.addSubview(glassChromeProbe)
        check(
            settingsWindowProbe.isMovableByWindowBackground
                && settingsWindowProbe.titlebarAppearsTransparent
                && !settingsWindowProbe.isOpaque,
            "glass utility windows keep their background drag region and transparent titlebar"
        )
        check(
            PanelCoordinator.transparentWindowGlassMode == .stableMaterial,
            "transparent note and edge windows use the stable glass renderer"
        )

        if !CommandLine.arguments.contains("--format-only")
            && !CommandLine.arguments.contains("--desktop-only") {
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("DockNotes-OutsideClick-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: file) }
            let editedNote = DockNote(title: "Edited tab", body: "Before", isPinned: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try? encoder.encode([editedNote]).write(to: file)
            let store = NotesStore(fileURL: file)
            store.select(editedNote.id)
            store.updateBody("After editing", for: editedNote.id)
            store.handleOutsideClick(keepDeckOpen: true)
            check(store.isExpanded, "a pinned note stays open after a desktop click")
            let pinnedPlan = DeckLayout.plan(
                notes: store.notes,
                activeNoteID: store.activeNoteID,
                isExpanded: store.isExpanded,
                availableHeight: 720
            )
            check(
                pinnedPlan.slots.contains(editedNote.id),
                "the edited pinned note remains visible as a side label after clicking the desktop"
            )

            let overflowFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("DockNotes-Edited-Overflow-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: overflowFile) }
            let overflowNotes = (0..<8).map { DockNote(title: "Tab \($0)", body: "Before") }
            try? encoder.encode(overflowNotes).write(to: overflowFile)
            let overflowStore = NotesStore(fileURL: overflowFile)
            let editedOverflowNote = overflowNotes[7]
            overflowStore.select(editedOverflowNote.id)
            overflowStore.updateBody("After editing", for: editedOverflowNote.id)
            overflowStore.handleOutsideClick(keepDeckOpen: true)
            let collapsedPlan = DeckLayout.plan(
                notes: overflowStore.notes,
                activeNoteID: overflowStore.activeNoteID,
                isExpanded: overflowStore.isExpanded,
                availableHeight: 720,
                preferredVisibleCount: 4
            )
            check(
                collapsedPlan.slots.contains(editedOverflowNote.id),
                "the note just edited returns to a visible side-label slot after clicking the desktop"
            )

            let openedNote = DockNote(title: "Opened side label", body: "Editing")
            let openedPlan = DeckLayout.plan(
                notes: [openedNote, DockNote(title: "Second label")],
                activeNoteID: openedNote.id,
                isExpanded: true,
                availableHeight: 720,
                preferredVisibleCount: 4
            )
            check(
                openedPlan.slots.contains(openedNote.id),
                "opening an unpinned side label never removes that label from the visible deck"
            )
            check(
                EdgeTabSelection.isSelected(noteID: openedNote.id, activeNoteID: openedNote.id),
                "the open side label remains selected for accessibility without changing its paper styling"
            )
        }

        if !CommandLine.arguments.contains("--pinned-only")
            && !CommandLine.arguments.contains("--desktop-only") {
            let probe = InteractionFormatProbe()
            let host = NSHostingView(rootView: InteractionFormatProbeView(probe: probe)
                .frame(width: 320, height: 140))
            host.frame = NSRect(x: 0, y: 0, width: 320, height: 140)
            let panel = NSPanel(contentRect: host.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.contentView = host
            panel.alphaValue = 0
            panel.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            host.layoutSubtreeIfNeeded()
            let editor = descendants(of: host, as: NSTextView.self)[0]
            editor.setSelectedRange(NSRange(location: 6, length: 5))
            probe.request = NoteFormatRequest(command: .underline)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
            host.layoutSubtreeIfNeeded()
            check(
                ((editor.textStorage?.attribute(.underlineStyle, at: 7, effectiveRange: nil) as? NSNumber)?.intValue ?? 0) != 0,
                "underline changes the selected text visibly"
            )
            check(
                (probe.rtfData.flatMap { try? NSAttributedString(
                    data: $0,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                ) }.flatMap { $0.attribute(.underlineStyle, at: 7, effectiveRange: nil) as? NSNumber }?.intValue ?? 0) != 0,
                "underline persists in the note's rich-text data"
            )
            panel.orderOut(nil)
            for (x, key, label) in [
                (CGFloat(250), NSAttributedString.Key.underlineStyle, "underline"),
                (CGFloat(275), NSAttributedString.Key.strikethroughStyle, "strikethrough")
            ] {
                    let file = FileManager.default.temporaryDirectory
                        .appendingPathComponent("DockNotes-Format-Click-\(UUID().uuidString).json")
                    let note = DockNote(title: "Format probe", body: "Hello world")
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    try? encoder.encode([note]).write(to: file)
                    let store = NotesStore(fileURL: file)
                    let defaults = UserDefaults(suiteName: "DockNotes.FormatClick.\(UUID().uuidString)")!
                    let settings = AppSettings(defaults: defaults)
                    let noteHost = NSHostingView(rootView: NoteCard(note: note, store: store, settings: settings)
                        .frame(width: 460, height: 380))
                    noteHost.frame = NSRect(x: 0, y: 0, width: 460, height: 380)
                    let notePanel = NSPanel(contentRect: noteHost.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                    notePanel.contentView = noteHost
                    notePanel.alphaValue = 1
                    notePanel.orderBack(nil)
                    noteHost.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                    let noteEditor = descendants(of: noteHost, as: NSTextView.self)[0]
                    notePanel.makeFirstResponder(noteEditor)
                    noteEditor.setSelectedRange(NSRange(location: 6, length: 5))
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        let event = NSEvent.mouseEvent(
                            with: type, location: NSPoint(x: x, y: 22), modifierFlags: [], timestamp: 0,
                            windowNumber: notePanel.windowNumber, context: nil, eventNumber: 0,
                            clickCount: 1, pressure: 1
                        )!
                        notePanel.sendEvent(event)
                    }
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.06))
                    let persisted = store.note(id: note.id)?.bodyRTF.flatMap {
                        try? NSAttributedString(
                            data: $0,
                            options: [.documentType: NSAttributedString.DocumentType.rtf],
                            documentAttributes: nil
                        )
                    }
                    check(
                        ((noteEditor.textStorage?.attribute(key, at: 7, effectiveRange: nil) as? NSNumber)?.intValue ?? 0) != 0
                            && ((persisted?.attribute(key, at: 7, effectiveRange: nil) as? NSNumber)?.intValue ?? 0) != 0,
                        "clicking the \(label) toolbar button visibly formats and persists selected text"
                    )
                    notePanel.orderOut(nil)
                    try? FileManager.default.removeItem(at: file)
            }
        }

        if !CommandLine.arguments.contains("--pinned-only")
            && !CommandLine.arguments.contains("--format-only") {
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("DockNotes-Desktop-Drag-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: file) }
            let store = NotesStore(fileURL: file)
            let defaults = UserDefaults(suiteName: "DockNotes.DesktopDrag.\(UUID().uuidString)")!
            let settings = AppSettings(defaults: defaults)
            let coordinator = PanelCoordinator(store: store, settings: settings)
            store.presentOnDesktop(store.notes[0].id)
            let window = coordinator.makeDesktopNoteWindow(for: store.notes[0].id)
            window.orderBack(nil)
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
            let handles = window.contentView.map { descendants(of: $0, as: NSView.self) } ?? []
            let dragHandles = handles.filter { $0.accessibilityIdentifier() == "DockNotesDesktopDragHandle" }
            check(dragHandles.count == 1, "a detached desktop note exposes a dedicated draggable handle")
            let dragRegions = handles.filter { $0.accessibilityIdentifier() == "DockNotesDesktopDragRegion" }
            check(
                dragRegions.contains { $0.bounds.height >= window.contentLayoutRect.height - 4 },
                "a detached desktop note can be dragged from its full-height colored spine"
            )
            if let region = dragRegions.first(where: { $0.bounds.height >= window.contentLayoutRect.height - 4 })
                as? DesktopWindowDragView,
               let contentView = window.contentView {
                let regionCenter = region.convert(
                    NSPoint(x: region.bounds.midX, y: region.bounds.midY),
                    to: contentView
                )
                check(
                    contentView.hitTest(regionCenter) === region,
                    "the desktop note's visible spine routes real pointer events to the drag surface"
                )
                let start = region.convert(
                    NSPoint(x: region.bounds.midX, y: region.bounds.midY),
                    to: nil
                )
                let originalOrigin = window.frame.origin
                func regionDragEvent(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
                    NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                        clickCount: 1, pressure: 1
                    )!
                }
                region.mouseDown(with: regionDragEvent(.leftMouseDown, start))
                region.mouseDragged(with: regionDragEvent(
                    .leftMouseDragged, NSPoint(x: start.x + 35, y: start.y + 20)
                ))
                check(
                    abs(window.frame.minX - originalOrigin.x - 35) < 2
                        && abs(window.frame.minY - originalOrigin.y - 20) < 2,
                    "dragging the desktop note's visible spine moves the native window"
                )
                region.mouseUp(with: regionDragEvent(.leftMouseUp, start))
            }
            let topDragRegions = handles.filter {
                $0.accessibilityIdentifier() == "DockNotesDesktopTopDragRegion"
            }
            check(
                topDragRegions.contains {
                    $0.bounds.width >= window.contentLayoutRect.width - 60 && $0.bounds.height >= 30
                },
                "the detached desktop note exposes its full top bar as a drag region"
            )
            if let topRegion = topDragRegions.first as? DesktopWindowDragView,
               let contentView = window.contentView {
                var draggableLocalPoint: NSPoint?
                var localX: CGFloat = 2
                while localX < topRegion.bounds.width - 2 && draggableLocalPoint == nil {
                    var localY: CGFloat = 2
                    while localY < topRegion.bounds.height - 2 {
                        let localPoint = NSPoint(x: localX, y: localY)
                        let point = topRegion.convert(localPoint, to: contentView)
                        if contentView.hitTest(point) === topRegion {
                            draggableLocalPoint = localPoint
                            break
                        }
                        localY += 3
                    }
                    localX += 3
                }
                check(
                    draggableLocalPoint != nil,
                    "the desktop note top bar leaves real draggable space around its controls"
                )
                if let draggableLocalPoint {
                    let start = topRegion.convert(draggableLocalPoint, to: nil)
                    let originalOrigin = window.frame.origin
                    func topDragEvent(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
                        NSEvent.mouseEvent(
                            with: type, location: point, modifierFlags: [], timestamp: 0,
                            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                            clickCount: 1, pressure: 1
                        )!
                    }
                    topRegion.mouseDown(with: topDragEvent(.leftMouseDown, start))
                    topRegion.mouseDragged(with: topDragEvent(
                        .leftMouseDragged, NSPoint(x: start.x + 30, y: start.y + 18)
                    ))
                    check(
                        abs(window.frame.minX - originalOrigin.x - 30) < 2
                            && abs(window.frame.minY - originalOrigin.y - 18) < 2,
                        "dragging empty space in the desktop note's top bar moves the native window"
                    )
                    topRegion.mouseUp(with: topDragEvent(.leftMouseUp, start))
                }
            }
            if let handle = dragHandles.first as? DesktopWindowDragView {
                let start = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
                let originalOrigin = window.frame.origin
                func dragEvent(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
                    NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                        clickCount: 1, pressure: 1
                    )!
                }
                handle.mouseDown(with: dragEvent(.leftMouseDown, start))
                handle.mouseDragged(with: dragEvent(
                    .leftMouseDragged, NSPoint(x: start.x + 40, y: start.y + 25)
                ))
                check(
                    abs(window.frame.minX - originalOrigin.x - 40) < 2
                        && abs(window.frame.minY - originalOrigin.y - 25) < 2,
                    "dragging the desktop note's handle moves the native window smoothly"
                )
                handle.mouseUp(with: dragEvent(.leftMouseUp, start))
            }
            window.orderOut(nil)
        }
    }

    static func renderAIPreview(to url: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent("notes.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let previewNote = DockNote(
            title: "产品发布清单",
            body: "整理发布说明、检查归档备份，并确认中英文界面。",
            colorHex: "#F4DC84",
            gradientEndHex: "#79BEDF"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let companionNotes = [
            DockNote(title: "发布前清单", colorHex: "#F4DC84", gradientEndHex: "#9FC6B2"),
            DockNote(title: "灵感收集", colorHex: "#A8D9F0", gradientEndHex: "#C7B9E8"),
            DockNote(title: "会议记录", colorHex: "#F6D38C", gradientEndHex: "#E7B8CE"),
            DockNote(title: "学习笔记", colorHex: "#C7B9E8", gradientEndHex: "#9FC6B2")
        ]
        try? encoder.encode([previewNote] + companionNotes).write(to: file)
        let store = NotesStore(fileURL: file)
        store.select(previewNote.id)
        let defaults = UserDefaults(suiteName: "DockNotes.AIPreview.\(UUID().uuidString)")!
        defaults.set("https://api.openai.com/v1", forKey: "docknotes.ai.endpoint")
        defaults.set("gpt-5-mini", forKey: "docknotes.ai.model")
        let settings = AppSettings(defaults: defaults)
        let renderer = ImageRenderer(
            content: NoteCard(
                note: previewNote,
                store: store,
                settings: settings,
                startsInAIMode: true,
                isDesignPreview: true
            )
            .frame(width: 460, height: 380)
            .environment(\.colorScheme, .light)
        )
        renderer.proposedSize = ProposedViewSize(width: 460, height: 380)
        renderer.scale = 2
        write(renderer: renderer, to: url, failureMessage: "Could not render AI preview")
    }

    static func renderDesktopPreview(to url: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent("notes.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let previewNote = DockNote(
            title: "记录 DockNotes 的修改",
            body: "桌面便签缩放预览",
            colorHex: "#E4F6AA",
            gradientEndHex: "#FF81A6",
            dueDate: Date().addingTimeInterval(7_200)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let companionNotes = [
            DockNote(title: "发布前清单", colorHex: "#F4DC84", gradientEndHex: "#9FC6B2"),
            DockNote(title: "灵感收集", colorHex: "#A8D9F0", gradientEndHex: "#C7B9E8"),
            DockNote(title: "会议记录", colorHex: "#F6D38C", gradientEndHex: "#E7B8CE"),
            DockNote(title: "学习笔记", colorHex: "#C7B9E8", gradientEndHex: "#9FC6B2")
        ]
        try? encoder.encode([previewNote] + companionNotes).write(to: file)
        let store = NotesStore(fileURL: file)
        store.select(previewNote.id)
        let defaults = UserDefaults(suiteName: "DockNotes.DesktopPreview.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let renderer = ImageRenderer(
            content: ZStack {
                LinearGradient(
                    colors: [Color(hex: "#C8DCEB"), Color(hex: "#F2DFC5"), Color(hex: "#D8CDEA")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 330, height: 330)
                    .blur(radius: 42)
                    .offset(x: 245, y: -190)
                Circle()
                    .fill(Color(hex: "#F6C7A8").opacity(0.38))
                    .frame(width: 300, height: 300)
                    .blur(radius: 48)
                    .offset(x: -250, y: 210)
                HStack(alignment: .center, spacing: 16) {
                    NoteCard(
                        note: previewNote,
                        store: store,
                        settings: settings,
                        startsInAIMode: true,
                        isDesignPreview: true
                    )
                    .frame(width: 700, height: 520)

                    DeckWindowView(
                        store: store,
                        settings: settings,
                        availableHeight: 520,
                        isDesignPreview: true
                    )
                    .frame(width: DeckLayout.windowWidth, height: 520)
                }
                .padding(28)
            }
            .frame(width: 900, height: 600)
            .environment(\.colorScheme, .light)
        )
        renderer.proposedSize = ProposedViewSize(width: 900, height: 600)
        renderer.scale = 2
        write(renderer: renderer, to: url, failureMessage: "Could not render desktop preview")
    }

    static func renderTabHoverPreview(to url: URL) {
        let previewNote = DockNote(
            title: "这是一个标题较长、需要在悬浮时完整展示的项目便签",
            body: "第一行摘要\n第二行包含更多上下文，方便不打开便签也能快速确认内容。",
            colorHex: "#F4DC84",
            gradientEndHex: "#79BEDF",
            isPinned: true,
            dueDate: Date().addingTimeInterval(3_600)
        )
        let renderer = ImageRenderer(
            content: EdgeTabHoverCard(note: previewNote, language: .simplifiedChinese)
                .environment(\.colorScheme, .light)
        )
        renderer.proposedSize = ProposedViewSize(width: 236, height: 180)
        renderer.scale = 2
        write(renderer: renderer, to: url, failureMessage: "Could not render tab hover preview")
    }

    static func renderDeckPreview(
        to url: URL,
        visibleTabCount: Int = DeckLayout.defaultVisibleTabs,
        availableHeight: CGFloat? = nil,
        noteCount: Int = 11
    ) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent("notes.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let previewTitles = ["发布前清单", "灵感收集", "会议记录", "学习笔记", "项目资料", "生活灵感", "New note", "旅行计划", "阅读清单", "产品想法", "周末采购"]
        let previewNotes = previewTitles.prefix(max(0, noteCount)).enumerated().map { index, title in
            let gradient = NotePalette.gradients[index % NotePalette.gradients.count]
            let dueDate: Date? = switch index {
            case 0: Date().addingTimeInterval(3_600)
            case 1: Date().addingTimeInterval(-3_600)
            default: nil
            }
            return DockNote(title: title, colorHex: gradient.startHex, gradientEndHex: gradient.endHex, dueDate: dueDate)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(previewNotes).write(to: file)
        let store = NotesStore(fileURL: file)
        if noteCount == 0 {
            _ = store.renameWorkspace(store.activeWorkspaceID, to: "工作")
        }
        let defaults = UserDefaults(suiteName: "DockNotes.DesignPreview.\(UUID().uuidString)")!
        defaults.set(AppSettings.clampVisibleTabCount(visibleTabCount), forKey: "docknotes.deck.visibleTabCount")
        let settings = AppSettings(defaults: defaults)
        let previewHeight = availableHeight ?? (visibleTabCount >= 7 ? 900 : 800)
        let renderer = ImageRenderer(
            content: DeckWindowView(store: store, settings: settings, availableHeight: previewHeight, isDesignPreview: true)
                .environment(\.colorScheme, .light)
        )
        renderer.proposedSize = ProposedViewSize(width: DeckLayout.windowWidth, height: previewHeight)
        renderer.scale = 2
        write(renderer: renderer, to: url, failureMessage: "Could not render deck preview")
    }

    static func renderWorkspacePreview(to url: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent("notes.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = NotesStore(fileURL: file)
        _ = store.renameWorkspace(store.activeWorkspaceID, to: "工作")
        _ = store.createWorkspace(name: "个人", colorHex: "#E7B8CE", makeActive: false)
        _ = store.createWorkspace(name: "项目", colorHex: "#9FC6B2", makeActive: false)
        let defaults = UserDefaults(suiteName: "DockNotes.WorkspacePreview.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let renderer = ImageRenderer(
            content: WorkspaceSwitcherView(
                store: store,
                settings: settings,
                draggedNoteID: nil,
                dropTargetID: nil,
                reportDropFrame: { _, _ in },
                dismiss: {},
                reportsDropFrames: false
            )
            .background(Color.white)
            .environment(\.colorScheme, .light)
        )
        renderer.proposedSize = ProposedViewSize(width: 248, height: 203)
        renderer.scale = 2
        write(renderer: renderer, to: url, failureMessage: "Could not render workspace preview")
    }

    static func renderWorkspaceManagementPreview(to url: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent("notes.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = NotesStore(fileURL: file)
        _ = store.createWorkspace(name: "工作", colorHex: "#A8D9F0", makeActive: false)
        _ = store.createWorkspace(name: "个人", colorHex: "#E7B8CE", makeActive: false)
        let defaults = UserDefaults(suiteName: "DockNotes.WorkspaceManagementPreview.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let renderer = ImageRenderer(
            content: WorkspaceManagementView(store: store, settings: settings)
                .environment(\.colorScheme, .light)
        )
        renderer.proposedSize = ProposedViewSize(width: 600, height: 480)
        renderer.scale = 2
        write(renderer: renderer, to: url, failureMessage: "Could not render workspace management preview")
    }

    static func renderTaskCenterPreview(to url: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent("notes.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let notes = [
            DockNote(title: "发布前清单", body: "☐ 检查玻璃界面\n☐ 完成发布准备"),
            DockNote(title: "工作计划", body: "☐ 整理工作区")
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(notes).write(to: file)
        let store = NotesStore(fileURL: file)
        let defaults = UserDefaults(suiteName: "DockNotes.TaskCenterPreview.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let renderer = ImageRenderer(
            content: TaskCenterView(store: store, settings: settings)
                .environment(\.colorScheme, .light)
        )
        renderer.proposedSize = ProposedViewSize(width: 860, height: 560)
        renderer.scale = 2
        write(renderer: renderer, to: url, failureMessage: "Could not render task center preview")
    }

    static func run() {
        runInteractionRegressions()
        check(AppSettings.clamp(0.05) == 0.20, "lower opacity clamp")
        check(AppSettings.clamp(0.64) == 0.64, "middle opacity value")
        check(AppSettings.clamp(1.40) == 1.00, "upper opacity clamp")
        check(AppSettings.clampVisibleTabCount(0) == 1, "visible tab count has a lower bound")
        check(AppSettings.clampVisibleTabCount(8) == 7, "visible tab count has a seven-tab upper bound")

        let aiPersistenceDefaults = UserDefaults(suiteName: "DockNotes.AIPersistence.\(UUID().uuidString)")!
        let configuredAISettings = AppSettings(defaults: aiPersistenceDefaults)
        check(!configuredAISettings.calendarSyncEnabled, "calendar sync is opt-in on a clean install")
        configuredAISettings.quickCaptureShortcut = .optionCommandSpace
        configuredAISettings.aiProvider = .anthropic
        configuredAISettings.aiEndpoint = "https://example.com/v1"
        configuredAISettings.aiModel = "claude-sonnet-5"
        configuredAISettings.taskRemindersEnabled = false
        configuredAISettings.dailySummaryEnabled = true
        configuredAISettings.dailySummaryMinutes = 21 * 60 + 45
        configuredAISettings.calendarSyncEnabled = true
        configuredAISettings.calendarIdentifier = "calendar-test-id"
        aiPersistenceDefaults.synchronize()
        let reloadedAISettings = AppSettings(defaults: aiPersistenceDefaults)
        check(
            reloadedAISettings.quickCaptureShortcut == .optionCommandSpace,
            "the selected global quick-capture shortcut persists across relaunches"
        )
        reloadedAISettings.reportQuickCaptureShortcutRegistration(false)
        check(
            reloadedAISettings.quickCaptureShortcutRegistrationFailed,
            "a global shortcut registration conflict remains visible in settings"
        )
        check(
            reloadedAISettings.aiProvider == .anthropic
                && reloadedAISettings.aiEndpoint == "https://example.com/v1"
                && reloadedAISettings.aiModel == "claude-sonnet-5",
            "AI provider, endpoint, and model survive a full settings reload"
        )
        check(
            !reloadedAISettings.taskRemindersEnabled
                && reloadedAISettings.dailySummaryEnabled
                && reloadedAISettings.dailySummaryMinutes == 21 * 60 + 45,
            "task reminder and daily summary preferences survive a full settings reload"
        )
        check(
            reloadedAISettings.calendarSyncEnabled
                && reloadedAISettings.calendarIdentifier == "calendar-test-id",
            "calendar sync remains off by default but persists an explicit enablement and target"
        )
        check(
            AppSettings.clampDailySummaryMinutes(-1) == 0
                && AppSettings.clampDailySummaryMinutes(24 * 60) == 23 * 60 + 59,
            "daily summary time remains inside a valid local day"
        )

        var deadlineCalendar = Calendar(identifier: .gregorian)
        deadlineCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let deadlineNow = Date(timeIntervalSince1970: 1_800_000_000)
        let todayDeadline = DeadlinePresentation.make(
            for: deadlineNow.addingTimeInterval(3_600),
            now: deadlineNow,
            calendar: deadlineCalendar,
            language: .english
        )
        let overdueDeadline = DeadlinePresentation.make(
            for: deadlineNow.addingTimeInterval(-3_600),
            now: deadlineNow,
            calendar: deadlineCalendar,
            language: .simplifiedChinese
        )
        check(todayDeadline.status == .today && todayDeadline.toolbarLabel.hasPrefix("Today"), "same-day deadlines show time in the note header")
        check(overdueDeadline.status == .overdue && overdueDeadline.edgeLabel.hasPrefix("!"), "overdue deadlines are visibly marked on edge tabs")
        let reminderID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        check(
            DueReminderScheduler.identifier(for: reminderID) == "docknotes.deadline.00000000-0000-0000-0000-000000000123",
            "deadline reminders use a stable per-note notification identifier"
        )
        let calendarReference = CalendarTaskReference(
            noteID: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            taskID: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            markerUTF16Offset: 0,
            occurrenceIndex: nil
        )
        let calendarDescriptor = CalendarEventDescriptor(
            stableID: "docknotes.calendar.task.policy-probe",
            title: "Policy probe",
            startDate: deadlineNow,
            endDate: deadlineNow.addingTimeInterval(CalendarTaskPlanner.eventDuration),
            reference: calendarReference
        )
        let calendarLedger = CalendarSyncLedgerEntry(
            stableID: calendarDescriptor.stableID,
            eventIdentifier: "event-primary",
            calendarIdentifier: "calendar-a",
            title: calendarDescriptor.title,
            startDate: calendarDescriptor.startDate,
            endDate: calendarDescriptor.endDate,
            reference: calendarReference
        )
        let calendarObserved = CalendarObservedEvent(
            eventIdentifier: "event-primary",
            stableID: calendarDescriptor.stableID,
            calendarIdentifier: "calendar-a",
            title: calendarDescriptor.title,
            startDate: calendarDescriptor.startDate,
            endDate: calendarDescriptor.endDate
        )
        let calendarDuplicate = CalendarObservedEvent(
            eventIdentifier: "event-duplicate",
            stableID: calendarDescriptor.stableID,
            calendarIdentifier: "calendar-a",
            title: calendarDescriptor.title,
            startDate: calendarDescriptor.startDate,
            endDate: calendarDescriptor.endDate
        )
        check(
            CalendarSyncPolicy.stableID(
                in: CalendarSyncPolicy.managedNotes(for: calendarDescriptor)
            ) == calendarDescriptor.stableID,
            "calendar events round-trip a stable DockNotes ownership marker"
        )
        check(
            CalendarSyncPolicy.evaluate(
                descriptor: calendarDescriptor,
                ledgerEntry: nil,
                observedEvents: [],
                force: false
            ).decision == .create,
            "a new task schedules creation of one managed calendar event"
        )
        let duplicateEvaluation = CalendarSyncPolicy.evaluate(
            descriptor: calendarDescriptor,
            ledgerEntry: calendarLedger,
            observedEvents: [calendarDuplicate, calendarObserved],
            force: false
        )
        check(
            duplicateEvaluation.decision == .update(eventIdentifier: "event-primary")
                && duplicateEvaluation.duplicateEventIdentifiers == ["event-duplicate"],
            "calendar reconciliation keeps the ledger event and removes duplicate managed events"
        )
        var externallyChanged = calendarObserved
        externallyChanged = CalendarObservedEvent(
            eventIdentifier: externallyChanged.eventIdentifier,
            stableID: externallyChanged.stableID,
            calendarIdentifier: externallyChanged.calendarIdentifier,
            title: "Changed in Calendar",
            startDate: externallyChanged.startDate.addingTimeInterval(3_600),
            endDate: externallyChanged.endDate.addingTimeInterval(3_600)
        )
        check(
            CalendarSyncPolicy.evaluate(
                descriptor: calendarDescriptor,
                ledgerEntry: calendarLedger,
                observedEvents: [externallyChanged],
                force: false
            ).decision == .conflictModified(eventIdentifier: "event-primary"),
            "an external calendar edit becomes an explicit conflict instead of being overwritten"
        )
        let externallyMoved = CalendarObservedEvent(
            eventIdentifier: calendarObserved.eventIdentifier,
            stableID: calendarObserved.stableID,
            calendarIdentifier: "calendar-b",
            title: calendarObserved.title,
            startDate: calendarObserved.startDate,
            endDate: calendarObserved.endDate
        )
        check(
            CalendarSyncPolicy.evaluate(
                descriptor: calendarDescriptor,
                ledgerEntry: calendarLedger,
                observedEvents: [externallyMoved],
                force: false
            ).decision == .conflictModified(eventIdentifier: "event-primary"),
            "moving a managed event to another calendar is detected as an external change"
        )
        check(
            CalendarSyncPolicy.evaluate(
                descriptor: calendarDescriptor,
                ledgerEntry: calendarLedger,
                observedEvents: [],
                force: false
            ).decision == .conflictDeleted,
            "an external calendar deletion becomes an explicit conflict"
        )
        check(
            CalendarSyncPolicy.evaluate(
                descriptor: calendarDescriptor,
                ledgerEntry: calendarLedger,
                observedEvents: [externallyChanged],
                force: true
            ).decision == .update(eventIdentifier: "event-primary"),
            "explicit resync overrides a calendar-side edit using DockNotes as the source"
        )
        let staleCalendarLedger = CalendarSyncLedgerEntry(
            stableID: "docknotes.calendar.task.stale",
            eventIdentifier: "event-stale",
            calendarIdentifier: "calendar-a",
            title: "Stale",
            startDate: deadlineNow,
            endDate: deadlineNow.addingTimeInterval(1_800),
            reference: calendarReference
        )
        check(
            CalendarSyncPolicy.staleStableIDs(
                desiredStableIDs: [calendarDescriptor.stableID],
                ledger: [
                    calendarDescriptor.stableID: calendarLedger,
                    staleCalendarLedger.stableID: staleCalendarLedger
                ]
            ) == [staleCalendarLedger.stableID],
            "calendar cleanup deletes only stale ledger-owned events and never unrelated events"
        )

        let searchRanges = NoteSearchEngine.matchRanges(in: "Beta beta", query: "beta")
        check(searchRanges == [NSRange(location: 0, length: 4), NSRange(location: 5, length: 4)], "note search exposes every case-insensitive match for emphasis")
        let highlightStorage = NSTextStorage(string: "Beta beta")
        let highlightLayout = NSLayoutManager()
        highlightStorage.addLayoutManager(highlightLayout)
        _ = NoteSearchHighlighter.apply(to: highlightLayout, text: highlightStorage.string, query: "beta")
        check(
            highlightLayout.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil) != nil,
            "note search applies visible emphasis through temporary editor attributes"
        )
        let titleMatch = DockNote(title: "Alpha plan", body: "plain body")
        let laterTitleMatch = DockNote(title: "Zulu alpha", body: "plain body")
        let bodyMatch = DockNote(title: "Beta note", body: "mentions alpha here")
        let noMatch = DockNote(title: "Gamma note", body: "plain body")
        check(
            NoteSearchEngine.rankedNotes([bodyMatch, laterTitleMatch, noMatch, titleMatch], query: "alpha").map(\.id)
                == [titleMatch.id, laterTitleMatch.id, bodyMatch.id],
            "library search ranks title matches first, orders by title, and excludes unrelated notes"
        )
        let libraryNow = Date(timeIntervalSince1970: 2_000_000_000)
        let pinnedLibraryNote = DockNote(
            title: "Pinned", isPinned: true,
            modifiedAt: libraryNow.addingTimeInterval(-30),
            createdAt: libraryNow.addingTimeInterval(-100)
        )
        let taskLibraryNote = DockNote(
            title: "Task", body: "☐ Finish",
            dueDate: libraryNow.addingTimeInterval(60),
            modifiedAt: libraryNow.addingTimeInterval(-10),
            createdAt: libraryNow.addingTimeInterval(-50)
        )
        let overdueLibraryNote = DockNote(
            title: "Overdue", dueDate: libraryNow.addingTimeInterval(-60),
            modifiedAt: libraryNow.addingTimeInterval(-20),
            createdAt: libraryNow.addingTimeInterval(-10)
        )
        let libraryQueryNotes = [pinnedLibraryNote, taskLibraryNote, overdueLibraryNote]
        check(
            LibraryQuery.apply(to: libraryQueryNotes, query: "", filter: .pinned, sort: .modified, now: libraryNow)
                .map(\.id) == [pinnedLibraryNote.id],
            "library filtering isolates pinned notes"
        )
        check(
            LibraryQuery.apply(to: libraryQueryNotes, query: "", filter: .incomplete, sort: .modified, now: libraryNow)
                .map(\.id) == [taskLibraryNote.id],
            "library filtering finds unchecked tasks in note content"
        )
        check(
            LibraryQuery.apply(to: libraryQueryNotes, query: "", filter: .overdue, sort: .due, now: libraryNow)
                .map(\.id) == [overdueLibraryNote.id],
            "library filtering isolates overdue notes"
        )
        check(
            LibraryQuery.apply(to: libraryQueryNotes, query: "", filter: .all, sort: .created, now: libraryNow)
                .map(\.id) == [overdueLibraryNote.id, taskLibraryNote.id, pinnedLibraryNote.id],
            "library creation sorting uses durable creation timestamps"
        )
        let parsedChecklistNote = DockNote(
            title: "Checklist source",
            body: "☐ First ☐ second\n☑ Done\n□ Legacy\n✓ Legacy done",
            dueDate: libraryNow
        )
        let parsedChecklist = ChecklistParser.items(in: parsedChecklistNote)
        check(
            parsedChecklist.map(\.text) == ["First", "second", "Done", "Legacy", "Legacy done"],
            "task center parses line and inline checkbox items without duplicating note data"
        )
        check(
            parsedChecklist.map(\.isCompleted) == [false, false, true, false, true],
            "task center recognizes current and legacy checkbox markers"
        )
        var taskCalendar = Calendar(identifier: .gregorian)
        taskCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let taskNow = taskCalendar.date(from: DateComponents(
            year: 2033, month: 5, day: 12, hour: 12
        ))!
        let todayTaskNote = DockNote(
            title: "Today source", body: "☐ Today task",
            dueDate: taskCalendar.date(byAdding: .hour, value: 2, to: taskNow)
        )
        let upcomingTaskNote = DockNote(
            title: "Upcoming source", body: "☐ Future task",
            dueDate: taskCalendar.date(byAdding: .day, value: 2, to: taskNow)
        )
        let overdueTaskNote = DockNote(
            title: "Overdue source", body: "☐ Late task",
            dueDate: taskCalendar.date(byAdding: .day, value: -1, to: taskNow)
        )
        let completedTaskNote = DockNote(title: "Completed source", body: "☑ Finished task")
        let taskQueryNotes = [todayTaskNote, upcomingTaskNote, overdueTaskNote, completedTaskNote]
        check(
            TaskCenterQuery.apply(to: taskQueryNotes, section: .today, now: taskNow, calendar: taskCalendar)
                .map(\.noteID) == [todayTaskNote.id],
            "task center isolates today's incomplete tasks"
        )
        check(
            TaskCenterQuery.apply(to: taskQueryNotes, section: .upcoming, now: taskNow, calendar: taskCalendar)
                .map(\.noteID) == [upcomingTaskNote.id],
            "task center isolates upcoming tasks"
        )
        check(
            TaskCenterQuery.apply(to: taskQueryNotes, section: .overdue, now: taskNow, calendar: taskCalendar)
                .map(\.noteID) == [overdueTaskNote.id],
            "task center isolates overdue tasks without duplicating today's tasks"
        )
        check(
            TaskCenterQuery.apply(to: taskQueryNotes, section: .completed, now: taskNow, calendar: taskCalendar)
                .map(\.noteID) == [completedTaskNote.id],
            "task center isolates completed tasks"
        )
        let taskCounts = TaskCenterQuery.counts(in: taskQueryNotes, now: taskNow, calendar: taskCalendar)
        check(
            taskCounts == TaskCenterCounts(inbox: 3, today: 1, week: 2, upcoming: 1, overdue: 1, completed: 1),
            "task center counts remain consistent across smart views"
        )
        check(NotePresentationPolicy.searchIsOverlay, "in-note search floats above text instead of resizing it")
        check(NotePresentationPolicy.aiKeepsEditorVisible, "opening in-note AI keeps the note body visible")

        let libraryFile = FileManager.default.temporaryDirectory.appendingPathComponent("DockNotes-Library-\(UUID().uuidString).json")
        let libraryStore = NotesStore(fileURL: libraryFile)
        libraryStore.isPreferencesPresented = true
        libraryStore.presentLibrary()
        check(libraryStore.isLibraryPresented, "the in-app library entry presents the library")
        check(!libraryStore.isPreferencesPresented, "opening the library dismisses settings")
        libraryStore.presentTaskCenter()
        check(libraryStore.isTaskCenterPresented, "the task center entry presents the task center")
        check(!libraryStore.isLibraryPresented, "opening the task center dismisses the library")
        let libraryArchivedDeleteID = libraryStore.notes[0].id
        libraryStore.archive(libraryArchivedDeleteID)
        check(
            libraryStore.archivedNotes.contains(where: { $0.id == libraryArchivedDeleteID }),
            "the library can archive an active note"
        )
        libraryStore.delete(libraryArchivedDeleteID)
        check(
            !libraryStore.archivedNotes.contains(where: { $0.id == libraryArchivedDeleteID }),
            "the library can permanently delete an archived note"
        )
        check(libraryStore.latestPendingDeletion?.note.id == libraryArchivedDeleteID, "deleting an archived note offers undo")
        libraryStore.undoLatestDeletion()
        check(
            libraryStore.archivedNotes.contains(where: { $0.id == libraryArchivedDeleteID }),
            "undo restores an archived note to the archived collection"
        )
        try? FileManager.default.removeItem(at: libraryFile)

        let taskCenterFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockNotes-TaskCenter-\(UUID().uuidString).json")
        let taskCenterAttributedBody = NSAttributedString(
            string: "☐ Rich task",
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
        )
        let taskCenterRTF = try? taskCenterAttributedBody.data(
            from: NSRange(location: 0, length: taskCenterAttributedBody.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let taskCenterSourceNote = DockNote(
            title: "Task source", body: taskCenterAttributedBody.string, bodyRTF: taskCenterRTF
        )
        let taskCenterEncoder = JSONEncoder()
        taskCenterEncoder.dateEncodingStrategy = .iso8601
        try? taskCenterEncoder.encode([taskCenterSourceNote]).write(to: taskCenterFile)
        let taskCenterStore = NotesStore(fileURL: taskCenterFile)
        let taskCenterItem = ChecklistParser.items(in: taskCenterSourceNote)[0]
        check(
            taskCenterStore.setChecklistItemCompleted(taskCenterItem.id, completed: true),
            "task center can complete a task by its source marker"
        )
        check(
            taskCenterStore.note(id: taskCenterSourceNote.id)?.body == "☑ Rich task",
            "task center completion writes through to the source note body"
        )
        let updatedTaskRTF = taskCenterStore.note(id: taskCenterSourceNote.id)?.bodyRTF.flatMap {
            try? NSAttributedString(
                data: $0,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        }
        check(
            updatedTaskRTF?.string == "☑ Rich task"
                && ((updatedTaskRTF?.attribute(.underlineStyle, at: 2, effectiveRange: nil) as? NSNumber)?.intValue ?? 0) != 0,
            "task center preserves rich-text formatting while toggling the source checkbox"
        )
        taskCenterStore.flushPendingSave()
        check(
            NotesStore(fileURL: taskCenterFile).note(id: taskCenterSourceNote.id)?.body == "☑ Rich task",
            "task center completion survives a store reload"
        )
        try? FileManager.default.removeItem(at: taskCenterFile)

        let calendarTitleFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockNotes-CalendarTitle-\(UUID().uuidString).json")
        let calendarTitleNote = DockNote(title: "Inline", body: "☐ First ☐ Second")
        try? taskCenterEncoder.encode([calendarTitleNote]).write(to: calendarTitleFile)
        let calendarTitleStore = NotesStore(fileURL: calendarTitleFile)
        let calendarTitleItems = ChecklistParser.items(
            in: calendarTitleStore.note(id: calendarTitleNote.id)!
        )
        let firstCalendarTitleTaskID = calendarTitleItems[0].id.taskID
        check(
            calendarTitleStore.updateChecklistItemText(
                calendarTitleItems[0].id,
                text: "Changed in Calendar"
            ),
            "a calendar-side title can be adopted into its source task"
        )
        let adoptedCalendarTitleNote = calendarTitleStore.note(id: calendarTitleNote.id)!
        check(
            adoptedCalendarTitleNote.body == "☐ Changed in Calendar ☐ Second"
                && ChecklistParser.items(in: adoptedCalendarTitleNote)[0].id.taskID == firstCalendarTitleTaskID,
            "adopting a calendar title preserves inline task separation and stable task identity"
        )
        try? FileManager.default.removeItem(at: calendarTitleFile)

        let taskDatesFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockNotes-TaskDates-\(UUID().uuidString).json")
        let taskDatesNote = DockNote(title: "Independent dates", body: "☐ First\n☐ Second")
        try? taskCenterEncoder.encode([taskDatesNote]).write(to: taskDatesFile)
        let taskDatesStore = NotesStore(fileURL: taskDatesFile)
        let taskDateItems = ChecklistParser.items(in: taskDatesStore.note(id: taskDatesNote.id)!)
        let firstTaskDueDate = taskNow.addingTimeInterval(7_200)
        check(
            taskDatesStore.setChecklistItemDueDate(taskDateItems[0].id, date: firstTaskDueDate),
            "task center can assign a due date to one parsed task"
        )
        let datedItems = ChecklistParser.items(in: taskDatesStore.note(id: taskDatesNote.id)!)
        check(
            datedItems[0].dueDate == firstTaskDueDate && datedItems[1].dueDate == nil,
            "tasks in the same note keep independent due dates"
        )
        taskDatesStore.updateBody("☐ New\n☐ First\n☐ Second", for: taskDatesNote.id)
        let shiftedDatedItems = ChecklistParser.items(in: taskDatesStore.note(id: taskDatesNote.id)!)
        check(
            shiftedDatedItems[0].dueDate == nil
                && shiftedDatedItems[1].text == "First"
                && shiftedDatedItems[1].dueDate == firstTaskDueDate,
            "task metadata follows its text when a new checkbox is inserted before it"
        )
        taskDatesStore.flushPendingSave()
        let reloadedDatedItems = ChecklistParser.items(in: NotesStore(fileURL: taskDatesFile).note(id: taskDatesNote.id)!)
        check(
            reloadedDatedItems[0].dueDate == nil
                && reloadedDatedItems[1].dueDate == firstTaskDueDate
                && reloadedDatedItems[2].dueDate == nil,
            "independent task due dates survive store reload"
        )

        let plannedTask = shiftedDatedItems[1]
        let plannedReference = ReminderTaskReference(item: plannedTask)
        let initialCalendarTask = CalendarTaskPlanner.descriptors(
            notes: taskDatesStore.notes,
            now: taskNow,
            calendar: taskCalendar
        ).first { $0.reference.taskID == plannedTask.id.taskID }
        check(
            initialCalendarTask?.startDate == firstTaskDueDate
                && initialCalendarTask?.stableID.contains(taskDatesNote.id.uuidString.lowercased()) == true,
            "a normal dated task produces one stable calendar event projection"
        )
        let reminderPlan = ReminderPlanner.makePlan(
            notes: taskDatesStore.notes,
            taskRemindersEnabled: true,
            dailySummaryEnabled: true,
            dailySummaryMinutes: 13 * 60,
            now: taskNow,
            calendar: taskCalendar,
            language: .english
        )
        let plannedTaskIdentifier = ReminderPlanner.taskIdentifier(for: plannedReference)
        check(
            reminderPlan.contains(where: {
                $0.identifier == plannedTaskIdentifier
                    && $0.fireDate == firstTaskDueDate
                    && $0.categoryIdentifier == ReminderNotificationAction.taskCategory
            }),
            "an incomplete task with a future date produces a stable task notification"
        )
        if let descriptor = reminderPlan.first(where: { $0.identifier == plannedTaskIdentifier }) {
            let systemRequest = ReminderSystemBridge.request(for: descriptor, calendar: taskCalendar)
            let trigger = systemRequest.trigger as? UNCalendarNotificationTrigger
            check(
                systemRequest.identifier == plannedTaskIdentifier
                    && systemRequest.content.categoryIdentifier == ReminderNotificationAction.taskCategory
                    && (systemRequest.content.userInfo["taskID"] as? String) == plannedReference.taskID?.uuidString
                    && trigger?.dateComponents.hour == taskCalendar.component(.hour, from: firstTaskDueDate),
                "the system notification request preserves task identity, category, and local fire time"
            )
        } else {
            check(false, "the system notification request can be constructed from a planned task")
        }
        let taskNotificationCategory = ReminderSystemBridge.categories(language: .english).first {
            $0.identifier == ReminderNotificationAction.taskCategory
        }
        check(
            taskNotificationCategory?.actions.map(\.identifier) == [
                ReminderNotificationAction.complete,
                ReminderNotificationAction.snooze,
                ReminderNotificationAction.open
            ],
            "task notifications register complete, snooze, and open actions in a stable order"
        )
        check(
            reminderPlan.contains(where: {
                $0.categoryIdentifier == ReminderNotificationAction.summaryCategory
                    && $0.body.contains("1 due today")
                    && taskCalendar.component(.hour, from: $0.fireDate) == 13
            }),
            "the daily plan summarizes today's and overdue task counts at the configured local time"
        )
        let rescheduledDate = firstTaskDueDate.addingTimeInterval(3_600)
        _ = taskDatesStore.setChecklistItemDueDate(plannedTask.id, date: rescheduledDate)
        let rescheduledPlan = ReminderPlanner.makePlan(
            notes: taskDatesStore.notes,
            taskRemindersEnabled: true,
            dailySummaryEnabled: false,
            dailySummaryMinutes: 8 * 60,
            now: taskNow,
            calendar: taskCalendar,
            language: .english
        )
        check(
            rescheduledPlan.first(where: { $0.identifier == plannedTaskIdentifier })?.fireDate == rescheduledDate,
            "changing a task date replaces the same stable notification at its new fire time"
        )
        let rescheduledCalendarTask = CalendarTaskPlanner.descriptors(
            notes: taskDatesStore.notes,
            now: taskNow,
            calendar: taskCalendar
        ).first { $0.reference.taskID == plannedTask.id.taskID }
        check(
            rescheduledCalendarTask?.stableID == initialCalendarTask?.stableID
                && rescheduledCalendarTask?.startDate == rescheduledDate,
            "rescheduling a task moves the same stable calendar event projection"
        )
        check(
            ReminderPlanner.activeEntityIdentifiers(in: taskDatesStore.notes).contains(plannedTaskIdentifier),
            "an incomplete dated task keeps its delivered notification available for notification actions"
        )
        _ = taskDatesStore.setChecklistItemDueDate(plannedTask.id, date: nil)
        check(
            !CalendarTaskPlanner.descriptors(
                notes: taskDatesStore.notes,
                now: taskNow,
                calendar: taskCalendar
            ).contains(where: { $0.reference.taskID == plannedTask.id.taskID }),
            "clearing a task date removes its calendar event projection"
        )
        check(
            !ReminderPlanner.makePlan(
                notes: taskDatesStore.notes,
                taskRemindersEnabled: true,
                dailySummaryEnabled: false,
                dailySummaryMinutes: 8 * 60,
                now: taskNow,
                calendar: taskCalendar,
                language: .english
            ).contains(where: { $0.identifier == plannedTaskIdentifier }),
            "clearing a task date cancels its pending notification"
        )
        _ = taskDatesStore.setChecklistItemDueDate(plannedTask.id, date: firstTaskDueDate)
        check(
            ReminderResponseRouter.command(
                actionIdentifier: ReminderNotificationAction.complete,
                userInfo: plannedReference.userInfo,
                now: taskNow
            ) == .complete(plannedReference),
            "the complete notification action resolves the durable source task"
        )
        check(
            ReminderResponseRouter.command(
                actionIdentifier: ReminderNotificationAction.snooze,
                userInfo: plannedReference.userInfo,
                now: taskNow
            ) == .snooze(plannedReference, until: taskNow.addingTimeInterval(15 * 60)),
            "the snooze notification action moves a task fifteen minutes forward"
        )
        check(
            ReminderResponseRouter.command(
                actionIdentifier: ReminderNotificationAction.openTaskCenter,
                userInfo: ["kind": "daily-summary"],
                now: taskNow
            ) == .openTaskCenter,
            "the daily summary notification opens the task center"
        )
        check(
            ReminderResponseRouter.command(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                userInfo: plannedReference.userInfo,
                now: taskNow
            ) == .openNote(taskDatesNote.id),
            "tapping a task notification opens its source note"
        )
        check(
            NotificationPermissionState(.authorized) == .allowed
                && NotificationPermissionState(.provisional) == .allowed
                && NotificationPermissionState(.denied) == .denied
                && NotificationPermissionState(.notDetermined) == .notRequested,
            "system notification authorization maps to clear settings states"
        )
        check(
            CalendarSyncCoordinator.permissionState(for: .fullAccess) == .allowed
                && CalendarSyncCoordinator.permissionState(for: .writeOnly) == .allowed
                && CalendarSyncCoordinator.permissionState(for: .denied) == .denied
                && CalendarSyncCoordinator.permissionState(for: .restricted) == .restricted
                && CalendarSyncCoordinator.permissionState(for: .notDetermined) == .notRequested,
            "system calendar authorization maps to recoverable settings states"
        )
        _ = taskDatesStore.setChecklistItemCompleted(plannedTask.id, completed: true)
        check(
            !CalendarTaskPlanner.descriptors(
                notes: taskDatesStore.notes,
                now: taskNow,
                calendar: taskCalendar
            ).contains(where: { $0.reference.taskID == plannedTask.id.taskID }),
            "completing a task removes its calendar event projection"
        )
        check(
            !ReminderPlanner.makePlan(
                notes: taskDatesStore.notes,
                taskRemindersEnabled: true,
                dailySummaryEnabled: false,
                dailySummaryMinutes: 8 * 60,
                now: taskNow,
                calendar: taskCalendar,
                language: .english
            ).contains(where: { $0.identifier == plannedTaskIdentifier }),
            "completing a task removes its pending notification from the next schedule"
        )
        check(
            !ReminderPlanner.activeEntityIdentifiers(in: taskDatesStore.notes).contains(plannedTaskIdentifier),
            "completing a task marks an already delivered notification as stale"
        )
        _ = taskDatesStore.setChecklistItemCompleted(
            ChecklistParser.items(in: taskDatesStore.note(id: taskDatesNote.id)!)[1].id,
            completed: false
        )
        taskDatesStore.archive(taskDatesNote.id)
        check(
            CalendarTaskPlanner.descriptors(
                notes: taskDatesStore.notes,
                now: taskNow,
                calendar: taskCalendar
            ).isEmpty,
            "archiving a source note removes its calendar event projections"
        )
        check(
            ReminderPlanner.makePlan(
                notes: taskDatesStore.notes,
                taskRemindersEnabled: true,
                dailySummaryEnabled: true,
                dailySummaryMinutes: 8 * 60,
                now: taskNow,
                calendar: taskCalendar,
                language: .english
            ).isEmpty,
            "archiving or deleting a source note removes all of its pending reminders"
        )
        taskDatesStore.restoreArchived(taskDatesNote.id)
        check(
            CalendarTaskPlanner.descriptors(
                notes: taskDatesStore.notes,
                now: taskNow,
                calendar: taskCalendar
            ).contains(where: { $0.stableID == initialCalendarTask?.stableID }),
            "restoring a source note reconstructs the same stable calendar event projection"
        )
        check(
            ReminderPlanner.makePlan(
                notes: taskDatesStore.notes,
                taskRemindersEnabled: true,
                dailySummaryEnabled: false,
                dailySummaryMinutes: 8 * 60,
                now: taskNow,
                calendar: taskCalendar,
                language: .english
            ).contains(where: { $0.identifier == plannedTaskIdentifier }),
            "restoring a source note reconstructs its task reminders from persisted metadata"
        )
        taskDatesStore.flushPendingSave()
        let restartedTaskDatesStore = NotesStore(fileURL: taskDatesFile)
        check(
            CalendarTaskPlanner.descriptors(
                notes: restartedTaskDatesStore.notes,
                now: taskNow,
                calendar: taskCalendar
            ).contains(where: { $0.stableID == initialCalendarTask?.stableID }),
            "application restart reconstructs the same calendar event identity from task metadata"
        )
        check(
            ReminderPlanner.makePlan(
                notes: restartedTaskDatesStore.notes,
                taskRemindersEnabled: true,
                dailySummaryEnabled: false,
                dailySummaryMinutes: 8 * 60,
                now: taskNow,
                calendar: taskCalendar,
                language: .english
            ).contains(where: { $0.identifier == plannedTaskIdentifier }),
            "application restart reconstructs task reminders from persisted note data"
        )
        taskDatesStore.delete(taskDatesNote.id)
        check(
            CalendarTaskPlanner.descriptors(
                notes: taskDatesStore.notes,
                now: taskNow,
                calendar: taskCalendar
            ).isEmpty,
            "deleting a source note removes its calendar event projections"
        )
        check(
            ReminderPlanner.makePlan(
                notes: taskDatesStore.notes,
                taskRemindersEnabled: true,
                dailySummaryEnabled: true,
                dailySummaryMinutes: 8 * 60,
                now: taskNow,
                calendar: taskCalendar,
                language: .english
            ).isEmpty,
            "deleting a source note cancels its task and summary reminders"
        )
        taskDatesStore.undoLatestDeletion()
        check(
            CalendarTaskPlanner.descriptors(
                notes: taskDatesStore.notes,
                now: taskNow,
                calendar: taskCalendar
            ).contains(where: { $0.stableID == initialCalendarTask?.stableID }),
            "undoing deletion restores the same calendar event projection"
        )
        check(
            ReminderPlanner.makePlan(
                notes: taskDatesStore.notes,
                taskRemindersEnabled: true,
                dailySummaryEnabled: false,
                dailySummaryMinutes: 8 * 60,
                now: taskNow,
                calendar: taskCalendar,
                language: .english
            ).contains(where: { $0.identifier == plannedTaskIdentifier }),
            "undoing deletion restores the reminder plan without changing task identity"
        )
        try? FileManager.default.removeItem(at: taskDatesFile)

        let monthAnchor = taskCalendar.date(from: DateComponents(
            year: 2032, month: 1, day: 31, hour: 9, minute: 15
        ))!
        let monthlyRule = TaskRecurrenceRule(frequency: .monthly)
        check(
            monthlyRule.scheduledDate(
                anchoredAt: monthAnchor,
                occurrenceIndex: 1,
                calendar: taskCalendar
            ) == taskCalendar.date(from: DateComponents(
                year: 2032, month: 2, day: 29, hour: 9, minute: 15
            )),
            "monthly recurrence clamps a month-end task to leap day"
        )
        check(
            monthlyRule.scheduledDate(
                anchoredAt: monthAnchor,
                occurrenceIndex: 2,
                calendar: taskCalendar
            ) == taskCalendar.date(from: DateComponents(
                year: 2032, month: 3, day: 31, hour: 9, minute: 15
            )),
            "monthly recurrence calculates from the series anchor without month-end drift"
        )
        let friday = taskCalendar.date(from: DateComponents(
            year: 2033, month: 5, day: 13, hour: 10
        ))!
        check(
            TaskRecurrenceRule(frequency: .weekdays).scheduledDate(
                anchoredAt: friday,
                occurrenceIndex: 1,
                calendar: taskCalendar
            ) == taskCalendar.date(from: DateComponents(
                year: 2033, month: 5, day: 16, hour: 10
            )),
            "weekday recurrence skips Saturday and Sunday"
        )
        check(
            TaskRecurrenceRule(frequency: .weekly, interval: 2).scheduledDate(
                anchoredAt: taskNow,
                occurrenceIndex: 3,
                calendar: taskCalendar
            ) == taskCalendar.date(byAdding: .weekOfYear, value: 6, to: taskNow),
            "custom recurrence intervals preserve the requested cadence"
        )

        let recurrenceFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockNotes-Recurrence-\(UUID().uuidString).json")
        let recurrenceNote = DockNote(title: "Daily plan", body: "☐ Daily standup")
        try? taskCenterEncoder.encode([recurrenceNote]).write(to: recurrenceFile)
        let recurrenceStore = NotesStore(fileURL: recurrenceFile)
        let recurrenceStart = taskCalendar.date(from: DateComponents(
            year: 2033, month: 5, day: 12, hour: 14
        ))!
        let initialRecurringItem = ChecklistParser.items(
            in: recurrenceStore.note(id: recurrenceNote.id)!
        )[0]
        check(
            recurrenceStore.setTaskRecurrence(
                initialRecurringItem.id,
                rule: TaskRecurrenceRule(frequency: .daily),
                startingAt: recurrenceStart
            ),
            "a source checklist task can become a recurring series"
        )
        let recurringItem = ChecklistParser.items(in: recurrenceStore.note(id: recurrenceNote.id)!)[0]
        let recurringTaskID = recurringItem.id.taskID
        check(
            recurringItem.recurrenceRule == TaskRecurrenceRule(frequency: .daily)
                && recurringItem.id.occurrenceIndex == 0
                && recurringItem.dueDate == recurrenceStart,
            "recurring metadata exposes the current occurrence without changing source text"
        )
        var shiftedRecurringNote = recurrenceStore.note(id: recurrenceNote.id)!
        shiftedRecurringNote.body = "☐ Other\n" + shiftedRecurringNote.body
        shiftedRecurringNote.tasks = ChecklistParser.synchronizedTasks(in: shiftedRecurringNote)
        let shiftedRecurringItem = ChecklistParser.items(in: shiftedRecurringNote).first {
            $0.text == "Daily standup"
        }
        check(
            shiftedRecurringItem?.id.taskID == recurringTaskID
                && shiftedRecurringItem?.recurrenceRule == TaskRecurrenceRule(frequency: .daily),
            "inserting another checkbox before a recurring task preserves its series identity and rule"
        )
        let firstWeekProjection = TaskCenterQuery.weekItems(
            in: recurrenceStore.notes,
            now: taskNow,
            calendar: taskCalendar
        )
        check(
            firstWeekProjection.count == 7
                && firstWeekProjection.map(\.id.occurrenceIndex) == Array(0...6).map(Optional.some),
            "the seven-day plan projects daily occurrences with stable sequence identities"
        )
        let calendarProjection = CalendarTaskPlanner.descriptors(
            notes: recurrenceStore.notes,
            now: taskNow,
            calendar: taskCalendar
        )
        check(
            calendarProjection.count == 7
                && Set(calendarProjection.map(\.stableID)).count == 7
                && calendarProjection.allSatisfy { $0.stableID.contains(".occurrence-") },
            "calendar sync projects seven days of recurring instances with unique stable identities"
        )
        var shiftedTimeZoneCalendar = taskCalendar
        shiftedTimeZoneCalendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        check(
            Set(CalendarTaskPlanner.descriptors(
                notes: recurrenceStore.notes,
                now: taskNow,
                calendar: shiftedTimeZoneCalendar
            ).map(\.stableID)) == Set(calendarProjection.map(\.stableID)),
            "a time-zone change preserves recurring calendar instance identities"
        )
        var archivedCalendarNote = recurrenceStore.notes[0]
        archivedCalendarNote.isArchived = true
        check(
            CalendarTaskPlanner.descriptors(
                notes: [archivedCalendarNote],
                now: taskNow,
                calendar: taskCalendar
            ).isEmpty,
            "calendar sync never projects tasks from archived notes"
        )
        let longOverdueTaskID = UUID()
        let longOverdueStart = taskCalendar.date(byAdding: .day, value: -100, to: taskNow)!
        let longOverdueRecurrence = TaskRecurrenceState(
            rule: TaskRecurrenceRule(frequency: .daily),
            startingAt: longOverdueStart
        )
        let longOverdueNote = DockNote(
            title: "Overdue recurrence",
            body: "☐ Long overdue",
            tasks: [NoteTask(
                id: longOverdueTaskID,
                text: "Long overdue",
                dueDate: longOverdueStart,
                sourceUTF16Offset: 0,
                recurrence: longOverdueRecurrence
            )]
        )
        let longOverdueCalendar = CalendarTaskPlanner.descriptors(
            notes: [longOverdueNote],
            now: taskNow,
            calendar: taskCalendar
        )
        check(
            longOverdueCalendar.contains(where: { $0.reference.occurrenceIndex == 0 })
                && !longOverdueCalendar.contains(where: { $0.reference.occurrenceIndex == 1 })
                && longOverdueCalendar.contains(where: { $0.reference.occurrenceIndex == 100 }),
            "calendar sync keeps one overdue current instance and only the upcoming seven-day plan"
        )
        let movedProjection = firstWeekProjection[2]
        let movedProjectionDate = recurrenceStart.addingTimeInterval(2 * 24 * 60 * 60 + 3_600)
        check(
            recurrenceStore.rescheduleTaskOccurrence(movedProjection.id, to: movedProjectionDate),
            "a projected occurrence can be rescheduled without moving the series"
        )
        check(
            TaskCenterQuery.weekItems(
                in: recurrenceStore.notes,
                now: taskNow,
                calendar: taskCalendar
            ).first(where: { $0.id.occurrenceIndex == 2 })?.dueDate == movedProjectionDate,
            "a one-time override appears at its effective date in the seven-day plan"
        )
        check(
            CalendarTaskPlanner.descriptors(
                notes: recurrenceStore.notes,
                now: taskNow,
                calendar: taskCalendar
            ).first(where: { $0.reference.occurrenceIndex == 2 })?.startDate == movedProjectionDate,
            "rescheduling one recurring instance moves only its stable calendar projection"
        )
        check(
            recurrenceStore.skipTaskOccurrence(firstWeekProjection[1].id),
            "a future projected occurrence can be skipped"
        )
        check(
            !TaskCenterQuery.weekItems(
                in: recurrenceStore.notes,
                now: taskNow,
                calendar: taskCalendar
            ).contains(where: { $0.id.occurrenceIndex == 1 }),
            "a skipped occurrence is absent from the seven-day plan"
        )
        check(
            !CalendarTaskPlanner.descriptors(
                notes: recurrenceStore.notes,
                now: taskNow,
                calendar: taskCalendar
            ).contains(where: { $0.reference.occurrenceIndex == 1 }),
            "skipping a recurring instance removes its calendar event projection"
        )

        let firstRecurringReference = ReminderTaskReference(item: recurringItem)
        let firstRecurringNotificationID = ReminderPlanner.taskIdentifier(for: firstRecurringReference)
        check(
            firstRecurringNotificationID.hasSuffix(".occurrence-0"),
            "recurring notification identity includes the stable occurrence sequence"
        )
        check(
            recurrenceStore.setChecklistItemCompleted(recurringItem.id, completed: true),
            "completing the current recurring instance advances the series"
        )
        let afterFirstCompletionNote = recurrenceStore.note(id: recurrenceNote.id)!
        let afterFirstCompletionItem = ChecklistParser.items(in: afterFirstCompletionNote)[0]
        let afterFirstCompletionTask = afterFirstCompletionNote.tasks.first { $0.id == recurringTaskID }
        check(
            afterFirstCompletionNote.body == "☐ Daily standup"
                && afterFirstCompletionItem.id.taskID == recurringTaskID
                && afterFirstCompletionItem.id.occurrenceIndex == 2
                && afterFirstCompletionItem.dueDate == movedProjectionDate
                && afterFirstCompletionTask?.recurrence?.history.last?.outcome == .completed,
            "completion records history, preserves source text and identity, and advances past a skipped instance"
        )
        let afterCompletionCalendar = CalendarTaskPlanner.descriptors(
            notes: recurrenceStore.notes,
            now: taskNow,
            calendar: taskCalendar
        )
        check(
            !afterCompletionCalendar.contains(where: { $0.reference.occurrenceIndex == 0 })
                && afterCompletionCalendar.contains(where: { $0.reference.occurrenceIndex == 2 }),
            "completing a recurring instance removes the old calendar event and keeps the generated instance"
        )
        let secondRecurringNotificationID = ReminderPlanner.taskIdentifier(
            for: ReminderTaskReference(item: afterFirstCompletionItem)
        )
        check(
            secondRecurringNotificationID != firstRecurringNotificationID
                && secondRecurringNotificationID.hasSuffix(".occurrence-2"),
            "the next generated instance replaces the previous notification identity"
        )
        recurrenceStore.updateBody("☑ Daily standup", for: recurrenceNote.id)
        let afterInlineCompletionNote = recurrenceStore.note(id: recurrenceNote.id)!
        let afterInlineCompletionItem = ChecklistParser.items(in: afterInlineCompletionNote)[0]
        check(
            afterInlineCompletionNote.body == "☐ Daily standup"
                && afterInlineCompletionItem.id.occurrenceIndex == 3
                && afterInlineCompletionNote.tasks[0].recurrence?.history.filter {
                    $0.outcome == .completed
                }.count == 2,
            "checking a recurring task inside the note advances it and restores the reusable source checkbox"
        )
        check(
            recurrenceStore.skipTaskOccurrence(afterInlineCompletionItem.id),
            "the current recurring instance can be skipped"
        )
        let afterCurrentSkip = recurrenceStore.note(id: recurrenceNote.id)!
        let afterCurrentSkipItem = ChecklistParser.items(in: afterCurrentSkip)[0]
        check(
            afterCurrentSkipItem.id.occurrenceIndex == 4
                && afterCurrentSkip.tasks[0].recurrence?.history.last?.outcome == .skipped,
            "skipping the current instance records the outcome and generates the following instance"
        )
        let currentRecurringNotificationID = ReminderPlanner.taskIdentifier(
            for: ReminderTaskReference(item: afterCurrentSkipItem)
        )
        check(
            ReminderPlanner.activeEntityIdentifiers(in: recurrenceStore.notes)
                .contains(currentRecurringNotificationID)
                && !ReminderPlanner.activeEntityIdentifiers(in: recurrenceStore.notes)
                    .contains(firstRecurringNotificationID),
            "notification cleanup retains only the newly generated recurring instance"
        )
        check(
            ReminderPlanner.makePlan(
                notes: recurrenceStore.notes,
                taskRemindersEnabled: true,
                dailySummaryEnabled: true,
                dailySummaryMinutes: 8 * 60,
                now: taskNow,
                calendar: taskCalendar,
                language: .english
            ).contains(where: {
                $0.categoryIdentifier == ReminderNotificationAction.summaryCategory
                    && taskCalendar.isDate($0.fireDate, inSameDayAs: afterCurrentSkipItem.dueDate!)
                    && $0.body.contains("1 due today")
            }),
            "daily summaries follow the current generated occurrence after completion and skipping"
        )
        check(
            TaskCenterQuery.apply(
                to: recurrenceStore.notes,
                section: .week,
                query: "standup",
                now: taskNow,
                calendar: taskCalendar
            ).count == 3,
            "seven-day projections participate in task and source-note search without duplicates"
        )
        let seriesRestart = taskCalendar.date(from: DateComponents(
            year: 2033, month: 6, day: 1, hour: 16
        ))!
        check(
            recurrenceStore.updateTaskRecurrenceSeries(
                ChecklistParser.items(in: afterCurrentSkip)[0].id,
                rule: TaskRecurrenceRule(frequency: .weekly, interval: 2),
                startingAt: seriesRestart
            ),
            "the entire series can be moved to a new rule and anchor"
        )
        let restartedSeriesCalendarNow = seriesRestart.addingTimeInterval(-3_600)
        let updatedSeriesCalendar = CalendarTaskPlanner.descriptors(
            notes: recurrenceStore.notes,
            now: restartedSeriesCalendarNow,
            calendar: taskCalendar
        )
        check(
            updatedSeriesCalendar.first?.startDate == seriesRestart
                && updatedSeriesCalendar.allSatisfy { $0.stableID.contains(recurringTaskID!.uuidString.lowercased()) },
            "editing an entire recurring series updates dates while preserving its stable task namespace"
        )
        recurrenceStore.flushPendingSave()
        let reloadedRecurrenceStore = NotesStore(fileURL: recurrenceFile)
        let reloadedRecurringItem = ChecklistParser.items(
            in: reloadedRecurrenceStore.note(id: recurrenceNote.id)!
        )[0]
        check(
            reloadedRecurringItem.id.taskID == recurringTaskID
                && reloadedRecurringItem.dueDate == seriesRestart
                && reloadedRecurringItem.recurrenceRule == TaskRecurrenceRule(
                    frequency: .weekly,
                    interval: 2
                ),
            "recurrence rule, current instance, history, and stable task identity survive restart"
        )
        check(
            CalendarTaskPlanner.descriptors(
                notes: reloadedRecurrenceStore.notes,
                now: restartedSeriesCalendarNow,
                calendar: taskCalendar
            ).map(\.stableID) == updatedSeriesCalendar.map(\.stableID),
            "restart reconstructs the same recurring calendar event identities"
        )
        let reloadedRecurringNotificationID = ReminderPlanner.taskIdentifier(
            for: ReminderTaskReference(item: reloadedRecurringItem)
        )
        check(
            ReminderPlanner.makePlan(
                notes: reloadedRecurrenceStore.notes,
                taskRemindersEnabled: true,
                dailySummaryEnabled: false,
                dailySummaryMinutes: 8 * 60,
                now: taskNow,
                calendar: taskCalendar,
                language: .english
            ).contains(where: {
                $0.identifier == reloadedRecurringNotificationID && $0.fireDate == seriesRestart
            }),
            "restart reconstructs the notification for the active recurring instance"
        )
        reloadedRecurrenceStore.archive(recurrenceNote.id)
        check(
            CalendarTaskPlanner.descriptors(
                notes: reloadedRecurrenceStore.notes,
                now: restartedSeriesCalendarNow,
                calendar: taskCalendar
            ).isEmpty,
            "archiving a recurring source removes every projected calendar instance"
        )
        check(
            ReminderPlanner.makePlan(
                notes: reloadedRecurrenceStore.notes,
                taskRemindersEnabled: true,
                dailySummaryEnabled: false,
                dailySummaryMinutes: 8 * 60,
                now: taskNow,
                calendar: taskCalendar,
                language: .english
            ).isEmpty,
            "archiving a recurring source cancels its active notification"
        )
        reloadedRecurrenceStore.restoreArchived(recurrenceNote.id)
        let restoredRecurringItem = ChecklistParser.items(
            in: reloadedRecurrenceStore.note(id: recurrenceNote.id)!
        )[0]
        check(
            restoredRecurringItem.id.taskID == recurringTaskID
                && restoredRecurringItem.recurrenceRule != nil
                && ReminderPlanner.makePlan(
                    notes: reloadedRecurrenceStore.notes,
                    taskRemindersEnabled: true,
                    dailySummaryEnabled: false,
                    dailySummaryMinutes: 8 * 60,
                    now: taskNow,
                    calendar: taskCalendar,
                    language: .english
                ).contains(where: {
                    $0.identifier == ReminderPlanner.taskIdentifier(
                        for: ReminderTaskReference(item: restoredRecurringItem)
                    )
                }),
            "restoring a recurring source rebuilds the same series identity and notification"
        )
        check(
            CalendarTaskPlanner.descriptors(
                notes: reloadedRecurrenceStore.notes,
                now: restartedSeriesCalendarNow,
                calendar: taskCalendar
            ).map(\.stableID) == updatedSeriesCalendar.map(\.stableID),
            "restoring a recurring source rebuilds the same calendar instance identities"
        )
        reloadedRecurrenceStore.delete(recurrenceNote.id)
        check(
            CalendarTaskPlanner.descriptors(
                notes: reloadedRecurrenceStore.notes,
                now: restartedSeriesCalendarNow,
                calendar: taskCalendar
            ).isEmpty,
            "deleting a recurring source removes every projected calendar instance"
        )
        check(
            ReminderPlanner.makePlan(
                notes: reloadedRecurrenceStore.notes,
                taskRemindersEnabled: true,
                dailySummaryEnabled: false,
                dailySummaryMinutes: 8 * 60,
                now: taskNow,
                calendar: taskCalendar,
                language: .english
            ).isEmpty,
            "deleting a recurring source removes its active occurrence notification"
        )
        reloadedRecurrenceStore.undoLatestDeletion()
        let undoRestoredRecurringItem = ChecklistParser.items(
            in: reloadedRecurrenceStore.note(id: recurrenceNote.id)!
        )[0]
        check(
            undoRestoredRecurringItem.id.taskID == recurringTaskID
                && undoRestoredRecurringItem.recurrenceRule != nil
                && ReminderPlanner.makePlan(
                    notes: reloadedRecurrenceStore.notes,
                    taskRemindersEnabled: true,
                    dailySummaryEnabled: false,
                    dailySummaryMinutes: 8 * 60,
                    now: taskNow,
                    calendar: taskCalendar,
                    language: .english
                ).contains(where: {
                    $0.identifier == ReminderPlanner.taskIdentifier(
                        for: ReminderTaskReference(item: undoRestoredRecurringItem)
                    )
                }),
            "undoing deletion restores the recurring series, identity, and notification"
        )
        check(
            CalendarTaskPlanner.descriptors(
                notes: reloadedRecurrenceStore.notes,
                now: restartedSeriesCalendarNow,
                calendar: taskCalendar
            ).map(\.stableID) == updatedSeriesCalendar.map(\.stableID),
            "undoing deletion restores the same recurring calendar instance identities"
        )
        check(
            reloadedRecurrenceStore.stopTaskRecurrence(undoRestoredRecurringItem.id),
            "a recurring series can be stopped without deleting its current task"
        )
        let stoppedItem = ChecklistParser.items(
            in: reloadedRecurrenceStore.note(id: recurrenceNote.id)!
        )[0]
        check(
            stoppedItem.recurrenceRule == nil
                && stoppedItem.dueDate == seriesRestart
                && stoppedItem.id.taskID == recurringTaskID,
            "stopping repetition keeps the current instance as a normal dated task"
        )
        let stoppedCalendarEvents = CalendarTaskPlanner.descriptors(
            notes: reloadedRecurrenceStore.notes,
            now: restartedSeriesCalendarNow,
            calendar: taskCalendar
        )
        check(
            stoppedCalendarEvents.count == 1
                && !stoppedCalendarEvents[0].stableID.contains(".occurrence-"),
            "stopping repetition replaces projected instances with one normal stable calendar event"
        )
        check(
            ReminderPlanner.makePlan(
                notes: reloadedRecurrenceStore.notes,
                taskRemindersEnabled: true,
                dailySummaryEnabled: false,
                dailySummaryMinutes: 8 * 60,
                now: taskNow,
                calendar: taskCalendar,
                language: .english
            ).contains(where: {
                $0.identifier == ReminderPlanner.taskIdentifier(
                    for: ReminderTaskReference(item: stoppedItem)
                ) && !$0.identifier.contains(".occurrence-")
            }),
            "stopping repetition replaces the series notification with a normal task notification"
        )

        let legacyTaskID = UUID()
        let legacyTaskData = """
        {"id":"\(legacyTaskID.uuidString)","text":"Legacy","isCompleted":false,"dueDate":null,"sourceUTF16Offset":0}
        """.data(using: .utf8)!
        let legacyTask = try? JSONDecoder().decode(NoteTask.self, from: legacyTaskData)
        check(
            legacyTask?.id == legacyTaskID && legacyTask?.recurrence == nil,
            "pre-v0.7 task metadata decodes without migration or a recurrence field"
        )
        try? FileManager.default.removeItem(at: recurrenceFile)

        let transferNote = DockNote(
            title: "Portable / Tasks",
            body: "☐ Pending\n☑ Finished\nPlain text"
        )
        let transferMarkdown = NoteFileTransfer.markdown(for: transferNote)
        check(
            transferMarkdown.contains("# Portable / Tasks")
                && transferMarkdown.contains("- [ ] Pending")
                && transferMarkdown.contains("- [x] Finished"),
            "Markdown export preserves title, body, and checklist semantics"
        )
        let importedMarkdownNote = NoteFileTransfer.note(
            fromMarkdown: transferMarkdown,
            fallbackTitle: "Fallback"
        )
        check(
            importedMarkdownNote.title == transferNote.title
                && importedMarkdownNote.body == transferNote.body
                && importedMarkdownNote.tasks.count == 2,
            "Markdown import restores title, body, and interactive checklist metadata"
        )
        let transferDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockNotes-Transfer-\(UUID().uuidString)", isDirectory: true)
        let exportedTransferURLs = try? NoteFileTransfer.export(
            [transferNote, transferNote],
            to: transferDirectory,
            format: .markdown
        )
        check(
            exportedTransferURLs?.map(\.lastPathComponent)
                == ["Portable Tasks.md", "Portable Tasks 2.md"],
            "batch export sanitizes filenames and never overwrites a sibling note"
        )
        let importedTransferNote = exportedTransferURLs?.first.flatMap {
            try? NoteFileTransfer.importNote(from: $0)
        }
        check(
            importedTransferNote?.title == transferNote.title
                && importedTransferNote?.body == transferNote.body,
            "an exported Markdown note can be imported again"
        )
        let textTransferNote = DockNote(
            title: "Portable Text",
            body: "中文与 English\n☐ Plain text task"
        )
        let exportedTextURLs = try? NoteFileTransfer.export(
            [textTransferNote],
            to: transferDirectory,
            format: .text
        )
        let importedTextNote = exportedTextURLs?.first.flatMap {
            try? NoteFileTransfer.importNote(from: $0)
        }
        check(
            exportedTextURLs?.first?.lastPathComponent == "Portable Text.txt"
                && importedTextNote?.title == textTransferNote.title
                && importedTextNote?.body == textTransferNote.body
                && importedTextNote?.tasks.count == 1,
            "TXT export and import preserve multilingual text and interactive checklist metadata"
        )
        try? FileManager.default.removeItem(at: transferDirectory)

        let undoFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockNotes-Undo-\(UUID().uuidString).json")
        let undoNotes = [DockNote(title: "First"), DockNote(title: "Second"), DockNote(title: "Third")]
        let undoEncoder = JSONEncoder()
        undoEncoder.dateEncodingStrategy = .iso8601
        try? undoEncoder.encode(undoNotes).write(to: undoFile)
        let undoStore = NotesStore(fileURL: undoFile)
        undoStore.select(undoNotes[0].id)
        undoStore.delete(undoNotes[0].id)
        check(
            undoStore.notes.map(\.id) == [undoNotes[1].id, undoNotes[2].id]
                && undoStore.latestPendingDeletion?.note.id == undoNotes[0].id,
            "deleting the open note removes it immediately and starts an undo transaction"
        )
        undoStore.undoLatestDeletion()
        check(
            undoStore.notes.map(\.id) == undoNotes.map(\.id)
                && undoStore.activeNoteID == undoNotes[0].id
                && undoStore.deckState == .noteOpen(undoNotes[0].id),
            "undo restores the note's original order and open presentation"
        )
        undoStore.delete(undoNotes[0].id)
        undoStore.delete(undoNotes[1].id)
        let latestDeletionID = undoStore.latestPendingDeletion!.id
        undoStore.undoDeletion(latestDeletionID)
        undoStore.undoLatestDeletion()
        check(undoStore.notes.map(\.id) == undoNotes.map(\.id), "multiple queued deletions undo in predictable order")
        undoStore.delete(undoNotes[2].id)
        let finalizedDeletionID = undoStore.latestPendingDeletion!.id
        undoStore.finalizeDeletion(finalizedDeletionID)
        check(
            undoStore.latestPendingDeletion == nil
                && !undoStore.notes.contains(where: { $0.id == undoNotes[2].id }),
            "an expired deletion can no longer be undone"
        )
        try? FileManager.default.removeItem(at: undoFile)

        let captureFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockNotes-Quick-Capture-\(UUID().uuidString).json")
        let captureStore = NotesStore(fileURL: captureFile)
        let captureCount = captureStore.notes.count
        captureStore.presentQuickCapture()
        check(captureStore.isQuickCapturePresented, "quick capture can be presented independently")
        check(
            captureStore.saveQuickCapture(title: "", body: "", language: .english) == false
                && captureStore.notes.count == captureCount,
            "cancelling an empty quick capture does not create a note"
        )
        captureStore.presentQuickCapture()
        check(
            captureStore.saveQuickCapture(title: "Captured", body: "From anywhere", language: .english),
            "a non-empty quick capture saves successfully"
        )
        check(
            captureStore.notes.last?.title == "Captured"
                && captureStore.notes.last?.body == "From anywhere"
                && !captureStore.isQuickCapturePresented
                && captureStore.deckState == .fanned,
            "quick capture returns the saved note to the edge deck"
        )
        try? FileManager.default.removeItem(at: captureFile)

        let emptyLibraryFile = FileManager.default.temporaryDirectory.appendingPathComponent("DockNotes-Empty-Library-\(UUID().uuidString).json")
        let emptyLibraryStore = NotesStore(fileURL: emptyLibraryFile)
        for noteID in emptyLibraryStore.notes.map(\.id) {
            emptyLibraryStore.delete(noteID)
        }
        for noteID in emptyLibraryStore.archivedNotes.map(\.id) {
            emptyLibraryStore.delete(noteID)
        }
        let reloadedEmptyLibrary = NotesStore(fileURL: emptyLibraryFile)
        check(
            reloadedEmptyLibrary.notes.isEmpty && reloadedEmptyLibrary.archivedNotes.isEmpty,
            "deleting every note remains empty after a full store reload"
        )
        try? FileManager.default.removeItem(at: emptyLibraryFile)

        let taskFile = FileManager.default.temporaryDirectory.appendingPathComponent("DockNotes-Task-\(UUID().uuidString).json")
        let taskNote = DockNote(title: "Task click", body: "☐ Buy milk")
        let taskEncoder = JSONEncoder()
        taskEncoder.dateEncodingStrategy = .iso8601
        try? taskEncoder.encode([taskNote]).write(to: taskFile)
        let taskStore = NotesStore(fileURL: taskFile)
        let taskDefaults = UserDefaults(suiteName: "DockNotes.TaskClick.\(UUID().uuidString)")!
        let taskSettings = AppSettings(defaults: taskDefaults)
        let taskHost = NSHostingView(rootView: NoteCard(note: taskNote, store: taskStore, settings: taskSettings)
            .frame(width: 460, height: 380))
        taskHost.frame = NSRect(x: 0, y: 0, width: 460, height: 380)
        let taskPanel = NSPanel(contentRect: taskHost.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        taskPanel.contentView = taskHost
        taskPanel.alphaValue = 0
        taskPanel.orderBack(nil)
        taskHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        taskHost.layoutSubtreeIfNeeded()
        let taskEditors = descendants(of: taskHost, as: NSTextView.self)
        check(taskEditors.count == 1, "the note mounts one editable task body")
        let taskEditor = taskEditors[0]
        let checkboxGlyph = taskEditor.layoutManager!.glyphRange(
            forCharacterRange: NSRange(location: 0, length: 1), actualCharacterRange: nil
        )
        let checkboxRect = taskEditor.layoutManager!.boundingRect(
            forGlyphRange: checkboxGlyph, in: taskEditor.textContainer!
        )
        let checkboxPoint = NSPoint(
            x: checkboxRect.midX + taskEditor.textContainerOrigin.x,
            y: checkboxRect.midY + taskEditor.textContainerOrigin.y
        )
        let clickInWindow = taskEditor.convert(checkboxPoint, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: clickInWindow, modifierFlags: [], timestamp: 0,
                windowNumber: taskPanel.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1
            )!
            taskPanel.sendEvent(event)
        }
        check(taskStore.note(id: taskNote.id)?.body == "☑ Buy milk", "clicking a task checkbox marks it done")
        taskStore.flushPendingSave()
        check(
            NotesStore(fileURL: taskFile).note(id: taskNote.id)?.body == "☑ Buy milk",
            "a completed task remains checked after store reload"
        )
        check(
            (taskEditor.textStorage?.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) as? NSNumber)?.intValue != 0,
            "completed task text is visually distinguished from pending text"
        )
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: clickInWindow, modifierFlags: [], timestamp: 0,
                windowNumber: taskPanel.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1
            )!
            taskPanel.sendEvent(event)
        }
        check(taskStore.note(id: taskNote.id)?.body == "☐ Buy milk", "clicking a completed task restores it to pending")
        taskStore.flushPendingSave()
        check(NotesStore(fileURL: taskFile).note(id: taskNote.id)?.body == "☐ Buy milk", "task state survives store reload")
        check(taskEditor is TaskCheckboxTextView, "the note editor owns caret-aware checklist insertion")
        taskEditor.setSelectedRange(NSRange(location: 6, length: 0))
        (taskEditor as? TaskCheckboxTextView)?.insertTaskAtSelection()
        check(
            taskStore.note(id: taskNote.id)?.body == "☐ Buy ☐ milk"
                && taskEditor.selectedRange().location == 8,
            "the checklist toolbar inserts at the caret and leaves the caret after the checkbox"
        )
        let inlineGlyph = taskEditor.layoutManager!.glyphRange(
            forCharacterRange: NSRange(location: 6, length: 1), actualCharacterRange: nil
        )
        let inlineRect = taskEditor.layoutManager!.boundingRect(forGlyphRange: inlineGlyph, in: taskEditor.textContainer!)
        let inlinePoint = taskEditor.convert(
            NSPoint(x: inlineRect.midX + taskEditor.textContainerOrigin.x,
                    y: inlineRect.midY + taskEditor.textContainerOrigin.y), to: nil
        )
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: inlinePoint, modifierFlags: [], timestamp: 0,
                windowNumber: taskPanel.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1
            )!
            taskPanel.sendEvent(event)
        }
        check(taskStore.note(id: taskNote.id)?.body == "☐ Buy ☑ milk", "an inline checkbox remains clickable")
        taskPanel.orderOut(nil)
        try? FileManager.default.removeItem(at: taskFile)

        let libraryScrollFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockNotes-Library-Scroll-\(UUID().uuidString).json")
        let libraryScrollNotes = (0..<25).map { DockNote(title: "Active \($0)") }
            + (0..<25).map { DockNote(title: "Archived \($0)", isArchived: true) }
        try? taskEncoder.encode(libraryScrollNotes).write(to: libraryScrollFile)
        let libraryScrollStore = NotesStore(fileURL: libraryScrollFile)
        let libraryHost = NSHostingView(rootView: NotesLibraryView(store: libraryScrollStore, settings: taskSettings))
        libraryHost.frame = NSRect(x: 0, y: 0, width: 680, height: 520)
        let libraryPanel = NSPanel(
            contentRect: libraryHost.bounds, styleMask: [.titled], backing: .buffered, defer: false
        )
        libraryPanel.contentView = libraryHost
        libraryPanel.alphaValue = 0
        libraryPanel.orderBack(nil)
        libraryHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        libraryHost.layoutSubtreeIfNeeded()
        let libraryScrollViews = descendants(of: libraryHost, as: NSScrollView.self)
            .filter { $0.documentView?.bounds.height ?? 0 > $0.contentView.bounds.height + 100 }
        check(libraryScrollViews.count == 1, "the library exposes one independently scrolling note list")
        let libraryScrollView = libraryScrollViews[0]
        libraryScrollView.contentView.scroll(to: NSPoint(x: 0, y: 600))
        libraryScrollView.reflectScrolledClipView(libraryScrollView.contentView)
        check(libraryScrollView.contentView.bounds.minY > 100, "the library can scroll down before switching collections")
        let librarySegments = descendants(of: libraryHost, as: NSSegmentedControl.self)
            .filter { $0.bounds.width > 240 }
        check(librarySegments.count == 1, "the library mounts its All/Archived segmented picker")
        let archivedSegment = librarySegments[0]
        let initialHeaderY = archivedSegment.convert(archivedSegment.bounds, to: libraryHost).midY
        let archivedPoint = archivedSegment.convert(
            NSPoint(x: archivedSegment.bounds.width * 0.75, y: archivedSegment.bounds.midY), to: nil
        )
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: archivedPoint, modifierFlags: [], timestamp: 0,
                windowNumber: libraryPanel.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1
            )!
            libraryPanel.sendEvent(event)
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        libraryHost.layoutSubtreeIfNeeded()
        let archivedScrollViews = descendants(of: libraryHost, as: NSScrollView.self)
            .filter { $0.documentView?.bounds.height ?? 0 > $0.contentView.bounds.height + 100 }
        check(archivedScrollViews.count == 1, "archived notes retain a scrollable list")
        check(
            archivedScrollViews[0].contentView.bounds.minY < 10,
            "switching to archived notes starts at the top rather than the previous scroll position"
        )
        for noteID in libraryScrollStore.archivedNotes.map(\.id) {
            libraryScrollStore.delete(noteID)
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        libraryHost.layoutSubtreeIfNeeded()
        let emptyArchiveSegment = descendants(of: libraryHost, as: NSSegmentedControl.self)
            .first(where: { $0.bounds.width > 240 })!
        let emptyHeaderY = emptyArchiveSegment.convert(emptyArchiveSegment.bounds, to: libraryHost).midY
        check(
            abs(emptyHeaderY - initialHeaderY) < 2,
            "the library title and search area stay pinned when Archived becomes empty"
        )
        libraryPanel.orderOut(nil)
        try? FileManager.default.removeItem(at: libraryScrollFile)

        let layoutNotes = (0..<6).map { DockNote(title: "Note \($0)") }
        let collapsedPlan = DeckLayout.plan(
            notes: layoutNotes,
            activeNoteID: layoutNotes[1].id,
            isExpanded: false,
            availableHeight: 640
        )
        let expandedPlan = DeckLayout.plan(
            notes: layoutNotes,
            activeNoteID: layoutNotes[1].id,
            isExpanded: true,
            availableHeight: 640
        )
        check(collapsedPlan.slots[0] == layoutNotes[0].id, "deck first slot is stable")
        check(expandedPlan.slots[0] == layoutNotes[0].id, "opening a note does not move the first slot")
        check(expandedPlan.slots[1] == layoutNotes[1].id, "the active note keeps its visible side label while open")
        check(expandedPlan.slots[2] == layoutNotes[2].id, "opening a note does not shift later tabs")
        check(
            DeckLayout.deckStackHeight(noteSlotCount: expandedPlan.slots.count, pitch: DeckLayout.tabHeight)
                + DeckLayout.controlsHeight <= 640
                && DeckLayout.deckStackHeight(noteSlotCount: expandedPlan.slots.count + 1, pitch: DeckLayout.tabHeight)
                    + DeckLayout.controlsHeight > 640
                && expandedPlan.overflowIDs.count == layoutNotes.count - expandedPlan.slots.count,
            "deck reserves enough height for every control before adding tab slots"
        )

        let tenNotes = (0..<10).map { DockNote(title: "Overflow Note \($0)") }
        let defaultSlotPlan = DeckLayout.plan(
            notes: tenNotes,
            activeNoteID: nil,
            isExpanded: false,
            availableHeight: 800
        )
        check(defaultSlotPlan.slots.count == 4, "the edge deck exposes four tabs by default")
        let sevenSlotPlan = DeckLayout.plan(
            notes: tenNotes,
            activeNoteID: nil,
            isExpanded: false,
            availableHeight: 1_040,
            preferredVisibleCount: 7
        )
        check(sevenSlotPlan.slots.count == 7, "settings can expose up to seven stable tab slots")
        check(DeckLayout.tabHeight >= 90, "seven tabs retain their full-size height")
        check(
            DeckLayout.dragPreviewOffset(for: 1, sourceSlot: 0, targetSlot: 2) == -DeckLayout.tabHeight,
            "tabs between the source and live drag target move aside during drag"
        )
        check(
            DeckLayout.dragPreviewOffset(for: 1, sourceSlot: 2, targetSlot: 0) == DeckLayout.tabHeight,
            "tabs move aside in both drag directions"
        )
        check(
            DeckLayout.dragTarget(sourceSlot: 1, translation: DeckLayout.tabHeight * 1.6, slotCount: 7) == 3,
            "live drag translation resolves to the nearest target slot"
        )
        check(
            DeckLayout.dragTarget(sourceSlot: 0, translation: -500, slotCount: 7) == 0,
            "live drag target remains within the visible deck"
        )
        let releaseTranslation = DeckLayout.tabHeight * 1.7
        let releaseResidual = DeckLayout.dragResidual(
            originSlot: 0,
            currentSlot: 2,
            translation: releaseTranslation
        )
        check(
            abs((releaseTranslation - DeckLayout.tabHeight * 2) - releaseResidual) < 0.001,
            "drop residual preserves the dragged tab's visual position across live reordering"
        )
        let repeatedDragID = UUID()
        let repeatedDrag = TabDragCoordinator()
        repeatedDrag.begin(noteID: repeatedDragID, sourceSlot: 0)
        repeatedDrag.beginSettling(
            destinationSlot: 2,
            translation: DeckLayout.tabHeight * 1.7,
            pitch: DeckLayout.tabHeight,
            noteID: repeatedDragID
        )
        repeatedDrag.begin(noteID: repeatedDragID, sourceSlot: 2)
        check(
            !repeatedDrag.isSettling && repeatedDrag.sourceSlot == 2,
            "a new drag recovers immediately when the previous same-tab settling session was interrupted"
        )
        let smoothDrag = TabDragCoordinator()
        let smoothDragID = UUID()
        smoothDrag.begin(noteID: smoothDragID, sourceSlot: 0)
        var targetUpdateCount = 0
        let targetUpdateObservation = smoothDrag.$targetSlot
            .dropFirst()
            .sink { _ in targetUpdateCount += 1 }
        for _ in 0..<120 {
            smoothDrag.update(
                translation: DeckLayout.tabHeight,
                targetSlot: 1,
                noteID: smoothDragID
            )
        }
        check(
            targetUpdateCount == 1,
            "dragging within one slot publishes one layout update instead of one update per mouse event"
        )
        withExtendedLifetime(targetUpdateObservation) {}
        let staleReleaseDrag = TabDragCoordinator()
        let staleReleaseDragID = UUID()
        staleReleaseDrag.begin(noteID: staleReleaseDragID, sourceSlot: 0)
        let staleReleaseGeneration = staleReleaseDrag.recoveryGeneration(
            noteID: staleReleaseDragID
        )!
        staleReleaseDrag.beginSettling(
            destinationSlot: 1,
            translation: DeckLayout.tabHeight,
            pitch: DeckLayout.tabHeight,
            noteID: staleReleaseDragID
        )
        staleReleaseDrag.completeSettling(noteID: staleReleaseDragID)
        staleReleaseDrag.begin(noteID: staleReleaseDragID, sourceSlot: 1)
        staleReleaseDrag.update(
            translation: DeckLayout.tabHeight * 0.5,
            targetSlot: 2,
            noteID: staleReleaseDragID
        )
        staleReleaseDrag.recoverInterruptedDrag(
            noteID: staleReleaseDragID,
            sessionGeneration: staleReleaseGeneration
        )
        check(
            staleReleaseDrag.noteID == staleReleaseDragID,
            "a delayed release from the previous drag cannot cancel a newer drag of the same label"
        )
        staleReleaseDrag.finish(noteID: staleReleaseDragID)
        let repeatedReleaseStress = TabDragCoordinator()
        let repeatedReleaseStressID = UUID()
        for iteration in 0..<100 {
            let sourceSlot = iteration % 3
            repeatedReleaseStress.begin(noteID: repeatedReleaseStressID, sourceSlot: sourceSlot)
            let staleGeneration = repeatedReleaseStress.recoveryGeneration(
                noteID: repeatedReleaseStressID
            )!
            repeatedReleaseStress.beginSettling(
                destinationSlot: (sourceSlot + 1) % 3,
                translation: DeckLayout.tabHeight,
                pitch: DeckLayout.tabHeight,
                noteID: repeatedReleaseStressID
            )
            repeatedReleaseStress.completeSettling(noteID: repeatedReleaseStressID)
            repeatedReleaseStress.begin(
                noteID: repeatedReleaseStressID,
                sourceSlot: (sourceSlot + 1) % 3
            )
            repeatedReleaseStress.update(
                translation: DeckLayout.tabHeight * 0.5,
                targetSlot: (sourceSlot + 2) % 3,
                noteID: repeatedReleaseStressID
            )
            repeatedReleaseStress.recoverInterruptedDrag(
                noteID: repeatedReleaseStressID,
                sessionGeneration: staleGeneration
            )
            check(
                repeatedReleaseStress.noteID == repeatedReleaseStressID,
                "one hundred repeated drags remain immune to stale release callbacks"
            )
            repeatedReleaseStress.finish(noteID: repeatedReleaseStressID)
        }
        let interruptedDrag = TabDragCoordinator()
        let interruptedDragID = UUID()
        interruptedDrag.begin(noteID: interruptedDragID, sourceSlot: 0)
        interruptedDrag.update(
            translation: DeckLayout.tabHeight * 0.5,
            targetSlot: 1,
            noteID: interruptedDragID
        )
        interruptedDrag.recoverInterruptedDrag(noteID: interruptedDragID)
        check(
            interruptedDrag.noteID == nil,
            "a missed panel mouse-up cannot leave the drag session stuck"
        )
        let selfCleaningDrag = TabDragCoordinator()
        let selfCleaningDragID = UUID()
        selfCleaningDrag.begin(noteID: selfCleaningDragID, sourceSlot: 0)
        selfCleaningDrag.beginSettling(
            destinationSlot: 1,
            translation: DeckLayout.tabHeight,
            pitch: DeckLayout.tabHeight,
            noteID: selfCleaningDragID
        )
        selfCleaningDrag.completeSettling(noteID: selfCleaningDragID)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.30))
        check(
            selfCleaningDrag.noteID == nil,
            "the drag coordinator owns and completes its settling cleanup"
        )
        var labelPointer = TabPointerDragSession()
        labelPointer.mouseDown(screenY: 700)
        check(
            labelPointer.mouseDragged(screenY: 699) == .dragChanged(1),
            "the colored label starts following the pointer after the first pixel of movement"
        )
        check(
            labelPointer.mouseDragged(screenY: 694) == .dragChanged(6),
            "dragging the colored label body produces a downward screen-space translation"
        )
        check(
            labelPointer.mouseDragged(screenY: 560) == .dragChanged(140),
            "the label drag remains continuous after crossing multiple slots"
        )
        check(
            labelPointer.mouseUp(screenY: 540) == .dragEnded(160),
            "releasing the colored label body completes the reorder drag"
        )
        var labelClick = TabPointerDragSession()
        labelClick.mouseDown(screenY: 700)
        check(
            labelClick.mouseUp(screenY: 700) == .clicked,
            "a stationary colored-label click still opens its note"
        )
        var jitteredLabelClick = TabPointerDragSession()
        jitteredLabelClick.mouseDown(screenY: 700)
        _ = jitteredLabelClick.mouseDragged(screenY: 697)
        check(
            jitteredLabelClick.mouseUp(screenY: 697) == .clicked,
            "a normal click with three pixels of pointer jitter still opens its note"
        )
        let nativeLabelSurface = TabPointerTrackingView(
            frame: NSRect(x: 0, y: 0, width: DeckLayout.tabWidth, height: DeckLayout.tabVisualHeight)
        )
        let nativeLabelPanel = NSPanel(
            contentRect: nativeLabelSurface.bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        nativeLabelPanel.contentView = nativeLabelSurface
        nativeLabelPanel.orderBack(nil)
        defer { nativeLabelPanel.orderOut(nil) }
        var nativeLabelEvents: [TabPointerEvent] = []
        nativeLabelSurface.onDragChanged = { translation, _ in
            nativeLabelEvents.append(.dragChanged(translation))
        }
        nativeLabelSurface.onDragEnded = { translation, _ in
            nativeLabelEvents.append(.dragEnded(translation))
        }
        nativeLabelSurface.onClick = { nativeLabelEvents.append(.clicked) }
        func pointerEvent(_ type: NSEvent.EventType, y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(
                with: type,
                location: NSPoint(x: DeckLayout.tabWidth / 2, y: y),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: nativeLabelPanel.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )!
        }
        nativeLabelSurface.mouseDown(with: pointerEvent(.leftMouseDown, y: 170))
        check(nativeLabelEvents.isEmpty, "pressing the colored label preserves native drag capture")
        nativeLabelSurface.mouseDragged(with: pointerEvent(.leftMouseDragged, y: 164))
        nativeLabelSurface.mouseDragged(with: pointerEvent(.leftMouseDragged, y: 30))
        nativeLabelSurface.mouseUp(with: pointerEvent(.leftMouseUp, y: 10))
        check(
            nativeLabelEvents == [.dragChanged(6), .dragChanged(140), .dragEnded(160)],
            "the native colored-label surface delivers a complete drag and drop event sequence"
        )
        nativeLabelEvents.removeAll()
        nativeLabelSurface.mouseDown(with: pointerEvent(.leftMouseDown, y: 170))
        nativeLabelSurface.mouseDragged(with: pointerEvent(.leftMouseDragged, y: 167))
        nativeLabelSurface.mouseUp(with: pointerEvent(.leftMouseUp, y: 167))
        check(
            nativeLabelEvents == [.dragChanged(3), .clicked],
            "the mounted label surface opens after a small accidental pointer movement"
        )
        var trackingHeld = false
        nativeLabelSurface.onTrackingChanged = { tracking, _ in trackingHeld = tracking }
        nativeLabelSurface.mouseDown(with: pointerEvent(.leftMouseDown, y: 170))
        NotificationCenter.default.post(name: .dockNotesPointerReleased, object: nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        check(!trackingHeld, "a missed native mouse-up releases the automatic-collapse hold")
        nativeLabelSurface.mouseDown(with: pointerEvent(.leftMouseDown, y: 170))
        NotificationCenter.default.post(name: .dockNotesPointerReleased, object: nil)
        nativeLabelSurface.mouseUp(with: pointerEvent(.leftMouseUp, y: 170))
        nativeLabelSurface.mouseDown(with: pointerEvent(.leftMouseDown, y: 170))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        check(trackingHeld, "an old native release cannot unlock the next pointer session")
        nativeLabelSurface.mouseUp(with: pointerEvent(.leftMouseUp, y: 170))
        let dragProbeFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockNotes-drag-probe-\(UUID().uuidString)", isDirectory: true)
        let dragProbeFile = dragProbeFolder.appendingPathComponent("notes.json")
        try? FileManager.default.createDirectory(at: dragProbeFolder, withIntermediateDirectories: true)
        let dragProbeNote = DockNote(title: "Drag probe")
        let dragProbeEncoder = JSONEncoder()
        dragProbeEncoder.dateEncodingStrategy = .iso8601
        try? dragProbeEncoder.encode([dragProbeNote, DockNote(title: "Second drag probe")]).write(to: dragProbeFile)
        let dragProbeStore = NotesStore(fileURL: dragProbeFile)
        let dragProbeDefaults = UserDefaults(suiteName: "DockNotes.DragProbe.\(UUID().uuidString)")!
        let dragProbeSettings = AppSettings(defaults: dragProbeDefaults)
        let dragProbeHost = NSHostingView(
            rootView: DeckWindowView(
                store: dragProbeStore,
                settings: dragProbeSettings,
                availableHeight: 520
            )
            .frame(width: DeckLayout.windowWidth, height: 520)
        )
        dragProbeHost.frame = NSRect(x: 0, y: 0, width: DeckLayout.windowWidth, height: 520)
        let dragProbePanel = NSPanel(
            contentRect: dragProbeHost.bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        dragProbePanel.contentView = dragProbeHost
        dragProbePanel.alphaValue = 0
        dragProbePanel.orderBack(nil)
        dragProbeHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        dragProbeHost.layoutSubtreeIfNeeded()
        let mountedLabelSurfaces = descendants(of: dragProbeHost, as: TabPointerTrackingView.self)
        check(!mountedLabelSurfaces.isEmpty, "the deck mounts a native drag surface on its colored labels")
        let mountedLabelSurface = mountedLabelSurfaces[0]
        let windowsBeforeHover = Set(NSApp.windows.map(ObjectIdentifier.init))
        mountedLabelSurface.mouseEntered(with: NSEvent.enterExitEvent(
            with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: dragProbePanel.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil
        )!)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.60))
        let hoverWindows = NSApp.windows.filter {
            !windowsBeforeHover.contains(ObjectIdentifier($0)) && $0.isVisible
        }
        check(!hoverWindows.isEmpty, "the mounted label displays its hover preview")
        check(
            hoverWindows.allSatisfy { $0.ignoresMouseEvents && !$0.canBecomeKey },
            "label hover previews must not intercept the next drag or take keyboard focus"
        )
        let mountedStartY = mountedLabelSurface.convert(mountedLabelSurface.bounds, to: dragProbeHost).midY
        let mountedCenter = mountedLabelSurface.convert(
            NSPoint(x: mountedLabelSurface.bounds.midX, y: mountedLabelSurface.bounds.midY),
            to: nil
        )
        func mountedPointerEvent(_ type: NSEvent.EventType, location: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: dragProbePanel.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )!
        }
        dragProbePanel.sendEvent(mountedPointerEvent(.leftMouseDown, location: mountedCenter))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        dragProbePanel.sendEvent(
            mountedPointerEvent(
                .leftMouseDragged,
                location: NSPoint(x: mountedCenter.x, y: mountedCenter.y - 50)
            )
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        dragProbeHost.layoutSubtreeIfNeeded()
        let mountedDraggedY = mountedLabelSurface.convert(mountedLabelSurface.bounds, to: dragProbeHost).midY
        check(
            mountedLabelSurface.superview != nil && abs(mountedDraggedY - mountedStartY) >= 40,
            "the mounted colored label remains attached and follows the pointer throughout the drag"
        )
        dragProbeStore.pointerExitedDeck(keepOpen: false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.75))
        check(
            dragProbeStore.deckState.showsTabs && mountedLabelSurface.window === dragProbePanel,
            "holding a label outside the deck must not collapse and destroy its drag surface"
        )
        dragProbePanel.sendEvent(
            mountedPointerEvent(
                .leftMouseUp,
                location: NSPoint(x: mountedCenter.x, y: mountedCenter.y - 50)
            )
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.75))
        check(
            dragProbeStore.deckState.showsTabs,
            "a release inside the deck corrects a stale exit and keeps the next label draggable"
        )
        for iteration in 0..<30 {
            dragProbeStore.pointerEnteredDeck()
            let readyDeadline = Date(timeIntervalSinceNow: 1)
            var surfaces: [TabPointerTrackingView] = []
            repeat {
                dragProbeHost.layoutSubtreeIfNeeded()
                surfaces = descendants(of: dragProbeHost, as: TabPointerTrackingView.self)
                    .sorted {
                        $0.convert($0.bounds, to: dragProbeHost).minY
                            < $1.convert($1.bounds, to: dragProbeHost).minY
                    }
                if surfaces.count == 2 && surfaces.allSatisfy(\.previewsEnabled) { break }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            } while Date() < readyDeadline
            check(
                surfaces.count == 2 && surfaces.allSatisfy(\.previewsEnabled),
                "repeated drag settles and retains both mounted labels"
            )
            let surface = surfaces[0]
            surface.showPreviewForTesting()
            check(
                dragProbePanel.childWindows?.contains { $0.isVisible && $0.ignoresMouseEvents } == true,
                "hover preview remains available before repeated drag \(iteration)"
            )
            let rect = surface.convert(surface.bounds, to: dragProbeHost)
            let start = dragProbeHost.convert(NSPoint(x: rect.midX, y: rect.minY + 25), to: nil)
            let pitch = DeckLayout.tabPitch(for: 520, slotCount: 2)
            let end = NSPoint(x: start.x, y: start.y - pitch)
            let previousOrder = dragProbeStore.notes.map(\.id)
            dragProbePanel.sendEvent(mountedPointerEvent(.leftMouseDown, location: start))
            check(
                dragProbePanel.childWindows?.isEmpty != false,
                "pressing a label dismisses its preview without retaining an input window"
            )
            dragProbePanel.sendEvent(mountedPointerEvent(.leftMouseDragged, location: end))
            if iteration % 10 == 0 {
                dragProbeStore.pointerExitedDeck(keepOpen: false)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.70))
                check(dragProbeStore.deckState.showsTabs, "repeated drag survives an extended pointer exit")
            }
            dragProbePanel.sendEvent(mountedPointerEvent(.leftMouseUp, location: end))
            check(
                dragProbeStore.notes.map(\.id) == Array(previousOrder.reversed()),
                "mounted panel reorder succeeds at iteration \(iteration)"
            )
        }
        dragProbeStore.pointerEnteredDeck()
        dragProbeHost.layoutSubtreeIfNeeded()
        let finalClickSurface = descendants(of: dragProbeHost, as: TabPointerTrackingView.self)[0]
        let finalClickPoint = finalClickSurface.convert(
            NSPoint(x: finalClickSurface.bounds.midX, y: finalClickSurface.bounds.midY), to: nil
        )
        dragProbePanel.sendEvent(mountedPointerEvent(.leftMouseDown, location: finalClickPoint))
        dragProbePanel.sendEvent(mountedPointerEvent(
            .leftMouseDragged, location: NSPoint(x: finalClickPoint.x, y: finalClickPoint.y - 3)
        ))
        dragProbePanel.sendEvent(mountedPointerEvent(
            .leftMouseUp, location: NSPoint(x: finalClickPoint.x, y: finalClickPoint.y - 3)
        ))
        check(
            dragProbeStore.deckState.openNoteID != nil,
            "a colored side label still opens its note after repeated reorders and pointer jitter"
        )
        dragProbeStore.collapseActive(keepDeckOpen: true)
        dragProbePanel.orderOut(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.30))
        dragProbeStore.pointerExitedDeck(keepOpen: false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.75))
        check(dragProbeStore.deckState == .resting, "releasing the label restores automatic collapse")
        check(defaultSlotPlan.overflowIDs == tenNotes.dropFirst(4).map(\.id), "only notes after the configured slots enter More Notes")
        check(DeckLayout.tabWidth == 48, "stacked edge tabs use a slender 48-point paper strip")
        check(
            DeckLayout.controlsHeight == DeckLayout.controlStackHeight(count: 4),
            "the deck reserves the full height of every persistent control"
        )
        let compactPitch = DeckLayout.tabPitch(for: 640, slotCount: 4)
        check(
            DeckLayout.deckStackHeight(noteSlotCount: 4, pitch: compactPitch)
                + DeckLayout.controlsHeight <= 640,
            "the paper-style new-note card and utilities fit together on a compact display"
        )
        check(
            DeckLayout.restingActivationWidth <= 2,
            "a resting deck activates only when the pointer reaches the screen edge"
        )
        check(DeckLayout.tabVisualHeight > DeckLayout.tabHeight, "paper tabs overlap while preserving the drag pitch")
        let defaultTabPitch = DeckLayout.tabPitch(for: 800, slotCount: 4)
        check(defaultTabPitch > DeckLayout.tabHeight, "four default tabs retain the airy spacing shown in the reference")
        let denseTabPitch = DeckLayout.tabPitch(for: 800, slotCount: 7)
        check(
            EdgeTabLayout.contentTopInset + EdgeTabLayout.titleContentLength <= denseTabPitch,
            "the fixed edge-tab title slot stays inside the minimum visible pitch"
        )
        check(
            DeckLayout.capacity(for: 800, preferredVisibleCount: 7) == 5
                && DeckLayout.capacity(for: 900, preferredVisibleCount: 7) == 6
                && DeckLayout.capacity(for: 1_040, preferredVisibleCount: 7) == 7,
            "the deck shows up to seven tabs while adapting to shorter screens"
        )
        check(
            EdgeTabLayout.contentTopInset >= 22,
            "edge-tab titles keep approximately two CJK glyphs of breathing room above them"
        )
        check(
            EdgeTabLayout.deadlineTopInset < EdgeTabLayout.contentTopInset,
            "the horizontal deadline occupies the reserved area above the vertical title"
        )
        var reminderCalendar = Calendar(identifier: .gregorian)
        reminderCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reminderDay = reminderCalendar.date(
            from: DateComponents(year: 2027, month: 2, day: 3, hour: 8, minute: 5)
        )!
        let parsed24Hour = ReminderTimeInput.parse("21:30", on: reminderDay, calendar: reminderCalendar)
        let parsed12Hour = ReminderTimeInput.parse("9:30 PM", on: reminderDay, calendar: reminderCalendar)
        check(
            parsed24Hour.map {
                reminderCalendar.component(.hour, from: $0) == 21
                    && reminderCalendar.component(.minute, from: $0) == 30
            } == true,
            "manual reminder input accepts 24-hour time"
        )
        check(
            parsed12Hour.map {
                reminderCalendar.component(.hour, from: $0) == 21
                    && reminderCalendar.component(.minute, from: $0) == 30
            } == true,
            "manual reminder input accepts 12-hour time"
        )
        check(
            ReminderTimeInput.parse("25:00", on: reminderDay, calendar: reminderCalendar) == nil,
            "manual reminder input rejects invalid time"
        )
        let longHoverTitle = "这是一个用于验证固定排版与悬浮信息的很长标题"
        let hoverInfo = EdgeTabHoverInfo.make(
            note: DockNote(title: longHoverTitle, body: "第一行\n  第二行", isPinned: true),
            language: .simplifiedChinese
        )
        check(hoverInfo.title == longHoverTitle, "hover information preserves the complete long title")
        check(hoverInfo.preview == "第一行 第二行", "hover information presents a compact content preview")
        check(hoverInfo.isPinned, "hover information preserves pinned state")
        check(
            DeckLayout.tabStackHeight(slotCount: 4, pitch: defaultTabPitch)
                == DeckLayout.tabVisualHeight + defaultTabPitch * 3,
            "the stacked deck reserves its visible overhang before the round controls"
        )
        check(DeckLayout.tiltDegrees(for: 0) != DeckLayout.tiltDegrees(for: 1), "adjacent paper tabs use alternating tilt angles")
        check(!PanelCoordinator.localClickIsOutsideApp(hasWindow: true), "a More Notes popover click remains an in-app click")
        check(PanelCoordinator.localClickIsOutsideApp(hasWindow: false), "a local event without a DockNotes window is outside")
        check(
            !PanelCoordinator.localClickIsOutsideApp(
                hasWindow: false,
                point: NSPoint(x: 59, y: 400),
                appWindowFrames: [NSRect(x: 0, y: 0, width: 60, height: 800)]
            ),
            "a windowless mouse event over the edge-label panel remains an in-app click"
        )
        check(PanelCoordinator.deckWindowLevel.rawValue > PanelCoordinator.noteWindowLevel.rawValue, "the edge deck and its More Notes popover stay above an open note")
        check(ColorInput.hex(red: "12", green: "34", blue: "56") == "#0C2238", "RGB converts to hex")
        check(ColorInput.hex(red: "256", green: "0", blue: "0") == nil, "RGB rejects out-of-range values")
        check(ColorInput.normalizedHex(" 7ead94 ") == "#7EAD94", "hex input is normalized")
        check(Set(NoteHighlightPalette.colors).count == 6, "text highlighting offers six distinct preset colors")
        check(
            NoteHighlightPalette.hex(from: Color(hex: "#93C5FD")) == "#93C5FD",
            "the custom highlight picker preserves the selected RGB color"
        )
        let coloredSelection = NSMutableAttributedString(string: "彩色高亮")
        let coloredRange = NSRange(location: 0, length: 2)
        NoteHighlightFormatter.apply(hex: "#93C5FD", to: coloredSelection, range: coloredRange)
        check(
            coloredSelection.attribute(.backgroundColor, at: 1, effectiveRange: nil) is NSColor,
            "the chosen highlight color is applied to the selected text"
        )
        let coloredRTF = try? coloredSelection.data(
            from: NSRange(location: 0, length: coloredSelection.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let restoredColoredSelection = coloredRTF.flatMap {
            try? NSAttributedString(
                data: $0,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        }
        check(
            restoredColoredSelection?.attribute(.backgroundColor, at: 1, effectiveRange: nil) is NSColor,
            "the selected highlight color survives rich-text persistence"
        )
        NoteHighlightFormatter.apply(hex: nil, to: coloredSelection, range: coloredRange)
        check(
            coloredSelection.attribute(.backgroundColor, at: 1, effectiveRange: nil) == nil,
            "selected-text highlighting can be cleared explicitly"
        )
        check(
            AIClient.endpointURL(from: "https://example.com/v1", provider: .openAICompatible)?.absoluteString
                == "https://example.com/v1/chat/completions",
            "AI configuration accepts an OpenAI-compatible base URL"
        )
        check(
            AIClient.endpointURL(from: "not a URL", provider: .openAICompatible) == nil,
            "AI configuration rejects an invalid service URL"
        )
        check(
            AIClient.endpointURL(from: "https://api.anthropic.com/v1", provider: .anthropic)?.absoluteString
                == "https://api.anthropic.com/v1/messages",
            "Anthropic configuration resolves the native Messages API endpoint"
        )
        check(
            AIClient.endpointURL(from: "https://api.anthropic.com/v1/messages/", provider: .anthropic)?.absoluteString
                == "https://api.anthropic.com/v1/messages",
            "Anthropic accepts a complete Messages endpoint with a trailing slash"
        )
        let anthropicRequest = try? AIClient.makeRequest(
            configuration: AIConfiguration(
                provider: .anthropic,
                endpoint: "https://api.anthropic.com/v1",
                model: "claude-test",
                apiKey: "anthropic-test-key"
            ),
            note: DockNote(title: "Request Test", body: "Context"),
            prompt: "Summarize",
            language: .english
        )
        check(anthropicRequest?.value(forHTTPHeaderField: "x-api-key") == "anthropic-test-key", "Anthropic uses x-api-key authentication")
        check(anthropicRequest?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01", "Anthropic sends the required API version header")
        if let body = anthropicRequest?.httpBody,
           let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            check(object["system"] != nil && object["max_tokens"] as? Int == 2_048, "Anthropic uses the native Messages request body")
        } else {
            check(false, "Anthropic request body can be inspected")
        }

        let orderedText = "1. one\n2. two\n3. three\n4. four"
        let orderedCaret = ("1. one\n2. two" as NSString).length
        let orderedResult = OrderedListEditing.insertingReturn(
            in: orderedText,
            selectedRange: NSRange(location: orderedCaret, length: 0)
        )
        check(
            orderedResult.text == "1. one\n2. two\n3. \n4. three\n5. four",
            "inserting an ordered item renumbers the following contiguous items"
        )
        check(orderedResult.selectedRange.location == orderedCaret + 4, "ordered-list insertion places the cursor after the new marker")

        let note = DockNote(
            title: "中文标题",
            body: "English body",
            material: .paper
        )
        let original = note
        _ = L10n.text(.preferences, language: .simplifiedChinese)
        _ = L10n.text(.preferences, language: .english)
        check(
            L10n.text(.deadlineReached, language: .simplifiedChinese) == "截止时间已到"
                && L10n.text(.deadlineReached, language: .english) == "Deadline reached",
            "deadline notifications follow the selected interface language"
        )
        check(note == original, "language switching mutated note content")

        let styledBody = NSMutableAttributedString(string: "Persistent formatting")
        styledBody.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: styledBody.length)
        )
        let styledRTF = try? styledBody.data(
            from: NSRange(location: 0, length: styledBody.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let appendedStyledRTF = RichTextBody.appendingPlainText("\nAI result", to: styledBody.string, rtfData: styledRTF)
        let appendedStyledBody = appendedStyledRTF.flatMap {
            try? NSAttributedString(
                data: $0,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        }
        check(
            appendedStyledBody?.string == "Persistent formatting\nAI result"
                && (appendedStyledBody?.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? NSNumber)?.intValue != 0
                && appendedStyledBody?.attribute(
                    .underlineStyle,
                    at: ("Persistent formatting\n" as NSString).length,
                    effectiveRange: nil
                ) == nil,
            "programmatic appends preserve existing rich text without leaking its style"
        )
        let styledNote = DockNote(title: "Rich text", body: styledBody.string, bodyRTF: styledRTF)
        let styledEncoded = try? JSONEncoder().encode(styledNote)
        let styledDecoded = styledEncoded.flatMap { try? JSONDecoder().decode(DockNote.self, from: $0) }
        check(
            styledDecoded?.body == styledBody.string && styledDecoded?.bodyRTF == styledRTF,
            "rich-text formatting persists alongside searchable plain text"
        )

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent("notes.json")
        defer { try? FileManager.default.removeItem(at: folder) }

        let workspaceEncoder = JSONEncoder()
        workspaceEncoder.dateEncodingStrategy = .iso8601
        let workspaceDecoder = JSONDecoder()
        workspaceDecoder.dateDecodingStrategy = .iso8601
        let legacyFile = folder.appendingPathComponent("legacy-workspaces.json")
        let legacyNotes = [
            DockNote(title: "Legacy A", body: "Alpha"),
            DockNote(title: "Legacy B", body: "Beta", isArchived: true),
            DockNote(title: "Legacy C", body: "Gamma")
        ]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? workspaceEncoder.encode(legacyNotes).write(to: legacyFile, options: .atomic)
        let migratedWorkspaceStore = NotesStore(fileURL: legacyFile)
        check(migratedWorkspaceStore.workspaces.count == 1, "legacy notes migrate into one default workspace")
        check(
            migratedWorkspaceStore.notes.map(\.id) == [legacyNotes[0].id, legacyNotes[2].id]
                && migratedWorkspaceStore.archivedNotes.map(\.id) == [legacyNotes[1].id]
                && migratedWorkspaceStore.notes.map(\.body) == ["Alpha", "Gamma"],
            "workspace migration preserves note IDs, content, archive state, and collection order"
        )
        check(
            (migratedWorkspaceStore.notes + migratedWorkspaceStore.archivedNotes)
                .allSatisfy { $0.workspaceID == migratedWorkspaceStore.defaultWorkspaceID },
            "workspace migration assigns every legacy note to the default workspace"
        )
        check(
            FileManager.default.fileExists(atPath: legacyFile.appendingPathExtension("pre-v0.9").path),
            "workspace migration retains a one-time pre-v0.9 backup"
        )
        let migratedDocument = (try? Data(contentsOf: legacyFile)).flatMap {
            try? workspaceDecoder.decode(DockNotesDocument.self, from: $0)
        }
        check(
            migratedDocument?.schemaVersion == DockNotesDocument.currentSchemaVersion,
            "workspace migration rewrites storage as the versioned document format"
        )

        let defaultWorkspaceID = migratedWorkspaceStore.defaultWorkspaceID
        let createdWorkspace = migratedWorkspaceStore.createWorkspace(
            name: "项目组",
            colorHex: "#123456"
        )!
        check(
            WorkspaceDropRouting.enteredCapsule(
                at: CGPoint(x: 98, y: 118),
                capsuleFrame: CGRect(x: 100, y: 120, width: 38, height: 29)
            ),
            "cross-workspace drag opens the chooser as soon as the pointer reaches the capsule"
        )
        let otherDropWorkspaceID = UUID()
        check(
            WorkspaceDropRouting.targetWorkspace(
                at: CGPoint(x: 220, y: 180),
                currentWorkspaceID: defaultWorkspaceID,
                frames: [
                    defaultWorkspaceID: CGRect(x: 200, y: 130, width: 180, height: 34),
                    otherDropWorkspaceID: CGRect(x: 200, y: 170, width: 180, height: 34)
                ]
            ) == otherDropWorkspaceID,
            "cross-workspace drag selects the hovered non-current workspace row"
        )
        check(
            migratedWorkspaceStore.activeWorkspaceID == createdWorkspace.id
                && migratedWorkspaceStore.activeWorkspaceNotes.isEmpty,
            "creating a workspace can activate its empty tab group"
        )
        check(
            migratedWorkspaceStore.renameWorkspace(createdWorkspace.id, to: "交付组")
                && migratedWorkspaceStore.setWorkspaceColor(createdWorkspace.id, colorHex: "#654321")
                && migratedWorkspaceStore.workspace(id: createdWorkspace.id)?.name == "交付组"
                && migratedWorkspaceStore.workspace(id: createdWorkspace.id)?.colorHex == "#654321",
            "workspace name and color are editable and persisted through the store"
        )
        migratedWorkspaceStore.moveWorkspace(createdWorkspace.id, to: 0)
        check(migratedWorkspaceStore.workspaces.first?.id == createdWorkspace.id, "workspaces can be reordered")
        migratedWorkspaceStore.addNote(language: .simplifiedChinese)
        let projectNoteID = migratedWorkspaceStore.activeNoteID!
        check(
            migratedWorkspaceStore.note(id: projectNoteID)?.workspaceID == createdWorkspace.id,
            "new notes belong to the current workspace"
        )
        migratedWorkspaceStore.moveNote(projectNoteID, toWorkspace: defaultWorkspaceID, at: 1)
        check(
            migratedWorkspaceStore.note(id: projectNoteID)?.workspaceID == defaultWorkspaceID
                && migratedWorkspaceStore.activeWorkspaceID == createdWorkspace.id,
            "a note can move to another workspace at an explicit group position without switching groups"
        )
        migratedWorkspaceStore.moveNote(projectNoteID, toWorkspace: createdWorkspace.id)
        migratedWorkspaceStore.select(projectNoteID)
        migratedWorkspaceStore.presentOnDesktop(projectNoteID)
        for index in 0..<100 {
            migratedWorkspaceStore.switchWorkspace(
                to: index.isMultiple(of: 2) ? defaultWorkspaceID : createdWorkspace.id
            )
        }
        check(
            migratedWorkspaceStore.activeWorkspaceID == createdWorkspace.id
                && migratedWorkspaceStore.deckState == .fanned
                && migratedWorkspaceStore.desktopNoteIDs.contains(projectNoteID),
            "one hundred workspace switches keep the deck collapsed and detached notes visible"
        )
        migratedWorkspaceStore.switchWorkspace(to: defaultWorkspaceID)
        migratedWorkspaceStore.presentOnDesktop(projectNoteID)
        check(
            migratedWorkspaceStore.activeWorkspaceID == defaultWorkspaceID
                && migratedWorkspaceStore.deckState == .fanned
                && !migratedWorkspaceStore.desktopNoteIDs.contains(projectNoteID),
            "returning a desktop note preserves its original workspace without forcing a switch"
        )
        migratedWorkspaceStore.switchWorkspace(to: createdWorkspace.id)
        for _ in 0..<3 { migratedWorkspaceStore.addNote(language: .english) }
        let reorderIDs = Set(migratedWorkspaceStore.activeWorkspaceNotes.map(\.id))
        for _ in 0..<100 {
            guard let firstID = migratedWorkspaceStore.activeWorkspaceNotes.first?.id else { break }
            migratedWorkspaceStore.moveNote(
                firstID,
                toWorkspace: createdWorkspace.id,
                at: migratedWorkspaceStore.activeWorkspaceNotes.count - 1
            )
        }
        check(
            Set(migratedWorkspaceStore.activeWorkspaceNotes.map(\.id)) == reorderIDs
                && migratedWorkspaceStore.activeWorkspaceNotes.count == reorderIDs.count,
            "one hundred group-local reorders preserve every tab and remain operable"
        )
        if let firstID = migratedWorkspaceStore.activeWorkspaceNotes.first?.id {
            migratedWorkspaceStore.moveNote(firstID, toWorkspace: createdWorkspace.id, at: 1)
        }
        let bulkIDs = Set(migratedWorkspaceStore.activeWorkspaceNotes
            .filter { $0.id != projectNoteID }
            .prefix(2)
            .map(\.id))
        migratedWorkspaceStore.moveNotes(bulkIDs, toWorkspace: defaultWorkspaceID)
        check(
            bulkIDs.allSatisfy {
                migratedWorkspaceStore.note(id: $0)?.workspaceID == defaultWorkspaceID
            } && migratedWorkspaceStore.activeWorkspaceID == createdWorkspace.id,
            "bulk moving notes updates ownership without changing the current workspace"
        )
        migratedWorkspaceStore.moveNotes(bulkIDs, toWorkspace: createdWorkspace.id)
        migratedWorkspaceStore.select(projectNoteID)
        migratedWorkspaceStore.archive(projectNoteID)
        check(
            migratedWorkspaceStore.archivedNotes.first(where: { $0.id == projectNoteID })?.workspaceID == createdWorkspace.id,
            "archiving retains workspace ownership"
        )
        check(migratedWorkspaceStore.deleteWorkspace(createdWorkspace.id), "a non-default workspace can be safely deleted")
        check(
            migratedWorkspaceStore.archivedNotes.first(where: { $0.id == projectNoteID })?.workspaceID == defaultWorkspaceID,
            "deleting a workspace moves its archived notes to the default workspace"
        )
        migratedWorkspaceStore.undoLatestWorkspaceDeletion()
        check(
            migratedWorkspaceStore.workspace(id: createdWorkspace.id) != nil
                && migratedWorkspaceStore.archivedNotes.first(where: { $0.id == projectNoteID })?.workspaceID == createdWorkspace.id,
            "workspace deletion undo restores the group and its note ownership"
        )
        migratedWorkspaceStore.restoreArchived(projectNoteID)
        migratedWorkspaceStore.switchWorkspace(to: createdWorkspace.id)
        migratedWorkspaceStore.select(projectNoteID)
        migratedWorkspaceStore.flushPendingSave()
        let restartedWorkspaceStore = NotesStore(fileURL: legacyFile)
        check(
            restartedWorkspaceStore.activeWorkspaceID == createdWorkspace.id
                && restartedWorkspaceStore.activeNoteID == projectNoteID
                && restartedWorkspaceStore.workspaces.first?.id == createdWorkspace.id,
            "workspace order, selection, and last active note survive a restart"
        )

        let invalidWorkspaceFile = folder.appendingPathComponent("invalid-workspace.json")
        let validWorkspace = NoteWorkspace(name: "Valid")
        let orphanedNote = DockNote(title: "Orphan", workspaceID: UUID())
        let invalidDocument = DockNotesDocument(
            activeWorkspaceID: UUID(),
            defaultWorkspaceID: UUID(),
            workspaces: [validWorkspace],
            notes: [orphanedNote]
        )
        try? workspaceEncoder.encode(invalidDocument).write(to: invalidWorkspaceFile, options: .atomic)
        let repairedWorkspaceStore = NotesStore(fileURL: invalidWorkspaceFile)
        check(
            repairedWorkspaceStore.defaultWorkspaceID == validWorkspace.id
                && repairedWorkspaceStore.activeWorkspaceID == validWorkspace.id
                && repairedWorkspaceStore.notes.first?.workspaceID == validWorkspace.id,
            "invalid workspace references repair to a valid default without losing notes"
        )

        let first = NotesStore(fileURL: file)
        let exportDirectory = folder.appendingPathComponent("Obsidian", isDirectory: true)
        let exportNote = DockNote(title: "AI / Archive Test", body: "Portable Markdown")
        let exportedURL = try? ObsidianArchiveExporter.export(exportNote, to: exportDirectory)
        check(exportedURL?.lastPathComponent == "AI Archive Test.md", "Obsidian backup sanitizes note filenames")
        check(
            (try? String(contentsOf: exportedURL!, encoding: .utf8))?.contains("docknotes-id: \(exportNote.id.uuidString)") == true,
            "Obsidian backup includes stable DockNotes metadata"
        )
        let exportIndex = try? String(
            contentsOf: exportDirectory.appendingPathComponent("DockNotes Archive Index.md"),
            encoding: .utf8
        )
        check(exportIndex?.contains("[[AI Archive Test]]") == true, "Obsidian backup maintains a wikilink index")
        let archiveBackupStore = NotesStore(fileURL: folder.appendingPathComponent("archive-backup.json"))
        let archivedBackupID = archiveBackupStore.notes[0].id
        archiveBackupStore.archive(
            archivedBackupID,
            obsidianDirectory: exportDirectory,
            obsidianBackupEnabled: true
        )
        check(
            archiveBackupStore.archivedNotes.contains(where: { $0.id == archivedBackupID }),
            "Obsidian backup preserves the DockNotes in-app archive"
        )
        check(
            archiveBackupStore.lastObsidianBackupURL != nil && archiveBackupStore.lastObsidianBackupError == nil,
            "archiving through the app writes the configured Obsidian backup"
        )
        let windowDefaults = UserDefaults(suiteName: "DockNotes.WindowSelfCheck.\(UUID().uuidString)")!
        let windowSettings = AppSettings(defaults: windowDefaults)
        let edgeSwitchStore = NotesStore(fileURL: folder.appendingPathComponent("edge-switch.json"))
        edgeSwitchStore.dismissDeck()
        let edgeSwitchCoordinator = PanelCoordinator(
            store: edgeSwitchStore,
            settings: windowSettings,
            visibleFrameOverride: NSRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        edgeSwitchCoordinator.start()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        let rightEdgeFrame = edgeSwitchCoordinator.edgePanelFrameForTesting
        windowSettings.deckEdge = .left
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        let leftEdgeFrame = edgeSwitchCoordinator.edgePanelFrameForTesting
        check(
            rightEdgeFrame != nil
                && leftEdgeFrame != nil
                && leftEdgeFrame!.minX < rightEdgeFrame!.minX - 100,
            "changing the deck side repositions the collapsed edge UI immediately without another click"
        )
        check(
            edgeSwitchCoordinator.edgeInteractionRefreshMatchesCommittedEdgeForTesting,
            "the moved edge panel refreshes hover activation only after the new side is committed"
        )
        let switchedActivationViews = edgeSwitchCoordinator.edgePanelContentViewForTesting.map {
            descendants(of: $0, as: RestingDeckActivationView.self)
        } ?? []
        check(
            switchedActivationViews.count == 1 && !switchedActivationViews[0].trackingAreas.isEmpty,
            "the switched resting edge owns a live native hover tracking area"
        )
        switchedActivationViews.first?.mouseEntered(with: NSEvent.enterExitEvent(
            with: .mouseEntered,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: edgeSwitchCoordinator.edgePanelContentViewForTesting?.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            trackingNumber: 0,
            userData: nil
        )!)
        check(
            edgeSwitchStore.deckState.showsTabs,
            "hovering the new screen edge after switching sides fans the labels without a click"
        )
        let settingsDragWindow = edgeSwitchCoordinator.settingsWindowForTesting
        let settingsTitlebar = settingsDragWindow?.standardWindowButton(.closeButton)?.superview
        let titlebarDragHandles = settingsTitlebar.map {
            descendants(of: $0, as: SettingsTitlebarDragView.self)
        } ?? []
        let titlebarHitTestReachesDragHandle = settingsTitlebar.map { titlebar in
            let point = titlebar.convert(
                NSPoint(x: titlebar.bounds.midX, y: titlebar.bounds.midY),
                to: titlebar.superview
            )
            return titlebar.hitTest(point) === titlebarDragHandles.first
        } ?? false
        check(
            settingsDragWindow?.isMovable == true
                && titlebarDragHandles.count == 1
                && (titlebarDragHandles.first?.frame.width ?? 0) > 400
                && titlebarHitTestReachesDragHandle,
            "the app-managed settings window exposes a wide native titlebar drag handle"
        )
        if let settingsDragWindow, let titlebarDragHandle = titlebarDragHandles.first {
            let initialOrigin = settingsDragWindow.frame.origin
            let downPoint = NSPoint(x: 380, y: settingsDragWindow.frame.height - 16)
            let draggedPoint = NSPoint(x: 422, y: settingsDragWindow.frame.height + 11)
            if let downEvent = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: downPoint,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: settingsDragWindow.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ), let draggedEvent = NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: draggedPoint,
                modifierFlags: [],
                timestamp: 0.02,
                windowNumber: settingsDragWindow.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ) {
                titlebarDragHandle.mouseDown(with: downEvent)
                titlebarDragHandle.mouseDragged(with: draggedEvent)
            }
            check(
                settingsDragWindow.frame.minX > initialOrigin.x + 30
                    && settingsDragWindow.frame.minY > initialOrigin.y + 20,
                "dragging the settings titlebar actually changes the window position"
            )
        }
        edgeSwitchCoordinator.stop()
        windowSettings.deckEdge = .right
        let windowCoordinator = PanelCoordinator(store: first, settings: windowSettings)
        let desktopWindow = windowCoordinator.makeDesktopNoteWindow(for: first.notes[0].id)
        desktopWindow.orderFrontRegardless()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
        let initialContentSize = desktopWindow.frame.size
        check(
            abs(initialContentSize.width - 460) < 1 && abs(initialContentSize.height - 380) < 1,
            "a desktop note opens at its 460 by 380 default content size"
        )
        check(
            desktopWindow.styleMask.contains(.borderless)
                && desktopWindow.styleMask.contains(.resizable)
                && desktopWindow.isMovable
                && desktopWindow.isMovableByWindowBackground,
            "desktop notes support both resizing and background movement"
        )
        let movedOrigin = NSPoint(x: desktopWindow.frame.minX + 24, y: desktopWindow.frame.minY + 18)
        desktopWindow.setFrameOrigin(movedOrigin)
        check(
            abs(desktopWindow.frame.minX - movedOrigin.x) < 1
                && abs(desktopWindow.frame.minY - movedOrigin.y) < 1,
            "desktop note position changes are not blocked by the implicit-size guard"
        )
        (desktopWindow as? DesktopNoteWindow)?.setExplicitFrame(
            NSRect(origin: desktopWindow.frame.origin, size: CGSize(width: 700, height: 560)),
            display: false
        )
        let enlargedContentSize = desktopWindow.frame.size
        let enlargedHostingSize = desktopWindow.contentView?.subviews.first?.frame.size ?? .zero
        check(
            abs(enlargedContentSize.width - 700) < 1 && abs(enlargedContentSize.height - 560) < 1,
            "a desktop note and its hosted content resize beyond the default size"
        )
        check(
            abs(enlargedHostingSize.width - 700) < 1 && abs(enlargedHostingSize.height - 560) < 1,
            "the SwiftUI desktop note surface follows the enlarged native window"
        )
        let desktopRenderer = ImageRenderer(
            content: DesktopNoteWindowView(
                noteID: first.notes[0].id,
                store: first,
                settings: windowSettings
            )
            .frame(width: 700, height: 560)
            .environment(\.colorScheme, .light)
        )
        desktopRenderer.proposedSize = ProposedViewSize(width: 700, height: 560)
        desktopRenderer.scale = 1
        if let renderedImage = desktopRenderer.nsImage,
           let renderedTIFF = renderedImage.tiffRepresentation,
           let renderedBitmap = NSBitmapImageRep(data: renderedTIFF) {
            var pixel = [Int](repeating: 0, count: renderedBitmap.samplesPerPixel)
            renderedBitmap.getPixel(
                &pixel,
                atX: min(650, renderedBitmap.pixelsWide - 1),
                y: min(280, renderedBitmap.pixelsHigh - 1)
            )
            let alpha = renderedBitmap.hasAlpha ? (pixel.last ?? 0) : 255
            check(alpha > 0, "the enlarged desktop note paints its surface beyond the former 460-point limit")
        } else {
            check(false, "the enlarged desktop note can be rendered for layout verification")
        }
        desktopWindow.orderOut(nil)
        windowCoordinator.stop()

        let desktopExcludedPlan = DeckLayout.plan(
            notes: first.notes,
            activeNoteID: nil,
            isExpanded: false,
            availableHeight: 800,
            excludedNoteIDs: [first.notes[0].id]
        )
        check(
            !desktopExcludedPlan.slots.compactMap { $0 }.contains(first.notes[0].id)
                && !desktopExcludedPlan.overflowIDs.contains(first.notes[0].id),
            "a desktop-presented note has no duplicate entry in the edge deck"
        )
        check(
            desktopExcludedPlan.slots[0] == nil
                && desktopExcludedPlan.slots[1] == first.notes[1].id,
            "a desktop-presented note reserves its slot so later edge tabs do not jump"
        )
        let filledDesktopExcludedPlan = DeckLayout.plan(
            notes: tenNotes,
            activeNoteID: nil,
            isExpanded: false,
            availableHeight: 800,
            excludedNoteIDs: [tenNotes[0].id]
        )
        check(
            filledDesktopExcludedPlan.slots[0] == nil
                && filledDesktopExcludedPlan.slots[1] == tenNotes[1].id
                && filledDesktopExcludedPlan.slots.compactMap { $0 }.count == 4,
            "reserved desktop slots use spare vertical space without shifting tabs or reducing the configured visible count"
        )
        let reorderStore = NotesStore(fileURL: folder.appendingPathComponent("reorder.json"))
        let adjacentOrder = reorderStore.notes.map(\.id)
        reorderStore.moveNote(adjacentOrder[0], to: 1)
        check(
            reorderStore.notes.prefix(2).map(\.id) == [adjacentOrder[1], adjacentOrder[0]],
            "dragging the first tab onto the next slot visibly swaps their positions"
        )
        check(!first.isExpanded, "the app starts with only the edge deck visible")
        check(first.deckState == .fanned, "labelled tabs are visible by default")
        let transitionNoteID = UUID()
        check(
            DeckTransition.reduce(.resting, event: .pointerEntered) == .fanned,
            "the deck transition policy fans the resting edge on pointer entry"
        )
        check(
            DeckTransition.reduce(.fanned, event: .noteSelected(transitionNoteID))
                == .noteOpen(transitionNoteID),
            "the deck transition policy opens a selected side label"
        )
        check(
            DeckTransition.reduce(
                .noteOpen(transitionNoteID),
                event: .outsideClick(keepOpen: true, activeNotePinned: false)
            ) == .fanned,
            "an outside click returns an unpinned editor to visible labels"
        )
        check(
            DeckTransition.reduce(
                .noteOpen(transitionNoteID),
                event: .outsideClick(keepOpen: false, activeNotePinned: false)
            ) == .resting,
            "an outside click may fully rest an unpinned deck"
        )
        check(
            DeckTransition.reduce(
                .noteOpen(transitionNoteID),
                event: .outsideClick(keepOpen: false, activeNotePinned: true)
            ) == .noteOpen(transitionNoteID),
            "an outside click never collapses a pinned note"
        )
        check(
            DeckTransition.reduce(.resting, event: .noteReturnedFromDesktop(transitionNoteID))
                == .noteOpen(transitionNoteID),
            "returning a desktop note always restores its edge editor"
        )
        let originalFirstID = first.notes[0].id
        let originalSecondID = first.notes[1].id
        first.select(originalSecondID)
        first.updateTitle("只修改第一张", for: originalFirstID)
        first.updateBody("第一张正文", for: originalFirstID)
        check(first.notes.first(where: { $0.id == originalFirstID })?.title == "只修改第一张", "a delayed title edit remains attached to its original note")
        check(first.notes.first(where: { $0.id == originalFirstID })?.body == "第一张正文", "a delayed body edit remains attached to its original note")
        check(first.notes.first(where: { $0.id == originalSecondID })?.title != "只修改第一张", "switching notes cannot redirect a stale title edit")
        check(first.notes.first(where: { $0.id == originalSecondID })?.body != "第一张正文", "switching notes cannot redirect a stale body edit")
        first.select(originalFirstID)
        first.presentOnDesktop(originalFirstID)
        check(first.desktopNoteIDs == [originalFirstID], "the global expand action creates an independent desktop note")
        check(!first.isExpanded, "expanding to the desktop collapses the edge editor")
        first.presentOnDesktop(originalFirstID)
        check(first.desktopNoteIDs.isEmpty, "invoking desktop presentation again returns the note to its edge tab")
        check(
            first.deckState == .noteOpen(originalFirstID),
            "returning a desktop note restores its previously open edge editor"
        )
        check(
            PanelCoordinator.desktopWindowMaximumSize.width > PanelCoordinator.desktopWindowInitialSize.width
                && PanelCoordinator.desktopWindowMaximumSize.height > PanelCoordinator.desktopWindowInitialSize.height,
            "desktop notes can resize beyond their 460 by 380 default size"
        )
        first.presentOnDesktop(originalFirstID)
        check(
            !PanelCoordinator.desktopWindowStyleMask.contains(.closable)
                && !PanelCoordinator.desktopWindowStyleMask.contains(.miniaturizable),
            "desktop notes omit close and minimize window controls"
        )
        check(
            PanelCoordinator.desktopWindowLevel(isPinned: false) == .normal
                && PanelCoordinator.desktopWindowLevel(isPinned: true) == .floating,
            "pinning changes the native desktop note window level"
        )
        first.select(originalSecondID)
        let customGradient = NoteGradient(startHex: "#123456", endHex: "#ABCDEF")
        let desktopDueDate = Date(timeIntervalSince1970: 1_700_000_000)
        first.setGradient(customGradient, for: originalFirstID)
        first.setDueDate(desktopDueDate, for: originalFirstID)
        first.togglePinned(originalFirstID)
        check(first.note(id: originalFirstID)?.gradientEndHex == "#ABCDEF", "desktop note controls apply a custom two-stop gradient to their own note")
        check(first.note(id: originalFirstID)?.dueDate == desktopDueDate, "desktop note controls update their own date")
        check(first.note(id: originalFirstID)?.isPinned == true, "desktop note controls update their own pin state")
        check(first.note(id: originalSecondID)?.gradientEndHex != "#ABCDEF", "desktop note controls do not mutate the edge note")
        first.closeDesktopNote(originalFirstID)
        check(first.desktopNoteIDs.isEmpty, "a desktop note can close without deleting its content")
        first.select(originalFirstID)
        first.togglePinned(originalFirstID)
        first.setFontStyle(.serif, for: originalFirstID)
        first.setFontSize(19, for: originalFirstID)
        let initialOrder = first.notes.map(\.id)
        first.moveNote(initialOrder[0], to: 3)
        check(first.notes.map(\.id) == [initialOrder[1], initialOrder[2], initialOrder[3], initialOrder[0]], "drag reorder moves a tab to its visible destination slot")
        first.dismissDeck()
        check(first.deckState == .resting, "the deck supports a quiet resting state")
        first.pointerEnteredDeck()
        check(first.deckState == .fanned, "pointer entry fans out the deck")
        first.pointerExitedDeck(keepOpen: true)
        check(first.deckState == .fanned, "keep-open prevents pointer exit from folding the deck")
        first.dismissDeck()
        check(first.deckState == .resting, "the deck can return to rest")
        first.presentSettings()
        check(!first.isExpanded, "opening settings does not open a note")
        check(first.isPreferencesPresented, "settings opens independently")
        first.handleOutsideClick(keepDeckOpen: true)
        check(!first.isPreferencesPresented, "outside click closes settings")
        if let id = first.activeNoteID { first.select(id) }
        first.handleOutsideClick(keepDeckOpen: true)
        check(!first.isExpanded, "outside click collapses an unpinned note")
        check(first.deckState == .fanned, "outside click returns to labelled tabs when keep-open is enabled")
        if let id = first.activeNoteID { first.select(id) }
        first.togglePinned()
        first.handleOutsideClick(keepDeckOpen: true)
        check(first.isExpanded, "an outside click keeps a pinned note open and actually on top")
        first.togglePinned()
        first.handleOutsideClick(keepDeckOpen: true)

        first.updateTitle("持久化测试")
        first.updateBody("正文保持原样")
        first.insertTask()
        check(first.activeNote?.body.hasSuffix("☐ ") == true, "task tool inserts a checkbox")
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        first.setDueDate(dueDate)
        first.setMaterial(.paper)
        first.setGradient(NotePalette.gradients[2])
        first.collapseActive()
        check(!first.isExpanded, "single note collapse state")
        if let id = first.activeNoteID { first.select(id) }
        check(first.isExpanded, "collapsed tab reopens its note")
        check(first.saveState == .saving, "editing exposes a real saving state before the debounce completes")
        first.flushPendingSave()
        if case .saved = first.saveState {
            check(true, "flushing a pending edit exposes a successful saved state")
        } else {
            check(false, "flushing a pending edit exposes a successful saved state")
        }
        try? Data("{corrupted".utf8).write(to: file, options: .atomic)
        let second = NotesStore(fileURL: file)
        check(second.didRecoverFromBackup, "a corrupt primary note file recovers from the last valid snapshot")
        let persisted = second.notes.first(where: { $0.id == originalFirstID })
        check(persisted?.title == "持久化测试", "note persistence round trip")
        check(persisted?.body == "正文保持原样\n☐ ", "note body persistence round trip")
        check(persisted?.dueDate == dueDate, "due date persistence round trip")
        check(persisted?.material == .paper, "note material persistence round trip")
        check(persisted?.colorHex == "#FBE693", "gradient start persists")
        check(persisted?.gradientEndHex == "#FE8E28", "gradient end persists")
        check(second.notes.first(where: { $0.id == originalFirstID })?.fontStyle == .serif, "font family persists")
        check(second.notes.first(where: { $0.id == originalFirstID })?.fontSize == 19, "font size persists")

        let failedSaveStore = NotesStore(
            fileURL: folder.appendingPathComponent("save-failure.json"),
            writeData: { _, _ in throw CocoaError(.fileWriteNoPermission) }
        )
        failedSaveStore.updateTitle("Unsaved edit")
        failedSaveStore.flushPendingSave()
        if case .failed = failedSaveStore.saveState {
            check(true, "a write error remains visible as a save failure")
        } else {
            check(false, "a write error remains visible as a save failure")
        }

        second.select(originalFirstID)
        second.archiveActive()
        check(!second.notes.contains(where: { $0.id == originalFirstID }), "archiving removes a note from the edge deck")
        check(second.archivedNotes.contains(where: { $0.id == originalFirstID }), "archiving retains the note in the library")
        let third = NotesStore(fileURL: file)
        check(third.archivedNotes.contains(where: { $0.id == originalFirstID }), "archived notes persist across launches")
        third.restoreArchived(originalFirstID)
        check(third.notes.contains(where: { $0.id == originalFirstID }), "an archived note can be restored")

        print("DockNotes self-checks passed: calendar projection, recurrence, weekly planning, reminders, daily planning, AI configuration, Obsidian backup, ID-scoped editing, deck state, drag preview/order, archive library, fonts, outside-click, overflow, RGB/Hex, localization, tools, persistence")
        fflush(stdout)
        exit(EXIT_SUCCESS)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            let data = Data("Self-check failed: \(message)\n".utf8)
            try? FileHandle.standardError.write(contentsOf: data)
            exit(EXIT_FAILURE)
        }
    }

    private static func descendants<ViewType: NSView>(
        of root: NSView,
        as type: ViewType.Type
    ) -> [ViewType] {
        var matches = root is ViewType ? [root as! ViewType] : []
        for child in root.subviews {
            matches.append(contentsOf: descendants(of: child, as: type))
        }
        return matches
    }

    private static func write<Content: View>(
        renderer: ImageRenderer<Content>,
        to url: URL,
        failureMessage: String
    ) {
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            fputs("\(failureMessage)\n", stderr)
            exit(EXIT_FAILURE)
        }
        do {
            try png.write(to: url, options: .atomic)
            print(url.path)
            fflush(stdout)
            exit(EXIT_SUCCESS)
        } catch {
            fputs("\(failureMessage): \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}

@MainActor
private final class InteractionFormatProbe: ObservableObject {
    @Published var text = "Hello world"
    @Published var rtfData: Data?
    @Published var request: NoteFormatRequest?
}

private struct InteractionFormatProbeView: View {
    @ObservedObject var probe: InteractionFormatProbe

    var body: some View {
        StableTextEditor(
            text: probe.text,
            rtfData: probe.rtfData,
            onChange: { text, data in
                probe.text = text
                probe.rtfData = data
            },
            fontStyle: .system,
            fontSize: 15,
            searchQuery: "",
            searchTopInset: 4,
            formatRequest: Binding(
                get: { probe.request },
                set: { probe.request = $0 }
            ),
            taskInsertRequest: .constant(nil)
        )
    }
}
