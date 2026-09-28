import AppKit
import Foundation

extension Notification.Name {
    static let dockNotesPointerReleased = Notification.Name("DockNotes.pointerReleased")
}

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

enum ReminderTimeInput {
    static func parse(_ input: String, on date: Date, calendar: Calendar = .current) -> Date? {
        var normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "：", with: ":")
            .uppercased()
        if normalized.hasPrefix("上午") {
            normalized = String(normalized.dropFirst(2)).trimmingCharacters(in: .whitespaces) + " AM"
        } else if normalized.hasPrefix("下午") {
            normalized = String(normalized.dropFirst(2)).trimmingCharacters(in: .whitespaces) + " PM"
        }

        let pattern = #"^(\d{1,2})(?::(\d{1,2}))?\s*(AM|PM)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: normalized,
                range: NSRange(location: 0, length: (normalized as NSString).length)
              ),
              match.range.location != NSNotFound else { return nil }

        let source = normalized as NSString
        guard let hour = Int(source.substring(with: match.range(at: 1))) else { return nil }
        let minuteRange = match.range(at: 2)
        let minute = minuteRange.location == NSNotFound ? 0 : Int(source.substring(with: minuteRange)) ?? -1
        guard (0...59).contains(minute) else { return nil }

        let meridiemRange = match.range(at: 3)
        let resolvedHour: Int
        if meridiemRange.location != NSNotFound {
            guard (1...12).contains(hour) else { return nil }
            let meridiem = source.substring(with: meridiemRange)
            resolvedHour = hour % 12 + (meridiem == "PM" ? 12 : 0)
        } else {
            guard (0...23).contains(hour) else { return nil }
            resolvedHour = hour
        }

        return calendar.date(bySettingHour: resolvedHour, minute: minute, second: 0, of: date)
    }

    static func format(_ date: Date, calendar: Calendar = .current) -> String {
        String(
            format: "%02d:%02d",
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )
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

    static func replacingCharacters(
        in range: NSRange,
        with replacement: String,
        body: String,
        rtfData: Data?
    ) -> Data? {
        guard let rtfData,
              let decoded = try? NSAttributedString(
                  data: rtfData,
                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                  documentAttributes: nil
              ),
              decoded.string == body,
              range.location >= 0,
              NSMaxRange(range) <= decoded.length else { return nil }

        let result = NSMutableAttributedString(attributedString: decoded)
        let attributes = range.location < decoded.length
            ? decoded.attributes(at: range.location, effectiveRange: nil)
            : [:]
        result.replaceCharacters(in: range, with: replacement)
        let replacementLength = (replacement as NSString).length
        if replacementLength > 0 {
            result.setAttributes(
                attributes,
                range: NSRange(location: range.location, length: replacementLength)
            )
        }
        return try? result.data(
            from: NSRange(location: 0, length: result.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}

enum TaskRecurrenceFrequency: String, CaseIterable, Codable, Sendable {
    case daily
    case weekdays
    case weekly
    case monthly
}

struct TaskRecurrenceRule: Codable, Equatable, Sendable {
    var frequency: TaskRecurrenceFrequency
    var interval: Int

    init(frequency: TaskRecurrenceFrequency, interval: Int = 1) {
        self.frequency = frequency
        self.interval = min(max(interval, 1), 365)
    }

    private enum CodingKeys: String, CodingKey { case frequency, interval }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try values.decode(TaskRecurrenceFrequency.self, forKey: .frequency)
        interval = min(max(try values.decodeIfPresent(Int.self, forKey: .interval) ?? 1, 1), 365)
    }

    func scheduledDate(
        anchoredAt anchorDate: Date,
        occurrenceIndex: Int,
        calendar: Calendar = .current
    ) -> Date? {
        let safeIndex = max(occurrenceIndex, 0)
        guard safeIndex > 0 else { return anchorDate }
        let distance = interval * safeIndex
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: distance, to: anchorDate)
        case .weekdays:
            var result = anchorDate
            var remaining = distance
            while remaining > 0 {
                guard let next = calendar.date(byAdding: .day, value: 1, to: result) else { return nil }
                result = next
                let weekday = calendar.component(.weekday, from: result)
                if weekday != 1 && weekday != 7 { remaining -= 1 }
            }
            return result
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: distance, to: anchorDate)
        case .monthly:
            return calendar.date(byAdding: .month, value: distance, to: anchorDate)
        }
    }
}

