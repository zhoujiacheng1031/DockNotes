import AppKit
import Combine
import Foundation
import UserNotifications

enum NotificationPermissionState: Equatable, Sendable {
    case unknown
    case notRequested
    case allowed
    case denied

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notRequested
        case .denied: self = .denied
        case .authorized, .provisional, .ephemeral: self = .allowed
        @unknown default: self = .unknown
        }
    }
}

enum ReminderNotificationAction {
    static let taskCategory = "docknotes.category.task"
    static let noteCategory = "docknotes.category.note"
    static let summaryCategory = "docknotes.category.daily-summary"
    static let complete = "docknotes.action.complete"
    static let snooze = "docknotes.action.snooze"
    static let open = "docknotes.action.open"
    static let openTaskCenter = "docknotes.action.open-task-center"
}

struct ReminderTaskReference: Equatable, Sendable {
    let noteID: DockNote.ID
    let taskID: NoteTask.ID?
    let markerUTF16Offset: Int
    let occurrenceIndex: Int?

    init(item: ChecklistItem) {
        noteID = item.noteID
        taskID = item.id.taskID
        markerUTF16Offset = item.id.markerUTF16Offset
        occurrenceIndex = item.id.occurrenceIndex
    }

    init?(userInfo: [String: String]) {
        guard let noteIDString = userInfo["noteID"],
              let noteID = UUID(uuidString: noteIDString),
              let markerUTF16Offset = Self.intValue(userInfo["markerUTF16Offset"]) else { return nil }
        self.noteID = noteID
        taskID = userInfo["taskID"].flatMap(UUID.init(uuidString:))
        self.markerUTF16Offset = markerUTF16Offset
        occurrenceIndex = userInfo["occurrenceIndex"].flatMap(Int.init)
    }

    var userInfo: [String: String] {
        var value = [
            "kind": "task",
            "noteID": noteID.uuidString,
            "markerUTF16Offset": String(markerUTF16Offset)
        ]
        if let taskID { value["taskID"] = taskID.uuidString }
        if let occurrenceIndex { value["occurrenceIndex"] = String(occurrenceIndex) }
        return value
    }

    private static func intValue(_ value: String?) -> Int? {
        value.flatMap(Int.init)
    }
}

struct ReminderRequestDescriptor: Equatable, Sendable {
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String
    let categoryIdentifier: String
    let userInfo: [String: String]
}

enum ReminderResponseCommand: Equatable, Sendable {
    case complete(ReminderTaskReference)
    case snooze(ReminderTaskReference, until: Date)
    case openNote(DockNote.ID)
    case openTaskCenter
    case none
}

enum ReminderResponseRouter {
    static func command(
        actionIdentifier: String,
        userInfo: [String: String],
        now: Date = .now,
        snoozeInterval: TimeInterval = 15 * 60
    ) -> ReminderResponseCommand {
        if userInfo["kind"] == "daily-summary" {
            return actionIdentifier == UNNotificationDismissActionIdentifier ? .none : .openTaskCenter
        }
        if let task = ReminderTaskReference(userInfo: userInfo) {
            switch actionIdentifier {
            case ReminderNotificationAction.complete:
                return .complete(task)
            case ReminderNotificationAction.snooze:
                return .snooze(task, until: now.addingTimeInterval(snoozeInterval))
            case UNNotificationDismissActionIdentifier:
                return .none
            default:
                return .openNote(task.noteID)
            }
        }
        guard let noteIDString = userInfo["noteID"],
              let noteID = UUID(uuidString: noteIDString) else { return .none }
        return actionIdentifier == UNNotificationDismissActionIdentifier ? .none : .openNote(noteID)
    }
}

enum ReminderPlanner {
    static let managedPrefix = "docknotes."
    static let maximumPendingRequests = 60
    static let summaryHorizonDays = 7

    static func noteIdentifier(for noteID: DockNote.ID) -> String {
        "docknotes.deadline.\(noteID.uuidString.lowercased())"
    }

    static func taskIdentifier(for reference: ReminderTaskReference) -> String {
        let stableTaskPart = reference.taskID?.uuidString.lowercased()
            ?? "offset-\(reference.markerUTF16Offset)"
        let occurrencePart = reference.occurrenceIndex.map { ".occurrence-\($0)" } ?? ""
        return "docknotes.task.\(reference.noteID.uuidString.lowercased()).\(stableTaskPart)\(occurrencePart)"
    }

