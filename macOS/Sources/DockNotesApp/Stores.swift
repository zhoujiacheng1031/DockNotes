import Combine
import Foundation

enum DeckEdge: String, CaseIterable, Identifiable {
    case left
    case right

    var id: Self { self }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let language = "docknotes.language"
        static let expandedOpacity = "docknotes.opacity.expanded"
        static let collapsedOpacity = "docknotes.opacity.collapsed"
        static let keepDeckOpen = "docknotes.deck.keepOpen"
        static let visibleTabCount = "docknotes.deck.visibleTabCount"
        static let deckEdge = "docknotes.deck.edge"
    }

    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: Key.language) } }
    @Published var expandedOpacity: Double { didSet { defaults.set(Self.clamp(expandedOpacity), forKey: Key.expandedOpacity) } }
    @Published var collapsedOpacity: Double { didSet { defaults.set(Self.clamp(collapsedOpacity), forKey: Key.collapsedOpacity) } }
    @Published var keepDeckOpen: Bool { didSet { defaults.set(keepDeckOpen, forKey: Key.keepDeckOpen) } }
    @Published var visibleTabCount: Int {
        didSet {
            let clamped = Self.clampVisibleTabCount(visibleTabCount)
            if visibleTabCount != clamped { visibleTabCount = clamped }
            defaults.set(clamped, forKey: Key.visibleTabCount)
        }
    }
    @Published var deckEdge: DeckEdge { didSet { defaults.set(deckEdge.rawValue, forKey: Key.deckEdge) } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .system
        expandedOpacity = defaults.object(forKey: Key.expandedOpacity) == nil ? 0.96 : Self.clamp(defaults.double(forKey: Key.expandedOpacity))
        collapsedOpacity = defaults.object(forKey: Key.collapsedOpacity) == nil ? 0.92 : Self.clamp(defaults.double(forKey: Key.collapsedOpacity))
        keepDeckOpen = defaults.object(forKey: Key.keepDeckOpen) == nil ? true : defaults.bool(forKey: Key.keepDeckOpen)
        visibleTabCount = defaults.object(forKey: Key.visibleTabCount) == nil
            ? 4
            : Self.clampVisibleTabCount(defaults.integer(forKey: Key.visibleTabCount))
        deckEdge = DeckEdge(rawValue: defaults.string(forKey: Key.deckEdge) ?? "") ?? .right
    }

    static func clamp(_ value: Double) -> Double { min(max(value, 0.20), 1.0) }
    static func clampVisibleTabCount(_ value: Int) -> Int { min(max(value, 1), 7) }
    func text(_ key: L10nKey) -> String { L10n.text(key, language: language) }
}

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [DockNote]
    @Published private(set) var archivedNotes: [DockNote]
    @Published var activeNoteID: DockNote.ID?
    @Published private(set) var deckState: DeckState = .fanned
    @Published var isPreferencesPresented = false
    @Published var isLibraryPresented = false
    @Published private(set) var desktopNoteIDs: [DockNote.ID] = []
    private var restTask: Task<Void, Never>?
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? base.appendingPathComponent("DockNotes", isDirectory: true).appendingPathComponent("notes.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? decoder.decode([DockNote].self, from: data),
           !decoded.isEmpty {
            let migratedNotes = decoded.enumerated().map { index, note in
                var migrated = note
                migrated.colorHex = NotePalette.migrated(note.colorHex)
                if migrated.gradientEndHex == nil {
                    let gradient = NotePalette.gradients[index % NotePalette.gradients.count]
                    migrated.colorHex = gradient.startHex
                    migrated.gradientEndHex = gradient.endHex
                }
                return migrated
            }
            notes = migratedNotes.filter { !$0.isArchived }
            archivedNotes = migratedNotes.filter(\.isArchived)
        } else {
            notes = DockNote.samples
            archivedNotes = []
        }
        activeNoteID = notes.first?.id
    }

    var activeNote: DockNote? {
        guard let activeNoteID else { return notes.first }
        return notes.first(where: { $0.id == activeNoteID }) ?? notes.first
    }

    var isExpanded: Bool { deckState.openNoteID != nil }

    func note(id: DockNote.ID) -> DockNote? {
        notes.first(where: { $0.id == id })
    }

    func pointerEnteredDeck() {
        restTask?.cancel()
        restTask = nil
        if deckState == .resting { deckState = .fanned }
    }

    func pointerExitedDeck(keepOpen: Bool) {
        guard !keepOpen, deckState == .fanned else { return }
        scheduleRest()
    }

    func dismissDeck() {
        restTask?.cancel()
        restTask = nil
        deckState = .resting
    }

    func select(_ id: DockNote.ID) {
        restTask?.cancel()
        activeNoteID = id
        deckState = .noteOpen(id)
        isPreferencesPresented = false
    }

    func collapseActive(keepDeckOpen: Bool = false) {
        isPreferencesPresented = false
        if keepDeckOpen {
            restTask?.cancel()
            deckState = .fanned
        } else {
            deckState = .fanned
            scheduleRest()
        }
    }

    func presentSettings() {
        isPreferencesPresented = true
    }

    func presentLibrary() {
        isLibraryPresented = true
        isPreferencesPresented = false
    }

    func presentOnDesktop(_ id: DockNote.ID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        if !desktopNoteIDs.contains(id) { desktopNoteIDs.append(id) }
        activeNoteID = id
        deckState = .fanned
    }

    func closeDesktopNote(_ id: DockNote.ID) {
        desktopNoteIDs.removeAll { $0 == id }
    }

    func handleOutsideClick(keepDeckOpen: Bool = false) {
        isPreferencesPresented = false
        if isExpanded {
            restTask?.cancel()
            deckState = keepDeckOpen ? .fanned : .resting
        } else if deckState == .fanned, !keepDeckOpen {
            dismissDeck()
        }
    }

    func addNote(language: AppLanguage) {
        let note = DockNote(title: L10n.text(.newNote, language: language), colorHex: NotePalette.colors[0])
        notes.append(note)
        activeNoteID = note.id
        deckState = .noteOpen(note.id)
        persist()
    }

    func updateTitle(_ title: String) { mutateActive { $0.title = title } }
    func updateBody(_ body: String) { mutateActive { $0.body = body } }
    func updateTitle(_ title: String, for noteID: DockNote.ID) { mutate(noteID) { $0.title = title } }
    func updateBody(_ body: String, for noteID: DockNote.ID) { mutate(noteID) { $0.body = body } }
    func setColor(_ colorHex: String) {
        guard let activeNoteID else { return }
        setColor(colorHex, for: activeNoteID)
    }
    func setColor(_ colorHex: String, for noteID: DockNote.ID) {
        mutate(noteID) {
            $0.colorHex = colorHex
            $0.gradientEndHex = colorHex
        }
    }
    func setGradient(_ gradient: NoteGradient) {
        guard let activeNoteID else { return }
        setGradient(gradient, for: activeNoteID)
    }
    func setGradient(_ gradient: NoteGradient, for noteID: DockNote.ID) {
        mutate(noteID) {
            $0.colorHex = gradient.startHex
            $0.gradientEndHex = gradient.endHex
        }
    }
    func setMaterial(_ material: NoteMaterial) { mutateActive { $0.material = material } }
    func setMaterial(_ material: NoteMaterial, for noteID: DockNote.ID) { mutate(noteID) { $0.material = material } }
    func setFontStyle(_ style: NoteFontStyle, for noteID: DockNote.ID) { mutate(noteID) { $0.fontStyle = style } }
    func setFontSize(_ size: Double, for noteID: DockNote.ID) { mutate(noteID) { $0.fontSize = min(max(size, 11), 28) } }
    func setDueDate(_ date: Date?) { mutateActive { $0.dueDate = date } }
    func setDueDate(_ date: Date?, for noteID: DockNote.ID) { mutate(noteID) { $0.dueDate = date } }
    func insertTask() {
        guard let activeNoteID else { return }
        insertTask(for: activeNoteID)
    }
    func insertTask(for noteID: DockNote.ID) {
        mutate(noteID) { note in
            let separator = note.body.isEmpty || note.body.hasSuffix("\n") ? "" : "\n"
            note.body += separator + "☐ "
        }
    }
    func updateBodyWithDictation(base: String, transcript: String) {
        let separator = base.isEmpty || base.hasSuffix("\n") ? "" : "\n"
        mutateActive { $0.body = base + separator + transcript }
    }
    func updateBodyWithDictation(base: String, transcript: String, for noteID: DockNote.ID) {
        let separator = base.isEmpty || base.hasSuffix("\n") ? "" : "\n"
        mutate(noteID) { $0.body = base + separator + transcript }
    }
    func togglePinned() { mutateActive { $0.isPinned.toggle() } }
    func togglePinned(_ noteID: DockNote.ID) { mutate(noteID) { $0.isPinned.toggle() } }

    func archiveActive() {
        guard let activeNoteID else { return }
        archive(activeNoteID)
    }

    func archive(_ noteID: DockNote.ID) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        var note = notes.remove(at: index)
        note.isArchived = true
        note.modifiedAt = .now
        archivedNotes.insert(note, at: 0)
        desktopNoteIDs.removeAll { $0 == noteID }
        if activeNoteID == noteID {
            activeNoteID = notes.first?.id
            dismissDeck()
        }
        persist()
    }

    func restoreArchived(_ id: DockNote.ID) {
        guard let index = archivedNotes.firstIndex(where: { $0.id == id }) else { return }
        var note = archivedNotes.remove(at: index)
        note.isArchived = false
        note.modifiedAt = .now
        notes.append(note)
        persist()
    }

    func openFromLibrary(_ id: DockNote.ID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        isLibraryPresented = false
        select(id)
    }

    func moveNote(_ sourceID: DockNote.ID, to targetIndex: Int) {
        guard let sourceIndex = notes.firstIndex(where: { $0.id == sourceID }) else { return }
        let destination = min(max(targetIndex, 0), notes.count - 1)
        guard sourceIndex != destination else { return }
        let note = notes.remove(at: sourceIndex)
        notes.insert(note, at: min(destination, notes.count))
        persist()
    }

    func deleteActive() {
        guard let activeNoteID else { return }
        delete(activeNoteID)
    }

    func delete(_ noteID: DockNote.ID) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes.remove(at: index)
        desktopNoteIDs.removeAll { $0 == noteID }
        if activeNoteID == noteID {
            activeNoteID = notes.first?.id
            dismissDeck()
        }
        persist()
    }

    private func mutateActive(_ mutation: (inout DockNote) -> Void) {
        guard let activeNoteID else { return }
        mutate(activeNoteID, mutation)
    }

    private func mutate(_ noteID: DockNote.ID, _ mutation: (inout DockNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        mutation(&notes[index])
        notes[index].modifiedAt = .now
        persist()
    }

    func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(notes + archivedNotes).write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("DockNotes could not save notes: \(error)")
        }
    }

    private func scheduleRest() {
        restTask?.cancel()
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.deckState == .fanned else { return }
                self.deckState = .resting
                self.restTask = nil
            }
        }
    }
}