struct TaskOccurrenceOverride: Codable, Equatable, Sendable {
    let occurrenceIndex: Int
    var dueDate: Date?
    var isSkipped: Bool
}

enum TaskOccurrenceOutcome: String, Codable, Sendable {
    case completed
    case skipped
}

struct TaskOccurrenceRecord: Codable, Equatable, Sendable {
    let occurrenceIndex: Int
    let scheduledDate: Date
    let effectiveDueDate: Date
    let recordedAt: Date
    let outcome: TaskOccurrenceOutcome
}

struct TaskOccurrenceProjection: Equatable, Sendable {
    let occurrenceIndex: Int
    let scheduledDate: Date
    let dueDate: Date
}

struct TaskRecurrenceState: Codable, Equatable, Sendable {
    var rule: TaskRecurrenceRule
    var anchorDate: Date
    var currentOccurrenceIndex: Int
    var overrides: [TaskOccurrenceOverride]
    var history: [TaskOccurrenceRecord]

    init(rule: TaskRecurrenceRule, startingAt date: Date) {
        self.rule = rule
        anchorDate = date
        currentOccurrenceIndex = 0
        overrides = []
        history = []
    }

    private enum CodingKeys: String, CodingKey {
        case rule, anchorDate, currentOccurrenceIndex, overrides, history
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        rule = try values.decode(TaskRecurrenceRule.self, forKey: .rule)
        anchorDate = try values.decode(Date.self, forKey: .anchorDate)
        currentOccurrenceIndex = max(
            try values.decodeIfPresent(Int.self, forKey: .currentOccurrenceIndex) ?? 0,
            0
        )
        overrides = try values.decodeIfPresent([TaskOccurrenceOverride].self, forKey: .overrides) ?? []
        history = try values.decodeIfPresent([TaskOccurrenceRecord].self, forKey: .history) ?? []
    }

    func scheduledDate(
        for occurrenceIndex: Int,
        calendar: Calendar = .current
    ) -> Date? {
        rule.scheduledDate(
            anchoredAt: anchorDate,
            occurrenceIndex: occurrenceIndex,
            calendar: calendar
        )
    }

    func occurrenceOverride(for occurrenceIndex: Int) -> TaskOccurrenceOverride? {
        overrides.last { $0.occurrenceIndex == occurrenceIndex }
    }

    func effectiveDate(
        for occurrenceIndex: Int,
        calendar: Calendar = .current
    ) -> Date? {
        if let occurrenceOverride = occurrenceOverride(for: occurrenceIndex) {
            return occurrenceOverride.isSkipped ? nil : occurrenceOverride.dueDate
        }
        return scheduledDate(for: occurrenceIndex, calendar: calendar)
    }

    mutating func setOverride(for occurrenceIndex: Int, dueDate: Date) {
        overrides.removeAll { $0.occurrenceIndex == occurrenceIndex }
        overrides.append(TaskOccurrenceOverride(
            occurrenceIndex: occurrenceIndex,
            dueDate: dueDate,
            isSkipped: false
        ))
    }

    mutating func skip(_ occurrenceIndex: Int) {
        overrides.removeAll { $0.occurrenceIndex == occurrenceIndex }
        overrides.append(TaskOccurrenceOverride(
            occurrenceIndex: occurrenceIndex,
            dueDate: nil,
            isSkipped: true
        ))
    }