    static func dailySummaryIdentifier(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "docknotes.daily-summary.\(formatter.string(from: date))"
    }

    static func makePlan(
        notes: [DockNote],
        taskRemindersEnabled: Bool,
        dailySummaryEnabled: Bool,
        dailySummaryMinutes: Int,
        now: Date = .now,
        calendar: Calendar = .current,
        language: AppLanguage = .system
    ) -> [ReminderRequestDescriptor] {
        var deadlineRequests: [ReminderRequestDescriptor] = []
        if taskRemindersEnabled {
            for note in notes where !note.isArchived {
                if let dueDate = note.dueDate, dueDate > now {
                    deadlineRequests.append(ReminderRequestDescriptor(
                        identifier: noteIdentifier(for: note.id),
                        fireDate: dueDate,
                        title: note.title.isEmpty ? "DockNotes" : note.title,
                        body: L10n.text(.deadlineReached, language: language),
                        categoryIdentifier: ReminderNotificationAction.noteCategory,
                        userInfo: ["kind": "note", "noteID": note.id.uuidString]
                    ))
                }
                for item in ChecklistParser.items(in: note)
                where !item.isCompleted && item.dueDate.map({ $0 > now }) == true {
                    guard let dueDate = item.dueDate else { continue }
                    let reference = ReminderTaskReference(item: item)
                    deadlineRequests.append(ReminderRequestDescriptor(
                        identifier: taskIdentifier(for: reference),
                        fireDate: dueDate,
                        title: note.title.isEmpty ? "DockNotes" : note.title,
                        body: String(
                            format: L10n.text(.taskReminderBody, language: language),
                            item.text.isEmpty ? L10n.text(.task, language: language) : item.text
                        ),
                        categoryIdentifier: ReminderNotificationAction.taskCategory,
                        userInfo: reference.userInfo
                    ))
                }
            }
        }

        let summaryRequests = dailySummaryEnabled
            ? dailySummaryRequests(
                notes: notes,
                minutes: dailySummaryMinutes,
                now: now,
                calendar: calendar,
                language: language
            )
            : []
        let availableDeadlineSlots = max(0, maximumPendingRequests - summaryRequests.count)
        let earliestDeadlines = deadlineRequests
            .sorted { $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate }
            .prefix(availableDeadlineSlots)
        return (Array(earliestDeadlines) + summaryRequests).sorted {
            $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate
        }
    }

    static func activeEntityIdentifiers(in notes: [DockNote]) -> Set<String> {
        var identifiers = Set<String>()
        for note in notes where !note.isArchived {
            if note.dueDate != nil {
                identifiers.insert(noteIdentifier(for: note.id))
            }
            for item in ChecklistParser.items(in: note) where !item.isCompleted && item.dueDate != nil {
                identifiers.insert(taskIdentifier(for: ReminderTaskReference(item: item)))
            }
        }
        return identifiers
    }

    private static func dailySummaryRequests(
        notes: [DockNote],
        minutes: Int,
        now: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> [ReminderRequestDescriptor] {
        let clampedMinutes = min(max(minutes, 0), 23 * 60 + 59)
        let hour = clampedMinutes / 60
        let minute = clampedMinutes % 60
        let start = calendar.startOfDay(for: now)
        return (0..<summaryHorizonDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let fireDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fireDate > now else { return nil }
            let todayCount = TaskCenterQuery.apply(
                to: notes,
                section: .today,
                now: fireDate,
                calendar: calendar
            ).count
            let overdueCount = TaskCenterQuery.apply(
                to: notes,
                section: .overdue,
                now: fireDate,
                calendar: calendar
            ).count
            guard todayCount + overdueCount > 0 else { return nil }
            return ReminderRequestDescriptor(
                identifier: dailySummaryIdentifier(for: day, calendar: calendar),
                fireDate: fireDate,
                title: L10n.text(.dailySummaryTitle, language: language),
                body: String(
                    format: L10n.text(.dailySummaryBody, language: language),
                    todayCount,
                    overdueCount
                ),
                categoryIdentifier: ReminderNotificationAction.summaryCategory,
                userInfo: ["kind": "daily-summary"]
            )
        }
    }
}

/// Retained as a small compatibility surface for the note deadline identifier.
enum DueReminderScheduler {
    static func identifier(for noteID: DockNote.ID) -> String {
        ReminderPlanner.noteIdentifier(for: noteID)
    }
}

enum ReminderSystemBridge {
    static func categories(language: AppLanguage) -> Set<UNNotificationCategory> {
        let complete = UNNotificationAction(
            identifier: ReminderNotificationAction.complete,
            title: L10n.text(.markTaskComplete, language: language),
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: ReminderNotificationAction.snooze,
            title: L10n.text(.snoozeFifteenMinutes, language: language),
            options: []
        )
        let open = UNNotificationAction(
            identifier: ReminderNotificationAction.open,
            title: L10n.text(.openNote, language: language),
            options: [.foreground]
        )
        let openTaskCenter = UNNotificationAction(
            identifier: ReminderNotificationAction.openTaskCenter,
            title: L10n.text(.openTaskCenter, language: language),
            options: [.foreground]
        )
        return [
            UNNotificationCategory(
                identifier: ReminderNotificationAction.taskCategory,
                actions: [complete, snooze, open],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: ReminderNotificationAction.noteCategory,
                actions: [open],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: ReminderNotificationAction.summaryCategory,
                actions: [openTaskCenter],
                intentIdentifiers: [],
                options: []
            )
        ]
    }

