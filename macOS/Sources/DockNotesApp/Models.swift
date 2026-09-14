import Foundation

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
        case id, title, body, tasks, colorHex, gradientEndHex, material, isPinned, isArchived, dueDate, fontStyle, fontSize, modifiedAt
    }

    init(id: UUID = UUID(), title: String, body: String = "", tasks: [NoteTask] = [], colorHex: String = NotePalette.gradients[0].startHex, gradientEndHex: String? = NotePalette.gradients[0].endHex, material: NoteMaterial = .plain, isPinned: Bool = false, isArchived: Bool = false, dueDate: Date? = nil, fontStyle: NoteFontStyle = .system, fontSize: Double = 15, modifiedAt: Date = .now) {
        self.id = id
        self.title = title
        self.body = body
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