    func nextActiveOccurrenceIndex(after occurrenceIndex: Int) -> Int? {
        for candidate in (occurrenceIndex + 1)...(occurrenceIndex + 10_000)
        where occurrenceOverride(for: candidate)?.isSkipped != true {
            return candidate
        }
        return nil
    }

    func projections(
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar = .current,
        limit: Int = 64
    ) -> [TaskOccurrenceProjection] {
        guard startDate < endDate, limit > 0 else { return [] }
        var result: [TaskOccurrenceProjection] = []
        var index = currentOccurrenceIndex
        var examinedAfterHorizon = 0
        while result.count < limit && index < currentOccurrenceIndex + 10_000 {
            guard let scheduledDate = scheduledDate(for: index, calendar: calendar) else { break }
            if scheduledDate >= endDate { examinedAfterHorizon += 1 }
            if examinedAfterHorizon > max(overrides.count + 2, 8) { break }
            if let dueDate = effectiveDate(for: index, calendar: calendar),
               dueDate >= startDate,
               dueDate < endDate {
                result.append(TaskOccurrenceProjection(
                    occurrenceIndex: index,
                    scheduledDate: scheduledDate,
                    dueDate: dueDate
                ))
            }
            index += 1
        }
        return result.sorted {
            $0.dueDate == $1.dueDate
                ? $0.occurrenceIndex < $1.occurrenceIndex
                : $0.dueDate < $1.dueDate
        }
    }
}

struct NoteTask: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var text: String
    var isCompleted: Bool = false
    var dueDate: Date? = nil
    var sourceUTF16Offset: Int? = nil
    var recurrence: TaskRecurrenceState? = nil
}

struct ChecklistItemID: Hashable, Sendable {
    let noteID: DockNote.ID
    let markerUTF16Offset: Int
    let taskID: NoteTask.ID?
    let occurrenceIndex: Int?

    init(
        noteID: DockNote.ID,
        markerUTF16Offset: Int,
        taskID: NoteTask.ID?,
        occurrenceIndex: Int? = nil
    ) {
        self.noteID = noteID
        self.markerUTF16Offset = markerUTF16Offset
        self.taskID = taskID
        self.occurrenceIndex = occurrenceIndex
    }
}

struct ChecklistItem: Identifiable, Equatable, Sendable {
    let id: ChecklistItemID
    let noteID: DockNote.ID
    let noteTitle: String
    let text: String
    let isCompleted: Bool
    let marker: String
    let dueDate: Date?
    let noteModifiedAt: Date
    let recurrenceRule: TaskRecurrenceRule?
    let currentOccurrenceIndex: Int?
    let scheduledOccurrenceDate: Date?
    let isProjectedOccurrence: Bool

    init(
        id: ChecklistItemID,
        noteID: DockNote.ID,
        noteTitle: String,
        text: String,
        isCompleted: Bool,
        marker: String,
        dueDate: Date?,
        noteModifiedAt: Date,
        recurrenceRule: TaskRecurrenceRule? = nil,
        currentOccurrenceIndex: Int? = nil,
        scheduledOccurrenceDate: Date? = nil,
        isProjectedOccurrence: Bool = false
    ) {
        self.id = id
        self.noteID = noteID
        self.noteTitle = noteTitle
        self.text = text
        self.isCompleted = isCompleted
        self.marker = marker
        self.dueDate = dueDate
        self.noteModifiedAt = noteModifiedAt
        self.recurrenceRule = recurrenceRule
        self.currentOccurrenceIndex = currentOccurrenceIndex
        self.scheduledOccurrenceDate = scheduledOccurrenceDate
        self.isProjectedOccurrence = isProjectedOccurrence
    }
}

enum ChecklistParser {
    private struct ParsedMarker {
        let offset: Int
        let marker: String
        let text: String
        let isCompleted: Bool
    }

    private static let uncheckedMarkers: Set<String> = ["☐", "□"]
    private static let completedMarkers: Set<String> = ["☑", "✓"]