    static func request(
        for descriptor: ReminderRequestDescriptor,
        calendar: Calendar = .current
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = descriptor.title
        content.body = descriptor.body
        content.sound = .default
        content.categoryIdentifier = descriptor.categoryIdentifier
        content.userInfo = descriptor.userInfo
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: descriptor.fireDate
        )
        return UNNotificationRequest(
            identifier: descriptor.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }
}

@MainActor
final class ReminderCoordinator: ObservableObject {
    @Published private(set) var permissionState: NotificationPermissionState = .unknown
    @Published private(set) var scheduledRequestCount = 0

    private let store: NotesStore
    private let settings: AppSettings
    private let center: UNUserNotificationCenter
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var syncTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private var syncRevision: UInt64 = 0
    private var pendingAuthorizationRequest = false
    private var pendingForcedAuthorizationRequest = false
    private var started = false

    init(
        store: NotesStore,
        settings: AppSettings,
        center: UNUserNotificationCenter = .current()
    ) {
        self.store = store
        self.settings = settings
        self.center = center
    }

    func start() {
        guard !started else { return }
        started = true
        registerCategories()
        observeChanges()
        startMaintenanceLoop()
        syncNow(requestAuthorizationIfNeeded: true)
    }

    func stop() {
        syncTask?.cancel()
        syncTask = nil
        maintenanceTask?.cancel()
        maintenanceTask = nil
        cancellables.removeAll()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        started = false
    }

    func requestPermission() {
        pendingForcedAuthorizationRequest = true
        enqueueSync()
    }

    func syncNow(requestAuthorizationIfNeeded: Bool = false) {
        pendingAuthorizationRequest = pendingAuthorizationRequest || requestAuthorizationIfNeeded
        enqueueSync()
    }

    private func enqueueSync() {
        syncRevision &+= 1
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            guard let self else { return }
            await drainSyncQueue()
        }
    }

    private func drainSyncQueue() async {
        while !Task.isCancelled {
            let revision = syncRevision
            let requestAuthorization = pendingAuthorizationRequest
            let forceAuthorization = pendingForcedAuthorizationRequest
            pendingAuthorizationRequest = false
            pendingForcedAuthorizationRequest = false
            await synchronize(
                requestAuthorizationIfNeeded: requestAuthorization,
                forceAuthorizationRequest: forceAuthorization
            )
            if revision == syncRevision {
                syncTask = nil
                return
            }
        }
        syncTask = nil
    }

