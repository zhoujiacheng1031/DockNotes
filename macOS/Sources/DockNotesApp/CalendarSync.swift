import AppKit
import Combine
import EventKit
import Foundation

enum CalendarSyncPermissionState: Equatable {
    case notRequested
    case allowed
    case denied
    case restricted
    case unknown
}

struct CalendarSyncCalendar: Identifiable, Equatable {
    let id: String
    let title: String
    let sourceTitle: String
}

struct CalendarTaskReference: Codable, Equatable, Sendable {
    let noteID: UUID
    let taskID: UUID
    let markerUTF16Offset: Int
    let occurrenceIndex: Int?
}

struct CalendarEventDescriptor: Codable, Equatable, Sendable {
    let stableID: String
    let title: String
    let startDate: Date
    let endDate: Date
    let reference: CalendarTaskReference
}

enum CalendarSyncConflictKind: String, Codable, Sendable {
    case modified
    case deleted
}

struct CalendarSyncConflict: Identifiable, Equatable, Sendable {
    var id: String { stableID }
    let stableID: String
    let kind: CalendarSyncConflictKind
    let localTitle: String
    let localStartDate: Date
    let calendarTitle: String?
    let calendarStartDate: Date?
    let reference: CalendarTaskReference
}

struct CalendarSyncLedgerEntry: Codable, Equatable, Sendable {
    let stableID: String
    var eventIdentifier: String
    var calendarIdentifier: String
    var title: String
    var startDate: Date
    var endDate: Date
    let reference: CalendarTaskReference
}

struct CalendarObservedEvent: Equatable, Sendable {
    let eventIdentifier: String
    let stableID: String
    let calendarIdentifier: String
    let title: String
    let startDate: Date
    let endDate: Date
}

enum CalendarSyncDecision: Equatable, Sendable {
    case create
    case update(eventIdentifier: String)
    case conflictModified(eventIdentifier: String)
    case conflictDeleted
}

struct CalendarSyncEvaluation: Equatable, Sendable {
    let decision: CalendarSyncDecision
    let duplicateEventIdentifiers: [String]
}

enum CalendarSyncPolicy {
    private static let markerPrefix = "DOCKNOTES-ID:"

    static func managedNotes(for descriptor: CalendarEventDescriptor) -> String {
        [
            "Managed by DockNotes. Edit carefully; DockNotes remains the task source.",
            "\(markerPrefix)\(descriptor.stableID)",
            "DOCKNOTES-NOTE:\(descriptor.reference.noteID.uuidString.lowercased())",
            "DOCKNOTES-TASK:\(descriptor.reference.taskID.uuidString.lowercased())"
        ].joined(separator: "\n")
    }

    static func stableID(in notes: String?) -> String? {
        notes?.split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix(markerPrefix) })
            .map { String($0.dropFirst(markerPrefix.count)) }
    }

    static func evaluate(
        descriptor: CalendarEventDescriptor,
        ledgerEntry: CalendarSyncLedgerEntry?,
        observedEvents: [CalendarObservedEvent],
        force: Bool
    ) -> CalendarSyncEvaluation {
        let matching = observedEvents
            .filter { $0.stableID == descriptor.stableID }
            .sorted { left, right in
                if left.eventIdentifier == ledgerEntry?.eventIdentifier { return true }
                if right.eventIdentifier == ledgerEntry?.eventIdentifier { return false }
                return left.eventIdentifier < right.eventIdentifier
            }
        guard let primary = matching.first else {
            return CalendarSyncEvaluation(
                decision: ledgerEntry == nil || force ? .create : .conflictDeleted,
                duplicateEventIdentifiers: []
            )
        }
        let duplicates = matching.dropFirst().map(\.eventIdentifier)
        if !force, let ledgerEntry, changed(primary, since: ledgerEntry) {
            return CalendarSyncEvaluation(
                decision: .conflictModified(eventIdentifier: primary.eventIdentifier),
                duplicateEventIdentifiers: duplicates
            )
        }
        return CalendarSyncEvaluation(
            decision: .update(eventIdentifier: primary.eventIdentifier),
            duplicateEventIdentifiers: duplicates
        )
    }

    static func staleStableIDs(
        desiredStableIDs: Set<String>,
        ledger: [String: CalendarSyncLedgerEntry]
    ) -> Set<String> {
        Set(ledger.keys).subtracting(desiredStableIDs)
    }

    private static func changed(
        _ event: CalendarObservedEvent,
        since entry: CalendarSyncLedgerEntry
    ) -> Bool {
        event.title != entry.title
            || abs(event.startDate.timeIntervalSince(entry.startDate)) > 1
            || abs(event.endDate.timeIntervalSince(entry.endDate)) > 1
            || event.calendarIdentifier != entry.calendarIdentifier
    }
}