    static func items(in note: DockNote) -> [ChecklistItem] {
        let source = note.body as NSString
        guard source.length > 0,
              let expression = try? NSRegularExpression(pattern: "[☐☑□✓]") else { return [] }
        let matches = expression.matches(
            in: note.body,
            range: NSRange(location: 0, length: source.length)
        )
        let parsed = matches.enumerated().map { index, match in
            let marker = source.substring(with: match.range)
            let contentStart = NSMaxRange(match.range)
            let remaining = NSRange(location: contentStart, length: source.length - contentStart)
            let lineBreak = source.range(of: "\n", options: [], range: remaining)
            let nextMarkerLocation = matches.indices.contains(index + 1)
                ? matches[index + 1].range.location
                : source.length
            let lineEnd = lineBreak.location == NSNotFound ? source.length : lineBreak.location
            let contentEnd = min(lineEnd, nextMarkerLocation)
            let rawText = source.substring(
                with: NSRange(location: contentStart, length: max(0, contentEnd - contentStart))
            )
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedMarker(
                offset: match.range.location,
                marker: marker,
                text: text,
                isCompleted: completedMarkers.contains(marker)
            )
        }

        var assignments = Array<NoteTask?>(repeating: nil, count: parsed.count)
        var usedTaskIDs = Set<NoteTask.ID>()
        for index in parsed.indices {
            let item = parsed[index]
            if let metadata = note.tasks.first(where: {
                !usedTaskIDs.contains($0.id)
                    && $0.text == item.text
                    && $0.isCompleted == item.isCompleted
            }) {
                assignments[index] = metadata
                usedTaskIDs.insert(metadata.id)
            }
        }
        for index in parsed.indices where assignments[index] == nil {
            if let metadata = note.tasks.first(where: {
                !usedTaskIDs.contains($0.id) && $0.sourceUTF16Offset == parsed[index].offset
            }) {
                assignments[index] = metadata
                usedTaskIDs.insert(metadata.id)
            }
        }

        return parsed.indices.map { index in
            let item = parsed[index]
            let metadata = assignments[index]
            return ChecklistItem(
                id: ChecklistItemID(
                    noteID: note.id,
                    markerUTF16Offset: item.offset,
                    taskID: metadata?.id,
                    occurrenceIndex: metadata?.recurrence?.currentOccurrenceIndex
                ),
                noteID: note.id,
                noteTitle: note.title,
                text: item.text,
                isCompleted: item.isCompleted,
                marker: item.marker,
                dueDate: metadata == nil ? note.dueDate : metadata?.dueDate,
                noteModifiedAt: note.modifiedAt,
                recurrenceRule: metadata?.recurrence?.rule,
                currentOccurrenceIndex: metadata?.recurrence?.currentOccurrenceIndex,
                scheduledOccurrenceDate: metadata?.recurrence?.scheduledDate(
                    for: metadata?.recurrence?.currentOccurrenceIndex ?? 0
                )
            )
        }
    }

    static func synchronizedTasks(in note: DockNote) -> [NoteTask] {
        items(in: note).map { item in
            if var metadata = item.id.taskID.flatMap({ id in note.tasks.first { $0.id == id } }) {
                metadata.text = item.text
                metadata.isCompleted = item.isCompleted
                metadata.sourceUTF16Offset = item.id.markerUTF16Offset
                return metadata
            }
            return NoteTask(
                text: item.text,
                isCompleted: item.isCompleted,
                sourceUTF16Offset: item.id.markerUTF16Offset
            )
        }
    }

    static func replacementMarker(for marker: String, completed: Bool) -> String {
        if completed { return marker == "□" ? "✓" : "☑" }
        return marker == "✓" ? "□" : "☐"
    }

    static func isChecklistMarker(_ marker: String) -> Bool {
        uncheckedMarkers.contains(marker) || completedMarkers.contains(marker)
    }
}

enum TaskCenterSection: String, CaseIterable, Identifiable, Sendable {
    case inbox
    case today
    case week
    case upcoming
    case overdue
    case completed