    func handle(actionIdentifier: String, userInfo: [String: String], now: Date = .now) {
        let command = ReminderResponseRouter.command(
            actionIdentifier: actionIdentifier,
            userInfo: userInfo,
            now: now
        )
        switch command {
        case let .complete(reference):
            guard let itemID = resolve(reference) else { return }
            _ = store.setChecklistItemCompleted(itemID, completed: true)
            store.flushPendingSave()
        case let .snooze(reference, until):
            guard let itemID = resolve(reference) else { return }
            _ = store.setChecklistItemDueDate(itemID, date: until)
            store.flushPendingSave()
        case let .openNote(noteID):
            store.openFromTaskCenter(noteID)
            NSApp.activate(ignoringOtherApps: true)
        case .openTaskCenter:
            store.presentTaskCenter()
            NSApp.activate(ignoringOtherApps: true)
        case .none:
            break
        }
        syncNow()
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func resolve(_ reference: ReminderTaskReference) -> ChecklistItemID? {
        guard let note = store.note(id: reference.noteID) else { return nil }
        let items = ChecklistParser.items(in: note)
        if let taskID = reference.taskID,
           let item = items.first(where: { $0.id.taskID == taskID }) {
            if let occurrenceIndex = reference.occurrenceIndex,
               item.id.occurrenceIndex != occurrenceIndex { return nil }
            return item.id
        }
        guard let item = items.first(where: {
            $0.id.markerUTF16Offset == reference.markerUTF16Offset
        }) else { return nil }
        if let occurrenceIndex = reference.occurrenceIndex,
           item.id.occurrenceIndex != occurrenceIndex { return nil }
        return item.id
    }

    private func observeChanges() {
        store.$notes.dropFirst().sink { [weak self] _ in self?.syncNow() }.store(in: &cancellables)
        settings.$taskRemindersEnabled.dropFirst().sink { [weak self] _ in
            self?.syncNow(requestAuthorizationIfNeeded: true)
        }.store(in: &cancellables)
        settings.$dailySummaryEnabled.dropFirst().sink { [weak self] _ in
            self?.syncNow(requestAuthorizationIfNeeded: true)
        }.store(in: &cancellables)
        settings.$dailySummaryMinutes.dropFirst().sink { [weak self] _ in self?.syncNow() }.store(in: &cancellables)
        settings.$language.dropFirst().sink { [weak self] _ in
            self?.registerCategories()
            self?.syncNow()
        }.store(in: &cancellables)

        observers.append(NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        })
    }

    private func startMaintenanceLoop() {
        maintenanceTask?.cancel()
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(21_600))
                guard !Task.isCancelled, let self else { return }
                self.syncNow()
            }
        }
    }

    private func registerCategories() {
        center.setNotificationCategories(ReminderSystemBridge.categories(language: settings.language))
    }

    private func synchronize(
        requestAuthorizationIfNeeded: Bool,
        forceAuthorizationRequest: Bool
    ) async {
        let plan = ReminderPlanner.makePlan(
            notes: store.notes,
            taskRemindersEnabled: settings.taskRemindersEnabled,
            dailySummaryEnabled: settings.dailySummaryEnabled,
            dailySummaryMinutes: settings.dailySummaryMinutes,
            language: settings.language
        )
        var notificationSettings = await center.notificationSettings()
        permissionState = NotificationPermissionState(notificationSettings.authorizationStatus)
        if notificationSettings.authorizationStatus == .notDetermined,
           forceAuthorizationRequest || (requestAuthorizationIfNeeded && !plan.isEmpty) {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            guard !Task.isCancelled else { return }
            notificationSettings = await center.notificationSettings()
            permissionState = NotificationPermissionState(notificationSettings.authorizationStatus)
        }
        guard !Task.isCancelled else { return }

        let pending = await center.pendingNotificationRequests()
        let managedPendingIDs = pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.managedPrefix) }
        if !managedPendingIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: managedPendingIDs)
        }
        let delivered = await center.deliveredNotifications()
        let liveEntityIdentifiers = ReminderPlanner.activeEntityIdentifiers(in: store.notes)
        let staleDeliveredIDs = delivered.map { $0.request.identifier }.filter { identifier in
            guard identifier.hasPrefix(ReminderPlanner.managedPrefix) else { return false }
            if identifier.hasPrefix("docknotes.daily-summary.") {
                return !settings.dailySummaryEnabled
            }
            return !liveEntityIdentifiers.contains(identifier)
        }
        if !staleDeliveredIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: staleDeliveredIDs)
        }

        guard permissionState == .allowed else {
            scheduledRequestCount = 0
            return
        }
        var added = 0
        for descriptor in plan {
            guard !Task.isCancelled else { return }
            do {
                try await center.add(ReminderSystemBridge.request(for: descriptor))
                added += 1
            } catch {
                continue
            }
        }
        scheduledRequestCount = added
    }
}
