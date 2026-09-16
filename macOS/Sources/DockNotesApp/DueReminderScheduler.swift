import Foundation
import UserNotifications

@MainActor
enum DueReminderScheduler {
    private static var generationByNoteID: [DockNote.ID: Int] = [:]

    static func identifier(for noteID: DockNote.ID) -> String {
        "docknotes.deadline.\(noteID.uuidString.lowercased())"
    }

    static func schedule(for note: DockNote, language: AppLanguage = .system) {
        guard !CommandLine.arguments.contains("--self-test") else { return }
        let center = UNUserNotificationCenter.current()
        let identifier = identifier(for: note.id)
        let generation = (generationByNoteID[note.id] ?? 0) + 1
        generationByNoteID[note.id] = generation
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        guard let dueDate = note.dueDate, dueDate > Date() else { return }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                guard generationByNoteID[note.id] == generation else { return }
                let content = UNMutableNotificationContent()
                content.title = note.title.isEmpty ? "DockNotes" : note.title
                content.body = L10n.text(.deadlineReached, language: language)
                content.sound = .default
                content.userInfo = ["noteID": note.id.uuidString]
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: dueDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try? await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                )
            }
        }
    }

    static func cancel(for noteID: DockNote.ID) {
        guard !CommandLine.arguments.contains("--self-test") else { return }
        generationByNoteID[noteID] = (generationByNoteID[noteID] ?? 0) + 1
        let identifier = identifier(for: noteID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