    var id: Self { self }
}

struct TaskCenterCounts: Equatable, Sendable {
    let inbox: Int
    let today: Int
    let week: Int
    let upcoming: Int
    let overdue: Int
    let completed: Int

    subscript(section: TaskCenterSection) -> Int {
        switch section {
        case .inbox: inbox
        case .today: today
        case .week: week
        case .upcoming: upcoming
        case .overdue: overdue
        case .completed: completed
        }
    }
}

enum TaskCenterQuery {
    static func allItems(in notes: [DockNote]) -> [ChecklistItem] {
        notes.filter { !$0.isArchived }.flatMap(ChecklistParser.items)
    }

    static func counts(
        in notes: [DockNote],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TaskCenterCounts {
        let items = allItems(in: notes)
        return TaskCenterCounts(
            inbox: items.count { !$0.isCompleted },
            today: items.count { matches($0, section: .today, now: now, calendar: calendar) },
            week: weekItems(in: notes, now: now, calendar: calendar).count,
            upcoming: items.count { matches($0, section: .upcoming, now: now, calendar: calendar) },
            overdue: items.count { matches($0, section: .overdue, now: now, calendar: calendar) },
            completed: items.count { $0.isCompleted }
        )
    }

    static func apply(
        to notes: [DockNote],
        section: TaskCenterSection,
        query: String = "",
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ChecklistItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceItems = section == .week
            ? weekItems(in: notes, now: now, calendar: calendar)
            : allItems(in: notes)
        return sourceItems
            .filter { matches($0, section: section, now: now, calendar: calendar) }
            .filter { item in
                needle.isEmpty
                    || item.text.localizedCaseInsensitiveContains(needle)
                    || item.noteTitle.localizedCaseInsensitiveContains(needle)
            }
            .sorted { left, right in
                switch (left.dueDate, right.dueDate) {
                case let (lhs?, rhs?):
                    if lhs != rhs { return lhs < rhs }
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): break
                }
                if left.noteModifiedAt != right.noteModifiedAt {
                    return left.noteModifiedAt > right.noteModifiedAt
                }
                if left.noteID != right.noteID {
                    return left.noteTitle.localizedCaseInsensitiveCompare(right.noteTitle) == .orderedAscending
                }
                return left.id.markerUTF16Offset < right.id.markerUTF16Offset
            }
    }

    static func weekItems(
        in notes: [DockNote],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ChecklistItem] {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 7, to: start)
            ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        return notes.filter { !$0.isArchived }.flatMap { note in
            ChecklistParser.items(in: note).flatMap { item -> [ChecklistItem] in
                guard !item.isCompleted else { return [] }
                guard let taskID = item.id.taskID,
                      let task = note.tasks.first(where: { $0.id == taskID }),
                      let recurrence = task.recurrence else {
                    guard let dueDate = item.dueDate,
                          dueDate >= start,
                          dueDate < end else { return [] }
                    return [item]
                }
                return recurrence.projections(from: start, through: end, calendar: calendar).map { projection in
                    ChecklistItem(
                        id: ChecklistItemID(
                            noteID: item.noteID,
                            markerUTF16Offset: item.id.markerUTF16Offset,
                            taskID: item.id.taskID,
                            occurrenceIndex: projection.occurrenceIndex
                        ),
                        noteID: item.noteID,
                        noteTitle: item.noteTitle,
                        text: item.text,
                        isCompleted: false,
                        marker: item.marker,
                        dueDate: projection.dueDate,
                        noteModifiedAt: item.noteModifiedAt,
                        recurrenceRule: recurrence.rule,
                        currentOccurrenceIndex: recurrence.currentOccurrenceIndex,
                        scheduledOccurrenceDate: projection.scheduledDate,
                        isProjectedOccurrence: projection.occurrenceIndex != recurrence.currentOccurrenceIndex
                    )
                }
            }
        }
        .sorted {
            if $0.dueDate != $1.dueDate {
                return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
            if $0.noteID != $1.noteID { return $0.noteID.uuidString < $1.noteID.uuidString }
            return ($0.id.occurrenceIndex ?? -1) < ($1.id.occurrenceIndex ?? -1)
        }
    }

