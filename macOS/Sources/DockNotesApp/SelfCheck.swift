import Darwin
import AppKit
import Foundation
import SwiftUI

@MainActor
enum SelfCheck {
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
        try? encoder.encode([previewNote]).write(to: file)
        let store = NotesStore(fileURL: file)
        let defaults = UserDefaults(suiteName: "DockNotes.AIPreview.\(UUID().uuidString)")!
        defaults.set("https://api.openai.com/v1", forKey: "docknotes.ai.endpoint")
        defaults.set("gpt-5-mini", forKey: "docknotes.ai.model")
        let settings = AppSettings(defaults: defaults)
        let renderer = ImageRenderer(
            content: NoteCard(
                note: previewNote,
                store: store,
                settings: settings,
                startsInAIMode: true
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
        try? encoder.encode([previewNote]).write(to: file)
        let store = NotesStore(fileURL: file)
        let defaults = UserDefaults(suiteName: "DockNotes.DesktopPreview.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let renderer = ImageRenderer(
            content: DesktopNoteWindowView(noteID: previewNote.id, store: store, settings: settings)
                .frame(width: 700, height: 560)
                .environment(\.colorScheme, .light)
        )
        renderer.proposedSize = ProposedViewSize(width: 700, height: 560)
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

    static func renderDeckPreview(to url: URL, visibleTabCount: Int = DeckLayout.defaultVisibleTabs) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent("notes.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let previewTitles = ["发布前清单", "灵感收集", "会议记录", "学习笔记", "项目资料", "生活灵感", "New note", "旅行计划", "阅读清单", "产品想法", "周末采购"]
        let previewNotes = previewTitles.enumerated().map { index, title in
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
        let defaults = UserDefaults(suiteName: "DockNotes.DesignPreview.\(UUID().uuidString)")!
        defaults.set(AppSettings.clampVisibleTabCount(visibleTabCount), forKey: "docknotes.deck.visibleTabCount")
        let settings = AppSettings(defaults: defaults)
        let previewHeight: CGFloat = visibleTabCount >= 7 ? 900 : 800
        let renderer = ImageRenderer(
            content: DeckWindowView(store: store, settings: settings, availableHeight: previewHeight, isDesignPreview: true)
                .environment(\.colorScheme, .light)
        )
        renderer.proposedSize = ProposedViewSize(width: DeckLayout.windowWidth, height: previewHeight)
        renderer.scale = 2
        write(renderer: renderer, to: url, failureMessage: "Could not render deck preview")
    }

    static func run() {
        check(AppSettings.clamp(0.05) == 0.20, "lower opacity clamp")
        check(AppSettings.clamp(0.64) == 0.64, "middle opacity value")
        check(AppSettings.clamp(1.40) == 1.00, "upper opacity clamp")
        check(AppSettings.clampVisibleTabCount(0) == 1, "visible tab count has a lower bound")
        check(AppSettings.clampVisibleTabCount(8) == 7, "visible tab count has a seven-tab upper bound")

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
        check(NotePresentationPolicy.searchIsOverlay, "in-note search floats above text instead of resizing it")
        check(NotePresentationPolicy.aiKeepsEditorVisible, "opening in-note AI keeps the note body visible")

        let libraryFile = FileManager.default.temporaryDirectory.appendingPathComponent("DockNotes-Library-\(UUID().uuidString).json")
        let libraryStore = NotesStore(fileURL: libraryFile)
        libraryStore.isPreferencesPresented = true
        libraryStore.presentLibrary()
        check(libraryStore.isLibraryPresented, "the in-app library entry presents the library")
        check(!libraryStore.isPreferencesPresented, "opening the library dismisses settings")
        try? FileManager.default.removeItem(at: libraryFile)

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
        check(expandedPlan.slots[1] == nil, "active note reserves its original deck slot")
        check(expandedPlan.slots[2] == layoutNotes[2].id, "opening a note does not shift later tabs")
        check(expandedPlan.overflowIDs.count == 2, "deck reports overflow count from available height")

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
            availableHeight: 900,
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
        check(defaultSlotPlan.overflowIDs == tenNotes.dropFirst(4).map(\.id), "only notes after the configured slots enter More Notes")
        check(DeckLayout.tabWidth == 48, "stacked edge tabs use a slender 48-point paper strip")
        check(DeckLayout.tabVisualHeight > DeckLayout.tabHeight, "paper tabs overlap while preserving the drag pitch")
        let defaultTabPitch = DeckLayout.tabPitch(for: 800, slotCount: 4)
        check(defaultTabPitch > DeckLayout.tabHeight, "four default tabs retain the airy spacing shown in the reference")
        let denseTabPitch = DeckLayout.tabPitch(for: 800, slotCount: 7)
        check(
            EdgeTabLayout.contentTopInset + EdgeTabLayout.titleContentLength <= denseTabPitch,
            "the fixed edge-tab title slot stays inside the minimum visible pitch"
        )
        check(
            DeckLayout.capacity(for: 800, preferredVisibleCount: 7) == 6
                && DeckLayout.capacity(for: 900, preferredVisibleCount: 7) == 7,
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
        check(!first.isExpanded, "an explicit outside click closes even a pinned note")
        first.togglePinned()

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
        let second = NotesStore(fileURL: file)
        let persisted = second.notes.first(where: { $0.id == originalFirstID })
        check(persisted?.title == "持久化测试", "note persistence round trip")
        check(persisted?.body == "正文保持原样\n☐ ", "note body persistence round trip")
        check(persisted?.dueDate == dueDate, "due date persistence round trip")
        check(persisted?.material == .paper, "note material persistence round trip")
        check(persisted?.colorHex == "#FBE693", "gradient start persists")
        check(persisted?.gradientEndHex == "#FE8E28", "gradient end persists")
        check(second.notes.first(where: { $0.id == originalFirstID })?.fontStyle == .serif, "font family persists")
        check(second.notes.first(where: { $0.id == originalFirstID })?.fontSize == 19, "font size persists")

        second.select(originalFirstID)
        second.archiveActive()
        check(!second.notes.contains(where: { $0.id == originalFirstID }), "archiving removes a note from the edge deck")
        check(second.archivedNotes.contains(where: { $0.id == originalFirstID }), "archiving retains the note in the library")
        let third = NotesStore(fileURL: file)
        check(third.archivedNotes.contains(where: { $0.id == originalFirstID }), "archived notes persist across launches")
        third.restoreArchived(originalFirstID)
        check(third.notes.contains(where: { $0.id == originalFirstID }), "an archived note can be restored")

        print("DockNotes self-checks passed: AI configuration, Obsidian backup, ID-scoped editing, deck state, drag preview/order, archive library, fonts, outside-click, overflow, RGB/Hex, localization, tools, persistence")
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
