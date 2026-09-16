import AppKit
import Foundation

enum DeadlineStatus: Equatable {
    case upcoming
    case today
    case overdue
}

struct DeadlinePresentation: Equatable {
    let status: DeadlineStatus
    let edgeLabel: String
    let toolbarLabel: String

    static func make(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        language: AppLanguage
    ) -> DeadlinePresentation {
        let status: DeadlineStatus
        if date < now {
            status = .overdue
        } else if calendar.isDate(date, inSameDayAs: now) {
            status = .today
        } else {
            status = .upcoming
        }
        let time = formatted(date, template: "HH:mm", calendar: calendar)
        let shortDate = formatted(date, template: "M/d", calendar: calendar)
        let dateTime = formatted(date, template: "M/d HH:mm", calendar: calendar)
        switch status {
        case .today:
            return DeadlinePresentation(
                status: status,
                edgeLabel: time,
                toolbarLabel: "\(L10n.text(.today, language: language)) \(time)"
            )
        case .overdue:
            return DeadlinePresentation(
                status: status,
                edgeLabel: "!\(shortDate)",
                toolbarLabel: "\(L10n.text(.overdue, language: language)) · \(dateTime)"
            )
        case .upcoming:
            return DeadlinePresentation(status: status, edgeLabel: shortDate, toolbarLabel: dateTime)
        }
    }

    private static func formatted(_ date: Date, template: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

enum NoteContentRegion: Hashable {
    case editor
    case searchOverlay
    case aiDrawer
}

enum NotePresentationPolicy {
    static func regions(searchVisible: Bool, aiVisible: Bool) -> Set<NoteContentRegion> {
        var regions: Set<NoteContentRegion> = [.editor]
        if searchVisible { regions.insert(.searchOverlay) }
        if aiVisible { regions.insert(.aiDrawer) }
        return regions
    }

    static let searchIsOverlay = regions(searchVisible: true, aiVisible: false).contains(.searchOverlay)
    static let aiKeepsEditorVisible = regions(searchVisible: false, aiVisible: true).contains(.editor)
}

enum NoteSearchEngine {
    static func matchRanges(in text: String, query: String) -> [NSRange] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let source = text as NSString
        var ranges: [NSRange] = []
        var remaining = NSRange(location: 0, length: source.length)
        while remaining.length > 0 {
            let range = source.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: remaining
            )
            guard range.location != NSNotFound else { break }
            ranges.append(range)
            let nextLocation = NSMaxRange(range)
            remaining = NSRange(location: nextLocation, length: source.length - nextLocation)
        }
        return ranges
    }

    static func rankedNotes(_ notes: [DockNote], query: String) -> [DockNote] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return notes }
        return notes.compactMap { note -> (rank: Int, note: DockNote)? in
            if !matchRanges(in: note.title, query: needle).isEmpty { return (0, note) }
            if !matchRanges(in: note.body, query: needle).isEmpty { return (1, note) }
            return nil
        }
        .sorted { left, right in
            if left.rank != right.rank { return left.rank < right.rank }
            let titleOrder = left.note.title.localizedCaseInsensitiveCompare(right.note.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return left.note.modifiedAt > right.note.modifiedAt
        }
        .map(\.note)
    }

    static func matchesTitle(_ note: DockNote, query: String) -> Bool {
        !matchRanges(in: note.title, query: query).isEmpty
    }
}