enum CalendarTaskPlanner {
    static let projectionDays = 7
    static let eventDuration: TimeInterval = 30 * 60

    static func descriptors(
        notes: [DockNote],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [CalendarEventDescriptor] {
        let horizon = calendar.date(byAdding: .day, value: projectionDays, to: now)
            ?? now.addingTimeInterval(Double(projectionDays) * 86_400)
        var result: [CalendarEventDescriptor] = []

        for note in notes where !note.isArchived {
            for item in ChecklistParser.items(in: note) where !item.isCompleted {
                guard let taskID = item.id.taskID,
                      let task = note.tasks.first(where: { $0.id == taskID }) else { continue }
                let reference = CalendarTaskReference(
                    noteID: note.id,
                    taskID: taskID,
                    markerUTF16Offset: item.id.markerUTF16Offset,
                    occurrenceIndex: nil
                )
                if let recurrence = task.recurrence {
                    var projections = recurrence.projections(
                        from: .distantPast,
                        through: horizon,
                        calendar: calendar,
                        limit: 10_000
                    )
                    if !projections.contains(where: {
                        $0.occurrenceIndex == recurrence.currentOccurrenceIndex
                    }),
                       let currentScheduledDate = recurrence.scheduledDate(
                        for: recurrence.currentOccurrenceIndex,
                        calendar: calendar
                       ),
                       let currentDueDate = recurrence.effectiveDate(
                        for: recurrence.currentOccurrenceIndex,
                        calendar: calendar
                       ) {
                        projections.append(TaskOccurrenceProjection(
                            occurrenceIndex: recurrence.currentOccurrenceIndex,
                            scheduledDate: currentScheduledDate,
                            dueDate: currentDueDate
                        ))
                    }
                    projections = projections.filter {
                        $0.occurrenceIndex == recurrence.currentOccurrenceIndex
                            || $0.dueDate >= now
                    }.sorted {
                        $0.dueDate == $1.dueDate
                            ? $0.occurrenceIndex < $1.occurrenceIndex
                            : $0.dueDate < $1.dueDate
                    }
                    for projection in projections {
                        let occurrenceReference = CalendarTaskReference(
                            noteID: reference.noteID,
                            taskID: reference.taskID,
                            markerUTF16Offset: reference.markerUTF16Offset,
                            occurrenceIndex: projection.occurrenceIndex
                        )
                        result.append(descriptor(
                            noteID: note.id,
                            taskID: taskID,
                            title: item.text,
                            startDate: projection.dueDate,
                            occurrenceIndex: projection.occurrenceIndex,
                            reference: occurrenceReference
                        ))
                    }
                } else if let dueDate = task.dueDate ?? item.dueDate {
                    result.append(descriptor(
                        noteID: note.id,
                        taskID: taskID,
                        title: item.text,
                        startDate: dueDate,
                        occurrenceIndex: nil,
                        reference: reference
                    ))
                }
            }
        }
        return result.sorted {
            $0.startDate == $1.startDate ? $0.stableID < $1.stableID : $0.startDate < $1.startDate
        }
    }

    private static func descriptor(
        noteID: UUID,
        taskID: UUID,
        title: String,
        startDate: Date,
        occurrenceIndex: Int?,
        reference: CalendarTaskReference
    ) -> CalendarEventDescriptor {
        var stableID = "docknotes.calendar.task.\(noteID.uuidString.lowercased()).\(taskID.uuidString.lowercased())"
        if let occurrenceIndex { stableID += ".occurrence-\(occurrenceIndex)" }
        return CalendarEventDescriptor(
            stableID: stableID,
            title: title.isEmpty ? "DockNotes Task" : title,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(eventDuration),
            reference: reference
        )
    }
}

@MainActor
final class CalendarSyncCoordinator: ObservableObject {
    @Published private(set) var permissionState: CalendarSyncPermissionState = .unknown
    @Published private(set) var calendars: [CalendarSyncCalendar] = []
    @Published private(set) var synchronizedEventCount = 0
    @Published private(set) var conflicts: [CalendarSyncConflict] = []
    @Published private(set) var statusMessage = ""
    @Published private(set) var isSyncing = false