    private static func matches(
        _ item: ChecklistItem,
        section: TaskCenterSection,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        switch section {
        case .inbox:
            return !item.isCompleted
        case .today:
            return !item.isCompleted && item.dueDate.map { calendar.isDate($0, inSameDayAs: now) } == true
        case .week:
            return true
        case .upcoming:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            return !item.isCompleted && item.dueDate.map { $0 >= tomorrow } == true
        case .overdue:
            return !item.isCompleted && item.dueDate.map { $0 < calendar.startOfDay(for: now) } == true
        case .completed:
            return item.isCompleted
        }
    }
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

struct NoteWorkspace: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var colorHex: String
    var createdAt: Date = .now
    var lastActiveNoteID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = NotePalette.gradients[3].startHex,
        createdAt: Date = .now,
        lastActiveNoteID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.lastActiveNoteID = lastActiveNoteID
    }
}

struct DockNotesDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var activeWorkspaceID: UUID
    var defaultWorkspaceID: UUID
    var workspaces: [NoteWorkspace]
    var notes: [DockNote]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        activeWorkspaceID: UUID,
        defaultWorkspaceID: UUID,
        workspaces: [NoteWorkspace],
        notes: [DockNote]
    ) {
        self.schemaVersion = schemaVersion
        self.activeWorkspaceID = activeWorkspaceID
        self.defaultWorkspaceID = defaultWorkspaceID
        self.workspaces = workspaces
        self.notes = notes
    }
}

struct DockNote: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var body: String = ""
    /// RTF is stored alongside `body`: AppKit renders the rich text while
    /// search, AI, and Markdown export continue to use the portable plain text.
    var bodyRTF: Data?
    var tasks: [NoteTask] = []
    var workspaceID: UUID?
    var colorHex: String = "#F4D36F"
    var gradientEndHex: String?
    var material: NoteMaterial = .plain
    var isPinned: Bool = false
    var isArchived: Bool = false
    var dueDate: Date?
    var fontStyle: NoteFontStyle = .system
    var fontSize: Double = 15
    var modifiedAt: Date = .now
    var createdAt: Date = .now

    private enum CodingKeys: String, CodingKey {
        case id, title, body, bodyRTF, tasks, workspaceID, colorHex, gradientEndHex, material, isPinned, isArchived, dueDate, fontStyle, fontSize, modifiedAt, createdAt
    }

    init(id: UUID = UUID(), title: String, body: String = "", bodyRTF: Data? = nil, tasks: [NoteTask] = [], workspaceID: UUID? = nil, colorHex: String = NotePalette.gradients[0].startHex, gradientEndHex: String? = NotePalette.gradients[0].endHex, material: NoteMaterial = .plain, isPinned: Bool = false, isArchived: Bool = false, dueDate: Date? = nil, fontStyle: NoteFontStyle = .system, fontSize: Double = 15, modifiedAt: Date = .now, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.body = body
        self.bodyRTF = bodyRTF
        self.tasks = tasks
        self.workspaceID = workspaceID
        self.colorHex = colorHex
        self.gradientEndHex = gradientEndHex
        self.material = material
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.dueDate = dueDate
        self.fontStyle = fontStyle
        self.fontSize = fontSize
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        tasks = try values.decodeIfPresent([NoteTask].self, forKey: .tasks) ?? []
        workspaceID = try values.decodeIfPresent(UUID.self, forKey: .workspaceID)
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
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? modifiedAt
    }

    static let samples: [DockNote] = [
        DockNote(title: "发布前清单", body: "检查中英文文案\nExport Markdown\n确认离线可编辑", colorHex: NotePalette.gradients[0].startHex, gradientEndHex: NotePalette.gradients[0].endHex),
        DockNote(title: "灵感收集", body: "记录一闪而过的想法。", colorHex: NotePalette.gradients[1].startHex, gradientEndHex: NotePalette.gradients[1].endHex),
        DockNote(title: "会议记录", body: "议题、决定与下一步。", colorHex: NotePalette.gradients[2].startHex, gradientEndHex: NotePalette.gradients[2].endHex),
        DockNote(title: "学习笔记", body: "今天学到的新知识。", colorHex: NotePalette.gradients[3].startHex, gradientEndHex: NotePalette.gradients[3].endHex)
    ]
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case pinned
    case incomplete
    case overdue

    var id: Self { self }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case modified
    case due
    case created

    var id: Self { self }
}