enum RichTextBody {
    static func appendingPlainText(_ suffix: String, to body: String, rtfData: Data?) -> Data? {
        guard let rtfData,
              let decoded = try? NSAttributedString(
                  data: rtfData,
                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                  documentAttributes: nil
              ),
              decoded.string == body else { return nil }

        let result = NSMutableAttributedString(attributedString: decoded)
        var baseAttributes: [NSAttributedString.Key: Any] = [:]
        if decoded.length > 0 {
            let previous = decoded.attributes(at: decoded.length - 1, effectiveRange: nil)
            if let font = previous[.font] as? NSFont {
                baseAttributes[.font] = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
            }
            if let color = previous[.foregroundColor] as? NSColor {
                baseAttributes[.foregroundColor] = color
            }
        }
        result.append(NSAttributedString(string: suffix, attributes: baseAttributes))
        return try? result.data(
            from: NSRange(location: 0, length: result.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}

struct NoteTask: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var text: String
    var isCompleted: Bool = false
}

enum NoteMaterial: String, CaseIterable, Codable, Sendable {
    case plain
    case paper
}

enum NoteFontStyle: String, CaseIterable, Codable, Sendable {
    case system
    case rounded
    case serif
    case monospaced
    case handwriting
}

enum NotePalette {
    static let gradients = [
        NoteGradient(startHex: "#F4DC84", endHex: "#79BEDF"),
        NoteGradient(startHex: "#C9DDC4", endHex: "#1F5CAC"),
        NoteGradient(startHex: "#FBE693", endHex: "#FE8E28"),
        NoteGradient(startHex: "#B8A9C6", endHex: "#2B693F"),
        NoteGradient(startHex: "#E4F6AA", endHex: "#FF81A6"),
        NoteGradient(startHex: "#80E484", endHex: "#2B693F")
    ]
    static let colors = gradients.map(\.startHex)

    private static let legacy: [String: String] = [
        "#F3CB4C": "#F4D36F",
        "#F3A13B": "#F1A06D",
        "#F59BA6": "#F2B3C2",
        "#8768E8": "#B7A7DE",
        "#4CA9DD": "#8DBDE0",
        "#31B99A": "#8FD1BA",
        "#B79558": "#C5AA72",
        "#657583": "#7D8C94"
    ]

    static func migrated(_ hex: String) -> String {
        legacy[hex.uppercased()] ?? hex
    }
}

struct NoteGradient: Hashable, Sendable {
    let startHex: String
    let endHex: String
}

struct DockNote: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var body: String = ""
    /// RTF is stored alongside `body`: AppKit renders the rich text while
    /// search, AI, and Markdown export continue to use the portable plain text.
    var bodyRTF: Data?
    var tasks: [NoteTask] = []
    var colorHex: String = "#F4D36F"
    var gradientEndHex: String?
    var material: NoteMaterial = .plain
    var isPinned: Bool = false
    var isArchived: Bool = false
    var dueDate: Date?
    var fontStyle: NoteFontStyle = .system
    var fontSize: Double = 15
    var modifiedAt: Date = .now

    private enum CodingKeys: String, CodingKey {
        case id, title, body, bodyRTF, tasks, colorHex, gradientEndHex, material, isPinned, isArchived, dueDate, fontStyle, fontSize, modifiedAt
    }

    init(id: UUID = UUID(), title: String, body: String = "", bodyRTF: Data? = nil, tasks: [NoteTask] = [], colorHex: String = NotePalette.gradients[0].startHex, gradientEndHex: String? = NotePalette.gradients[0].endHex, material: NoteMaterial = .plain, isPinned: Bool = false, isArchived: Bool = false, dueDate: Date? = nil, fontStyle: NoteFontStyle = .system, fontSize: Double = 15, modifiedAt: Date = .now) {
        self.id = id
        self.title = title
        self.body = body
        self.bodyRTF = bodyRTF
        self.tasks = tasks
        self.colorHex = colorHex
        self.gradientEndHex = gradientEndHex
        self.material = material
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.dueDate = dueDate
        self.fontStyle = fontStyle
        self.fontSize = fontSize
        self.modifiedAt = modifiedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        tasks = try values.decodeIfPresent([NoteTask].self, forKey: .tasks) ?? []
        body = try values.decodeIfPresent(String.self, forKey: .body)
            ?? tasks.map { ($0.isCompleted ? "✓ " : "□ ") + $0.text }.joined(separator: "\n")
        bodyRTF = try values.decodeIfPresent(Data.self, forKey: .bodyRTF)
        colorHex = try values.decodeIfPresent(String.self, forKey: .colorHex) ?? "#F4D36F"
        gradientEndHex = try values.decodeIfPresent(String.self, forKey: .gradientEndHex)
        material = try values.decodeIfPresent(NoteMaterial.self, forKey: .material) ?? .plain
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try values.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        dueDate = try values.decodeIfPresent(Date.self, forKey: .dueDate)
        fontStyle = try values.decodeIfPresent(NoteFontStyle.self, forKey: .fontStyle) ?? .system
        fontSize = min(max(try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? 15, 11), 28)
        modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .now
    }

    static let samples: [DockNote] = [
        DockNote(title: "发布前清单", body: "检查中英文文案\nExport Markdown\n确认离线可编辑", colorHex: NotePalette.gradients[0].startHex, gradientEndHex: NotePalette.gradients[0].endHex),
        DockNote(title: "灵感收集", body: "记录一闪而过的想法。", colorHex: NotePalette.gradients[1].startHex, gradientEndHex: NotePalette.gradients[1].endHex),
        DockNote(title: "会议记录", body: "议题、决定与下一步。", colorHex: NotePalette.gradients[2].startHex, gradientEndHex: NotePalette.gradients[2].endHex),
        DockNote(title: "学习笔记", body: "今天学到的新知识。", colorHex: NotePalette.gradients[3].startHex, gradientEndHex: NotePalette.gradients[3].endHex)
    ]
}

enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case simplifiedChinese
    case english
}

enum DeckState: Equatable, Sendable {
    case resting
    case fanned
    case noteOpen(UUID)

    var openNoteID: UUID? {
        guard case let .noteOpen(id) = self else { return nil }
        return id
    }

    var showsTabs: Bool { self != .resting }
}