    private enum SyncMode { case normal, force }
    private static let ledgerKey = "docknotes.calendar.ledger.v1"

    private let store: NotesStore
    private let settings: AppSettings
    private let eventStore: EKEventStore
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var eventStoreObserver: Any?
    private var isApplyingCalendarChange = false

    init(
        store: NotesStore,
        settings: AppSettings,
        eventStore: EKEventStore = EKEventStore(),
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.settings = settings
        self.eventStore = eventStore
        self.defaults = defaults
        refreshPermissionAndCalendars()
    }

    func start() {
        guard cancellables.isEmpty else { return }
        store.$notes
            .dropFirst()
            .debounce(for: .milliseconds(220), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncNow() }
            .store(in: &cancellables)
        settings.$calendarSyncEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.syncNow() } else { self.statusMessage = self.local("日历同步已暂停", "Calendar sync paused") }
            }
            .store(in: &cancellables)
        settings.$calendarIdentifier
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reconcile(mode: .force, clearExistingManagedEvents: false)
            }
            .store(in: &cancellables)
        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isApplyingCalendarChange else { return }
                self.refreshPermissionAndCalendars()
                self.syncNow()
            }
        }
        NotificationCenter.default.publisher(for: Notification.Name.NSSystemTimeZoneDidChange)
            .sink { [weak self] _ in self?.syncNow() }
            .store(in: &cancellables)
        if settings.calendarSyncEnabled { syncNow() }
    }

    func stop() {
        cancellables.removeAll()
        if let eventStoreObserver { NotificationCenter.default.removeObserver(eventStoreObserver) }
        eventStoreObserver = nil
    }

    func refreshPermissionAndCalendars() {
        permissionState = Self.permissionState(for: EKEventStore.authorizationStatus(for: .event))
        guard permissionState == .allowed else {
            calendars = []
            synchronizedEventCount = 0
            return
        }
        calendars = eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { CalendarSyncCalendar(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title) }
            .sorted {
                $0.title == $1.title ? $0.sourceTitle < $1.sourceTitle : $0.title.localizedCompare($1.title) == .orderedAscending
            }
        if let selected = settings.calendarIdentifier,
           !calendars.contains(where: { $0.id == selected }) {
            settings.calendarIdentifier = nil
            statusMessage = local("目标日历不可用，请重新选择", "The target calendar is unavailable. Choose another calendar.")
        }
    }

    func requestPermission() {
        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                self.refreshPermissionAndCalendars()
                if granted {
                    self.statusMessage = self.local("已获得日历权限", "Calendar access granted")
                    if self.settings.calendarIdentifier == nil { self.createDockNotesCalendar() }
                } else {
                    self.settings.calendarSyncEnabled = false
                    self.statusMessage = error?.localizedDescription
                        ?? self.local("未获得日历权限，DockNotes 数据未受影响", "Calendar access was not granted. DockNotes data is unchanged.")
                }
            }
        }
    }

    func openSystemCalendarSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    func createDockNotesCalendar() {
        guard permissionState == .allowed else {
            requestPermission()
            return
        }
        if let existing = eventStore.calendars(for: .event).first(where: {
            $0.title == "DockNotes" && $0.allowsContentModifications
        }) {
            settings.calendarIdentifier = existing.calendarIdentifier
            refreshPermissionAndCalendars()
            syncNow()
            return
        }
        guard let source = eventStore.defaultCalendarForNewEvents?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .local || $0.sourceType == .calDAV }) else {
            statusMessage = local("没有可写的日历账户", "No writable calendar account is available")
            return
        }
        do {
            let calendar = EKCalendar(for: .event, eventStore: eventStore)
            calendar.title = "DockNotes"
            calendar.source = source
            try eventStore.saveCalendar(calendar, commit: true)
            settings.calendarIdentifier = calendar.calendarIdentifier
            refreshPermissionAndCalendars()
            statusMessage = local("已创建 DockNotes 日历", "Created the DockNotes calendar")
            syncNow()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func syncNow() { reconcile(mode: .normal, clearExistingManagedEvents: false) }

    func rebuild() { reconcile(mode: .force, clearExistingManagedEvents: true) }

    func resolveByResyncing(_ conflict: CalendarSyncConflict) {
        conflicts.removeAll { $0.stableID == conflict.stableID }
        reconcile(mode: .force, clearExistingManagedEvents: false, onlyStableID: conflict.stableID)
    }

    func resolveByAdoptingCalendar(_ conflict: CalendarSyncConflict) {
        var ledger = loadLedger()
        switch conflict.kind {
        case .modified:
            if let title = conflict.calendarTitle, !title.isEmpty {
                _ = store.updateChecklistItemText(checklistID(for: conflict.reference), text: title)
            }
            if let date = conflict.calendarStartDate {
                _ = store.setChecklistItemDueDate(checklistID(for: conflict.reference), date: date)
            }
            if var entry = ledger[conflict.stableID] {
                entry.title = conflict.calendarTitle ?? entry.title
                entry.startDate = conflict.calendarStartDate ?? entry.startDate
                entry.endDate = entry.startDate.addingTimeInterval(CalendarTaskPlanner.eventDuration)
                ledger[conflict.stableID] = entry
            }
        case .deleted:
            if conflict.reference.occurrenceIndex == nil {
                _ = store.setChecklistItemDueDate(checklistID(for: conflict.reference), date: nil)
            } else {
                _ = store.skipTaskOccurrence(checklistID(for: conflict.reference))
            }
            ledger.removeValue(forKey: conflict.stableID)
        }
        saveLedger(ledger)
        conflicts.removeAll { $0.stableID == conflict.stableID }
        statusMessage = local("已采用系统日历中的更改", "Adopted the change from Calendar")
    }

    static func permissionState(for status: EKAuthorizationStatus) -> CalendarSyncPermissionState {
        switch status {
        case .notDetermined: .notRequested
        case .restricted: .restricted
        case .denied: .denied
        case .fullAccess, .writeOnly: .allowed
        @unknown default: .unknown
        }
    }

    private func reconcile(
        mode: SyncMode,
        clearExistingManagedEvents: Bool,
        onlyStableID: String? = nil
    ) {
        refreshPermissionAndCalendars()
        guard settings.calendarSyncEnabled else { return }
        guard permissionState == .allowed else {
            statusMessage = local("请先允许访问系统日历", "Allow Calendar access first")
            return
        }
        guard let calendarIdentifier = settings.calendarIdentifier,
              let targetCalendar = eventStore.calendar(withIdentifier: calendarIdentifier),
              targetCalendar.allowsContentModifications else {
            statusMessage = local("请选择可写的目标日历", "Choose a writable target calendar")
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        isApplyingCalendarChange = true
        defer {
            DispatchQueue.main.async { [weak self] in self?.isApplyingCalendarChange = false }
        }

        var desired = Dictionary(uniqueKeysWithValues: CalendarTaskPlanner.descriptors(notes: store.notes).map { ($0.stableID, $0) })
        if let onlyStableID { desired = desired.filter { $0.key == onlyStableID } }
        var ledger = loadLedger()
        let relevantLedger = onlyStableID.map { id in ledger.filter { $0.key == id } } ?? ledger
        let managedEvents = discoverManagedEvents(
            calendar: targetCalendar,
            descriptors: Array(desired.values),
            ledger: Array(relevantLedger.values)
        )
        var eventsByStableID = Dictionary(grouping: managedEvents, by: { markerStableID(in: $0.notes) ?? "" })
        var newConflicts: [CalendarSyncConflict] = []

        do {
            if clearExistingManagedEvents {
                for event in managedEvents { try eventStore.remove(event, span: .thisEvent) }
                for key in relevantLedger.keys { ledger.removeValue(forKey: key) }
                eventsByStableID.removeAll()
            }

            for (stableID, descriptor) in desired {
                let entry = ledger[stableID]
                var candidates = eventsByStableID[stableID] ?? []
                if let eventIdentifier = entry?.eventIdentifier,
                   let event = eventStore.calendarItem(withIdentifier: eventIdentifier) as? EKEvent,
                   markerStableID(in: event.notes) == stableID,
                   !candidates.contains(where: { $0.eventIdentifier == eventIdentifier }) {
                    candidates.append(event)
                }
                let observed = candidates.map(observedEvent)
                let evaluation = CalendarSyncPolicy.evaluate(
                    descriptor: descriptor,
                    ledgerEntry: entry,
                    observedEvents: observed,
                    force: mode == .force
                )
                for duplicateID in evaluation.duplicateEventIdentifiers {
                    if let duplicate = candidates.first(where: { $0.eventIdentifier == duplicateID }) {
                        try eventStore.remove(duplicate, span: .thisEvent)
                    }
                }
                switch evaluation.decision {
                case let .update(eventIdentifier):
                    guard let event = candidates.first(where: { $0.eventIdentifier == eventIdentifier }) else { continue }
                    apply(descriptor, to: event, calendar: targetCalendar)
                    try eventStore.save(event, span: .thisEvent)
                    ledger[stableID] = ledgerEntry(for: descriptor, event: event, calendarIdentifier: calendarIdentifier)
                case let .conflictModified(eventIdentifier):
                    let event = candidates.first(where: { $0.eventIdentifier == eventIdentifier })
                    newConflicts.append(conflict(for: descriptor, event: event, kind: .modified))
                case .conflictDeleted:
                    newConflicts.append(conflict(for: descriptor, event: nil, kind: .deleted))
                case .create:
                    let event = EKEvent(eventStore: eventStore)
                    apply(descriptor, to: event, calendar: targetCalendar)
                    try eventStore.save(event, span: .thisEvent)
                    ledger[stableID] = ledgerEntry(for: descriptor, event: event, calendarIdentifier: calendarIdentifier)
                }
            }

            let staleStableIDs = CalendarSyncPolicy.staleStableIDs(
                desiredStableIDs: Set(desired.keys),
                ledger: relevantLedger
            )
            for stableID in staleStableIDs {
                guard let entry = relevantLedger[stableID] else { continue }
                if let event = managedEvents.first(where: { markerStableID(in: $0.notes) == stableID })
                    ?? (eventStore.calendarItem(withIdentifier: entry.eventIdentifier) as? EKEvent),
                   markerStableID(in: event.notes) == stableID {
                    try eventStore.remove(event, span: .thisEvent)
                }
                ledger.removeValue(forKey: stableID)
            }
            saveLedger(ledger)
            conflicts = mergeConflicts(newConflicts, retainingOutside: onlyStableID)
            synchronizedEventCount = ledger.values.filter { $0.calendarIdentifier == calendarIdentifier }.count
            statusMessage = newConflicts.isEmpty
                ? local("系统日历已同步", "Calendar is up to date")
                : local("发现日历外部更改，请选择处理方式", "Calendar changes need your decision")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func discoverManagedEvents(
        calendar: EKCalendar,
        descriptors: [CalendarEventDescriptor],
        ledger: [CalendarSyncLedgerEntry]
    ) -> [EKEvent] {
        let dates = descriptors.flatMap { [$0.startDate, $0.endDate] }
            + ledger.flatMap { [$0.startDate, $0.endDate] }
        let earliest = dates.min()?.addingTimeInterval(-86_400) ?? Date().addingTimeInterval(-366 * 86_400)
        let latest = dates.max()?.addingTimeInterval(86_400) ?? Date().addingTimeInterval(366 * 86_400)
        guard earliest < latest else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: earliest, end: latest, calendars: [calendar])
        var events = eventStore.events(matching: predicate).filter { markerStableID(in: $0.notes) != nil }
        let knownIDs = Set(events.compactMap(\.eventIdentifier))
        for entry in ledger where !knownIDs.contains(entry.eventIdentifier) {
            guard let event = eventStore.calendarItem(withIdentifier: entry.eventIdentifier) as? EKEvent,
                  event.calendar.calendarIdentifier == calendar.calendarIdentifier,
                  markerStableID(in: event.notes) != nil else { continue }
            events.append(event)
        }
        return events
    }

    private func apply(_ descriptor: CalendarEventDescriptor, to event: EKEvent, calendar: EKCalendar) {
        event.calendar = calendar
        event.title = descriptor.title
        event.startDate = descriptor.startDate
        event.endDate = descriptor.endDate
        event.isAllDay = false
        event.notes = CalendarSyncPolicy.managedNotes(for: descriptor)
    }

    private func markerStableID(in notes: String?) -> String? {
        CalendarSyncPolicy.stableID(in: notes)
    }

    private func observedEvent(_ event: EKEvent) -> CalendarObservedEvent {
        CalendarObservedEvent(
            eventIdentifier: event.eventIdentifier,
            stableID: markerStableID(in: event.notes) ?? "",
            calendarIdentifier: event.calendar.calendarIdentifier,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate
        )
    }

    private func conflict(
        for descriptor: CalendarEventDescriptor,
        event: EKEvent?,
        kind: CalendarSyncConflictKind
    ) -> CalendarSyncConflict {
        CalendarSyncConflict(
            stableID: descriptor.stableID,
            kind: kind,
            localTitle: descriptor.title,
            localStartDate: descriptor.startDate,
            calendarTitle: event?.title,
            calendarStartDate: event?.startDate,
            reference: descriptor.reference
        )
    }

    private func ledgerEntry(
        for descriptor: CalendarEventDescriptor,
        event: EKEvent,
        calendarIdentifier: String
    ) -> CalendarSyncLedgerEntry {
        CalendarSyncLedgerEntry(
            stableID: descriptor.stableID,
            eventIdentifier: event.eventIdentifier,
            calendarIdentifier: calendarIdentifier,
            title: descriptor.title,
            startDate: descriptor.startDate,
            endDate: descriptor.endDate,
            reference: descriptor.reference
        )
    }

    private func mergeConflicts(
        _ newConflicts: [CalendarSyncConflict],
        retainingOutside onlyStableID: String?
    ) -> [CalendarSyncConflict] {
        guard let onlyStableID else { return newConflicts }
        return conflicts.filter { $0.stableID != onlyStableID } + newConflicts
    }

    private func checklistID(for reference: CalendarTaskReference) -> ChecklistItemID {
        ChecklistItemID(
            noteID: reference.noteID,
            markerUTF16Offset: reference.markerUTF16Offset,
            taskID: reference.taskID,
            occurrenceIndex: reference.occurrenceIndex
        )
    }

    private func loadLedger() -> [String: CalendarSyncLedgerEntry] {
        guard let data = defaults.data(forKey: Self.ledgerKey),
              let entries = try? JSONDecoder().decode([CalendarSyncLedgerEntry].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.stableID, $0) })
    }

    private func saveLedger(_ ledger: [String: CalendarSyncLedgerEntry]) {
        if let data = try? JSONEncoder().encode(Array(ledger.values)) {
            defaults.set(data, forKey: Self.ledgerKey)
        }
    }

    private func local(_ chinese: String, _ english: String) -> String {
        switch settings.language {
        case .english: english
        case .simplifiedChinese: chinese
        case .system: Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
        }
    }
}