enum LibraryQuery {
    static func apply(
        to notes: [DockNote],
        query: String,
        filter: LibraryFilter,
        sort: LibrarySort,
        now: Date = .now
    ) -> [DockNote] {
        let searched = NoteSearchEngine.rankedNotes(notes, query: query)
        let filtered = searched.filter { note in
            switch filter {
            case .all:
                true
            case .pinned:
                note.isPinned
            case .incomplete:
                note.tasks.contains(where: { !$0.isCompleted })
                    || note.body.split(separator: "\n", omittingEmptySubsequences: false)
                        .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("☐") }
            case .overdue:
                note.dueDate.map { $0 < now } == true
            }
        }
        return filtered.sorted { left, right in
            switch sort {
            case .modified:
                left.modifiedAt > right.modifiedAt
            case .due:
                switch (left.dueDate, right.dueDate) {
                case let (lhs?, rhs?): lhs == rhs ? left.modifiedAt > right.modifiedAt : lhs < rhs
                case (.some, .none): true
                case (.none, .some): false
                case (.none, .none): left.modifiedAt > right.modifiedAt
                }
            case .created:
                left.createdAt > right.createdAt
            }
        }
    }
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

enum DeckEvent: Equatable, Sendable {
    case pointerEntered
    case noteSelected(UUID)
    case noteMovedToDesktop
    case noteReturnedFromDesktop(UUID)
    case collapsed
    case dismissed
    case automaticRest
    case outsideClick(keepOpen: Bool, activeNotePinned: Bool)
}

/// Pure transition policy for the edge deck. Keeping the policy free of view
/// and timer side effects makes every input path obey the same state rules.
enum DeckTransition {
    static func reduce(_ state: DeckState, event: DeckEvent) -> DeckState {
        switch event {
        case .pointerEntered:
            return state == .resting ? .fanned : state
        case let .noteSelected(id), let .noteReturnedFromDesktop(id):
            return .noteOpen(id)
        case .noteMovedToDesktop, .collapsed:
            return .fanned
        case .dismissed:
            return .resting
        case .automaticRest:
            return state == .fanned ? .resting : state
        case let .outsideClick(keepOpen, activeNotePinned):
            switch state {
            case .noteOpen where activeNotePinned:
                return state
            case .noteOpen:
                return keepOpen ? .fanned : .resting
            case .fanned:
                return keepOpen ? .fanned : .resting
            case .resting:
                return .resting
            }
        }
    }
}

enum NoteSaveState: Equatable {
    case saving
    case saved(Date)
    case failed(String)
}

enum NoteCollection: Equatable, Sendable {
    case active
    case archived
}

struct PendingDeletion: Identifiable, Equatable {
    let id: UUID
    let note: DockNote
    let collection: NoteCollection
    let originalIndex: Int
    let wasActive: Bool
    let wasOnDesktop: Bool
    let previousDeckState: DeckState
    let expiresAt: Date
}

struct PendingWorkspaceDeletion: Identifiable, Equatable {
    let id: UUID
    let workspace: NoteWorkspace
    let originalIndex: Int
    let activeNoteIDs: [DockNote.ID]
    let archivedNoteIDs: [DockNote.ID]
    let wasActive: Bool
    let expiresAt: Date
}
