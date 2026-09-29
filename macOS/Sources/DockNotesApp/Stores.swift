import Combine
import Foundation
import Security

enum DeckEdge: String, CaseIterable, Identifiable {
    case left
    case right

    var id: Self { self }
}

enum QuickCaptureShortcut: String, CaseIterable, Identifiable {
    case shiftCommandSpace
    case optionCommandSpace
    case controlOptionSpace

    var id: Self { self }

    var displayName: String {
        switch self {
        case .shiftCommandSpace: "⇧⌘Space"
        case .optionCommandSpace: "⌥⌘Space"
        case .controlOptionSpace: "⌃⌥Space"
        }
    }
}

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case openAICompatible
    case anthropic

    var id: Self { self }

    var endpointPath: String {
        switch self {
        case .openAICompatible: "chat/completions"
        case .anthropic: "messages"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .openAICompatible: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .openAICompatible: ["gpt-5", "gpt-5-mini", "gpt-4.1"]
        case .anthropic: ["claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5-20251001"]
        }
    }
}

enum ObsidianBackupFailure: Equatable {
    case missingFolder
    case writeFailed(String)
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
        static let quickCaptureShortcut = "docknotes.shortcut.quickCapture"
        static let taskRemindersEnabled = "docknotes.reminders.tasks.enabled"
        static let dailySummaryEnabled = "docknotes.reminders.daily.enabled"
        static let dailySummaryMinutes = "docknotes.reminders.daily.minutes"
        static let calendarSyncEnabled = "docknotes.calendar.sync.enabled"
        static let calendarIdentifier = "docknotes.calendar.identifier"
        static let aiEndpoint = "docknotes.ai.endpoint"
        static let aiModel = "docknotes.ai.model"
        static let aiProvider = "docknotes.ai.provider"
        static let anthropicEndpoint = "docknotes.ai.anthropic.endpoint"
        static let anthropicModel = "docknotes.ai.anthropic.model"
        static let obsidianBackupEnabled = "docknotes.archive.obsidian.enabled"
        static let obsidianVaultPath = "docknotes.archive.obsidian.path"
        static let obsidianVaultBookmark = "docknotes.archive.obsidian.bookmark"
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
    @Published var quickCaptureShortcut: QuickCaptureShortcut {
        didSet { defaults.set(quickCaptureShortcut.rawValue, forKey: Key.quickCaptureShortcut) }
    }
    @Published var taskRemindersEnabled: Bool {
        didSet { defaults.set(taskRemindersEnabled, forKey: Key.taskRemindersEnabled) }
    }
    @Published var dailySummaryEnabled: Bool {
        didSet { defaults.set(dailySummaryEnabled, forKey: Key.dailySummaryEnabled) }
    }
    @Published var dailySummaryMinutes: Int {
        didSet {
            let clamped = Self.clampDailySummaryMinutes(dailySummaryMinutes)
            if dailySummaryMinutes != clamped { dailySummaryMinutes = clamped }
            defaults.set(clamped, forKey: Key.dailySummaryMinutes)
        }
    }
    @Published var calendarSyncEnabled: Bool {
        didSet { defaults.set(calendarSyncEnabled, forKey: Key.calendarSyncEnabled) }
    }
    @Published var calendarIdentifier: String? {
        didSet {
            if let calendarIdentifier {
                defaults.set(calendarIdentifier, forKey: Key.calendarIdentifier)
            } else {
                defaults.removeObject(forKey: Key.calendarIdentifier)
            }
        }
    }
    @Published private(set) var quickCaptureShortcutRegistrationFailed = false
    @Published var aiProvider: AIProvider {
        didSet {
            guard aiProvider != oldValue else { return }
            defaults.set(aiProvider.rawValue, forKey: Key.aiProvider)
            aiEndpoint = loadStoredAIEndpoint(for: aiProvider)
            aiModel = loadStoredAIModel(for: aiProvider)
            loadAIKeyAsync(for: aiProvider)
        }
    }
    @Published var aiEndpoint: String {
        didSet { defaults.set(aiEndpoint, forKey: endpointKey(for: aiProvider)) }
    }
    @Published var aiModel: String {
        didSet { defaults.set(aiModel, forKey: modelKey(for: aiProvider)) }
    }
    @Published private(set) var aiAPIKey: String
    @Published private(set) var aiCredentialStorageFailed = false
    @Published var obsidianBackupEnabled: Bool {
        didSet { defaults.set(obsidianBackupEnabled, forKey: Key.obsidianBackupEnabled) }
    }
    @Published private(set) var obsidianVaultPath: String
    private let defaults: UserDefaults
    private var aiCredentialLoadGeneration: UInt64 = 0

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
        quickCaptureShortcut = QuickCaptureShortcut(
            rawValue: defaults.string(forKey: Key.quickCaptureShortcut) ?? ""
        ) ?? .shiftCommandSpace
        taskRemindersEnabled = defaults.object(forKey: Key.taskRemindersEnabled) == nil
            ? true
            : defaults.bool(forKey: Key.taskRemindersEnabled)
        dailySummaryEnabled = defaults.bool(forKey: Key.dailySummaryEnabled)
        dailySummaryMinutes = defaults.object(forKey: Key.dailySummaryMinutes) == nil
            ? 8 * 60
            : Self.clampDailySummaryMinutes(defaults.integer(forKey: Key.dailySummaryMinutes))
        calendarSyncEnabled = defaults.bool(forKey: Key.calendarSyncEnabled)
        calendarIdentifier = defaults.string(forKey: Key.calendarIdentifier)
        aiProvider = AIProvider(rawValue: defaults.string(forKey: Key.aiProvider) ?? "") ?? .openAICompatible
        aiEndpoint = ""
        aiModel = ""
        aiAPIKey = ""
        obsidianBackupEnabled = defaults.bool(forKey: Key.obsidianBackupEnabled)
        obsidianVaultPath = defaults.string(forKey: Key.obsidianVaultPath) ?? ""
        aiEndpoint = loadStoredAIEndpoint(for: aiProvider)
        aiModel = loadStoredAIModel(for: aiProvider)
        loadAIKeyAsync(for: aiProvider)
    }

    static func clamp(_ value: Double) -> Double { min(max(value, 0.20), 1.0) }
    static func clampVisibleTabCount(_ value: Int) -> Int { min(max(value, 1), 7) }
    static func clampDailySummaryMinutes(_ value: Int) -> Int { min(max(value, 0), 23 * 60 + 59) }
    func text(_ key: L10nKey) -> String { L10n.text(key, language: language) }

    func reportQuickCaptureShortcutRegistration(_ succeeded: Bool) {
        quickCaptureShortcutRegistrationFailed = !succeeded
    }

    var isAIConfigured: Bool {
        !aiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !aiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveAIConfiguration(
        provider: AIProvider,
        endpoint: String,
        model: String,
        apiKey: String
    ) async -> Bool {
        aiProvider = provider
        aiCredentialLoadGeneration &+= 1
        aiEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        aiModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        aiAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let valueToStore = aiAPIKey
        let credentialSaved = await Task.detached(priority: .utility) {
            AIKeychain.write(valueToStore, provider: provider)
        }.value
        aiCredentialStorageFailed = !credentialSaved
        defaults.synchronize()
        return credentialSaved
    }

    func storedAIEndpoint(for provider: AIProvider) -> String {
        loadStoredAIEndpoint(for: provider)
    }

    func storedAIModel(for provider: AIProvider) -> String {
        loadStoredAIModel(for: provider)
    }

    func storedAIAPIKey(for provider: AIProvider) -> String {
        provider == aiProvider ? aiAPIKey : ""
    }

    func loadAIAPIKey(for provider: AIProvider) async -> String {
        guard !CommandLine.arguments.contains("--self-test") else { return "" }
        if provider == aiProvider, !aiAPIKey.isEmpty { return aiAPIKey }
        return await Task.detached(priority: .utility) {
            AIKeychain.read(provider: provider) ?? ""
        }.value
    }

    var obsidianVaultURL: URL? {
        if let bookmark = defaults.data(forKey: Key.obsidianVaultBookmark) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        guard !obsidianVaultPath.isEmpty else { return nil }
        return URL(fileURLWithPath: obsidianVaultPath, isDirectory: true)
    }

    func setObsidianVault(_ url: URL?) {
        guard let url else {
            obsidianVaultPath = ""
            defaults.removeObject(forKey: Key.obsidianVaultPath)
            defaults.removeObject(forKey: Key.obsidianVaultBookmark)
            return
        }
        obsidianVaultPath = url.path
        defaults.set(url.path, forKey: Key.obsidianVaultPath)
        if let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(bookmark, forKey: Key.obsidianVaultBookmark)
        }
    }

    private func endpointKey(for provider: AIProvider) -> String {
        provider == .anthropic ? Key.anthropicEndpoint : Key.aiEndpoint
    }

    private func modelKey(for provider: AIProvider) -> String {
        provider == .anthropic ? Key.anthropicModel : Key.aiModel
    }

    private func loadStoredAIEndpoint(for provider: AIProvider) -> String {
        defaults.string(forKey: endpointKey(for: provider)) ?? provider.defaultEndpoint
    }

    private func loadStoredAIModel(for provider: AIProvider) -> String {
        defaults.string(forKey: modelKey(for: provider)) ?? ""
    }

    private func loadAIKeyAsync(for provider: AIProvider) {
        aiCredentialLoadGeneration &+= 1
        let generation = aiCredentialLoadGeneration
        aiAPIKey = ""
        guard !CommandLine.arguments.contains("--self-test") else { return }
        Task { [weak self] in
            let value = await Task.detached(priority: .utility) {
                AIKeychain.read(provider: provider) ?? ""
            }.value
            guard let self,
                  self.aiCredentialLoadGeneration == generation,
                  self.aiProvider == provider else { return }
            self.aiAPIKey = value
        }
    }
}

private enum AIKeychain {
    private static let service = "com.local.DockNotes.ai"
    private static let legacyAccount = "openai-compatible-api-key"

    static func read(provider: AIProvider) -> String? {
        read(account: provider.rawValue)
            ?? (provider == .openAICompatible ? read(account: legacyAccount) : nil)
    }

    private static func read(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, provider: AIProvider) -> Bool {
        let account = provider.rawValue
        let identity: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if value.isEmpty {
            let status = SecItemDelete(identity as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(identity as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData] = data
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
}

@MainActor
final class NotesStore: ObservableObject {
    enum UtilityWindowRequest {
        case settings
        case library
        case taskCenter
    }

    @Published private(set) var notes: [DockNote]
    @Published private(set) var archivedNotes: [DockNote]
    @Published private(set) var workspaces: [NoteWorkspace]
    @Published private(set) var activeWorkspaceID: NoteWorkspace.ID
    @Published private(set) var defaultWorkspaceID: NoteWorkspace.ID
    @Published var activeNoteID: DockNote.ID?
    @Published private(set) var deckState: DeckState = .fanned
    @Published var isPreferencesPresented = false
    @Published var isLibraryPresented = false
    @Published var isWorkspaceManagementPresented = false
    @Published var isTaskCenterPresented = false
    @Published var isQuickCapturePresented = false
    let utilityWindowRequests = PassthroughSubject<UtilityWindowRequest, Never>()
    @Published private(set) var desktopNoteIDs: [DockNote.ID] = []
    @Published private(set) var lastObsidianBackupURL: URL?
    @Published private(set) var lastObsidianBackupError: ObsidianBackupFailure?
    @Published private(set) var saveState: NoteSaveState = .saved(.now)
    @Published private(set) var didRecoverFromBackup = false
    @Published private(set) var pendingDeletions: [PendingDeletion] = []
    @Published private(set) var pendingWorkspaceDeletions: [PendingWorkspaceDeletion] = []
    private var restTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var deletionTasks: [PendingDeletion.ID: Task<Void, Never>] = [:]
    private var workspaceDeletionTasks: [PendingWorkspaceDeletion.ID: Task<Void, Never>] = [:]
    private var saveGeneration: UInt64 = 0
    private var trackedDeckLabels: Set<UUID> = []
    private var pointerIsInsideDeck = false

    func beginTrackingDeckLabel(_ id: UUID) {
        trackedDeckLabels.insert(id)
        restTask?.cancel()
        restTask = nil
    }

    func endTrackingDeckLabel(_ id: UUID, keepOpen: Bool, pointerInside: Bool? = nil) {
        trackedDeckLabels.remove(id)
        if let pointerInside { pointerIsInsideDeck = pointerInside }
        if !pointerIsInsideDeck { pointerExitedDeck(keepOpen: keepOpen) }
    }
    private let fileURL: URL
    private let backupURL: URL
    private let preMigrationBackupURL: URL
    private let writeData: (Data, URL) throws -> Void
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL? = nil,
        writeData: ((Data, URL) throws -> Void)? = nil
    ) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let resolvedFileURL = fileURL
            ?? base.appendingPathComponent("DockNotes", isDirectory: true)
                .appendingPathComponent("notes.json")
        self.fileURL = resolvedFileURL
        backupURL = resolvedFileURL.appendingPathExtension("backup")
        preMigrationBackupURL = resolvedFileURL.appendingPathExtension("pre-v0.9")
        self.writeData = writeData ?? { data, url in
            try data.write(to: url, options: .atomic)
        }
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let primarySnapshot = Self.decodeSnapshot(at: resolvedFileURL, using: decoder)
        let recoveredSnapshot = primarySnapshot == nil
            ? Self.decodeSnapshot(at: backupURL, using: decoder)
            : nil
        let loadedSnapshot = primarySnapshot ?? recoveredSnapshot
        var shouldRewriteSnapshot = false
        var legacySourceURL: URL?
        if let loadedSnapshot {
            let normalized = Self.normalizedDocument(loadedSnapshot.document)
            workspaces = normalized.workspaces
            activeWorkspaceID = normalized.activeWorkspaceID
            defaultWorkspaceID = normalized.defaultWorkspaceID
            notes = normalized.notes.filter { !$0.isArchived }
            archivedNotes = normalized.notes.filter(\.isArchived)
            didRecoverFromBackup = primarySnapshot == nil && recoveredSnapshot != nil
            shouldRewriteSnapshot = loadedSnapshot.wasLegacy
                || normalized != loadedSnapshot.document
                || didRecoverFromBackup
            if loadedSnapshot.wasLegacy {
                legacySourceURL = primarySnapshot == nil ? backupURL : resolvedFileURL
            }
        } else {
            let workspace = Self.makeDefaultWorkspace()
            workspaces = [workspace]
            activeWorkspaceID = workspace.id
            defaultWorkspaceID = workspace.id
            notes = DockNote.samples.map { note in
                var note = note
                note.workspaceID = workspace.id
                return note
            }
            archivedNotes = []
        }
        let preferredActiveNoteID = workspaces.first(where: { $0.id == activeWorkspaceID })?.lastActiveNoteID
        activeNoteID = preferredActiveNoteID.flatMap { preferred in
            notes.first(where: { $0.id == preferred && $0.workspaceID == activeWorkspaceID })?.id
        } ?? notes.first(where: { $0.workspaceID == activeWorkspaceID })?.id
        if let legacySourceURL,
           !FileManager.default.fileExists(atPath: preMigrationBackupURL.path),
           let legacyData = try? Data(contentsOf: legacySourceURL) {
            try? self.writeData(legacyData, preMigrationBackupURL)
        }
        if shouldRewriteSnapshot { persist() }
    }

    var activeNote: DockNote? {
        guard let activeNoteID else { return activeWorkspaceNotes.first }
        return notes.first(where: { $0.id == activeNoteID }) ?? activeWorkspaceNotes.first
    }

    var activeWorkspace: NoteWorkspace {
        workspaces.first(where: { $0.id == activeWorkspaceID })
            ?? workspaces.first!
    }

    var activeWorkspaceNotes: [DockNote] {
        notes.filter { $0.workspaceID == activeWorkspaceID }
    }

    var latestPendingWorkspaceDeletion: PendingWorkspaceDeletion? {
        pendingWorkspaceDeletions.last
    }

    private struct DecodedSnapshot {
        let document: DockNotesDocument
        let wasLegacy: Bool
    }

    private static func decodeSnapshot(at url: URL, using decoder: JSONDecoder) -> DecodedSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let document = try? decoder.decode(DockNotesDocument.self, from: data),
           document.schemaVersion <= DockNotesDocument.currentSchemaVersion {
            return DecodedSnapshot(document: document, wasLegacy: false)
        }
        guard let legacyNotes = try? decoder.decode([DockNote].self, from: data) else { return nil }
        let workspace = makeDefaultWorkspace()
        let migratedNotes = legacyNotes.map { note in
            var note = note
            note.workspaceID = workspace.id
            return note
        }
        return DecodedSnapshot(
            document: DockNotesDocument(
                activeWorkspaceID: workspace.id,
                defaultWorkspaceID: workspace.id,
                workspaces: [workspace],
                notes: migratedNotes
            ),
            wasLegacy: true
        )
    }

    private static func makeDefaultWorkspace() -> NoteWorkspace {
        NoteWorkspace(
            name: Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "默认工作区" : "Default Workspace",
            colorHex: NotePalette.gradients[3].startHex
        )
    }

    private static func normalizedDocument(_ source: DockNotesDocument) -> DockNotesDocument {
        var document = source
        document.schemaVersion = DockNotesDocument.currentSchemaVersion
        var seenWorkspaceIDs = Set<NoteWorkspace.ID>()
        document.workspaces = document.workspaces.enumerated().compactMap { index, workspace in
            guard seenWorkspaceIDs.insert(workspace.id).inserted else { return nil }
            var workspace = workspace
            workspace.name = workspace.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if workspace.name.isEmpty { workspace.name = "Workspace \(index + 1)" }
            workspace.colorHex = ColorInput.normalizedHex(NotePalette.migrated(workspace.colorHex))
                ?? NotePalette.gradients[index % NotePalette.gradients.count].startHex
            return workspace
        }
        if document.workspaces.isEmpty {
            document.workspaces = [makeDefaultWorkspace()]
        }
        let workspaceIDs = Set(document.workspaces.map(\.id))
        if !workspaceIDs.contains(document.defaultWorkspaceID) {
            document.defaultWorkspaceID = document.workspaces[0].id
        }
        if !workspaceIDs.contains(document.activeWorkspaceID) {
            document.activeWorkspaceID = document.defaultWorkspaceID
        }
        document.notes = document.notes.enumerated().map { index, note in
            var migrated = note
            if migrated.workspaceID.map({ workspaceIDs.contains($0) }) != true {
                migrated.workspaceID = document.defaultWorkspaceID
            }
            migrated.colorHex = NotePalette.migrated(note.colorHex)
            if migrated.gradientEndHex == nil {
                let gradient = NotePalette.gradients[index % NotePalette.gradients.count]
                migrated.colorHex = gradient.startHex
                migrated.gradientEndHex = gradient.endHex
            }
            synchronizeTasksAndAdvanceRecurrences(in: &migrated)
            return migrated
        }
        let activeNoteIDs = Set(document.notes.filter { !$0.isArchived }.map(\.id))
        document.workspaces = document.workspaces.map { workspace in
            var workspace = workspace
            if workspace.lastActiveNoteID.map({ noteID in
                activeNoteIDs.contains(noteID)
                    && document.notes.contains { $0.id == noteID && $0.workspaceID == workspace.id }
            }) != true {
                workspace.lastActiveNoteID = nil
            }
            return workspace
        }
        return document
    }

    var isExpanded: Bool { deckState.openNoteID != nil }

    var latestPendingDeletion: PendingDeletion? { pendingDeletions.last }

    func workspace(id: NoteWorkspace.ID) -> NoteWorkspace? {
        workspaces.first(where: { $0.id == id })
    }

    func note(id: DockNote.ID) -> DockNote? {
        notes.first(where: { $0.id == id })
    }

    func pointerEnteredDeck() {
        pointerIsInsideDeck = true
        restTask?.cancel()
        restTask = nil
        transitionDeck(.pointerEntered)
    }

    func pointerExitedDeck(keepOpen: Bool) {
        pointerIsInsideDeck = false
        guard trackedDeckLabels.isEmpty, !keepOpen, deckState == .fanned else { return }
        scheduleRest()
    }

    func dismissDeck() {
        restTask?.cancel()
        restTask = nil
        transitionDeck(.dismissed)
    }

    func select(_ id: DockNote.ID) {
        guard let note = notes.first(where: { $0.id == id }),
              let workspaceID = note.workspaceID,
              workspaces.contains(where: { $0.id == workspaceID }) else { return }
        restTask?.cancel()
        activeWorkspaceID = workspaceID
        activeNoteID = id
        rememberLastActiveNote(id, in: workspaceID)
        transitionDeck(.noteSelected(id))
        isPreferencesPresented = false
        schedulePersist()
    }

    @discardableResult
    func createWorkspace(
        name: String,
        colorHex: String = NotePalette.gradients[3].startHex,
        makeActive: Bool = true
    ) -> NoteWorkspace? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let normalizedColor = ColorInput.normalizedHex(NotePalette.migrated(colorHex))
            ?? NotePalette.gradients[workspaces.count % NotePalette.gradients.count].startHex
        let workspace = NoteWorkspace(name: trimmedName, colorHex: normalizedColor)
        workspaces.append(workspace)
        if makeActive { switchWorkspace(to: workspace.id) }
        persist()
        return workspace
    }

    @discardableResult
    func renameWorkspace(_ id: NoteWorkspace.ID, to name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = workspaces.firstIndex(where: { $0.id == id }) else { return false }
        guard workspaces[index].name != trimmedName else { return true }
        workspaces[index].name = trimmedName
        persist()
        return true
    }

    @discardableResult
    func setWorkspaceColor(_ id: NoteWorkspace.ID, colorHex: String) -> Bool {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return false }
        guard let migratedColor = ColorInput.normalizedHex(NotePalette.migrated(colorHex)) else {
            return false
        }
        guard workspaces[index].colorHex != migratedColor else { return true }
        workspaces[index].colorHex = migratedColor
        persist()
        return true
    }

    func moveWorkspace(_ sourceID: NoteWorkspace.ID, to targetIndex: Int) {
        guard let sourceIndex = workspaces.firstIndex(where: { $0.id == sourceID }),
              workspaces.count > 1 else { return }
        let destination = min(max(targetIndex, 0), workspaces.count - 1)
        guard sourceIndex != destination else { return }
        let workspace = workspaces.remove(at: sourceIndex)
        workspaces.insert(workspace, at: min(destination, workspaces.count))
        persist()
    }

    func switchWorkspace(to id: NoteWorkspace.ID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        if activeWorkspaceID != id {
            activeWorkspaceID = id
            transitionDeck(.collapsed)
        }
        let preferredNoteID = workspace(id: id)?.lastActiveNoteID
        activeNoteID = preferredNoteID.flatMap { preferred in
            notes.first(where: { $0.id == preferred && $0.workspaceID == id })?.id
        } ?? notes.first(where: { $0.workspaceID == id })?.id
        schedulePersist()
    }

    func moveNote(_ noteID: DockNote.ID, toWorkspace workspaceID: NoteWorkspace.ID, at targetIndex: Int? = nil) {
        guard workspaces.contains(where: { $0.id == workspaceID }),
              let sourceIndex = notes.firstIndex(where: { $0.id == noteID }) else { return }
        var note = notes.remove(at: sourceIndex)
        let sourceWorkspaceID = note.workspaceID
        note.workspaceID = workspaceID
        note.modifiedAt = .now
        let destinationIndices = notes.indices.filter { notes[$0].workspaceID == workspaceID }
        let workspaceIndex = min(max(targetIndex ?? destinationIndices.count, 0), destinationIndices.count)
        let insertionIndex: Int
        if destinationIndices.isEmpty {
            insertionIndex = notes.count
        } else if workspaceIndex == destinationIndices.count {
            insertionIndex = destinationIndices.last! + 1
        } else {
            insertionIndex = destinationIndices[workspaceIndex]
        }
        notes.insert(note, at: min(insertionIndex, notes.count))
        if sourceWorkspaceID != workspaceID {
            clearLastActiveNote(noteID, in: sourceWorkspaceID)
        }
        if activeNoteID == noteID {
            if workspaceID == activeWorkspaceID {
                rememberLastActiveNote(noteID, in: workspaceID)
            } else {
                activeNoteID = preferredActiveNoteID(in: activeWorkspaceID)
                transitionDeck(.collapsed)
            }
        }
        schedulePersist()
    }

    func moveNotes(_ noteIDs: Set<DockNote.ID>, toWorkspace workspaceID: NoteWorkspace.ID) {
        guard !noteIDs.isEmpty,
              workspaces.contains(where: { $0.id == workspaceID }) else { return }
        let movedActive = notes.filter { noteIDs.contains($0.id) }
        let movedArchived = archivedNotes.filter { noteIDs.contains($0.id) }
        guard !movedActive.isEmpty || !movedArchived.isEmpty else { return }

        let affectedSourceWorkspaceIDs = Set((movedActive + movedArchived).compactMap(\.workspaceID))
        notes.removeAll { noteIDs.contains($0.id) }
        archivedNotes.removeAll { noteIDs.contains($0.id) }

        let updatedActive = movedActive.map { note -> DockNote in
            var note = note
            note.workspaceID = workspaceID
            note.modifiedAt = .now
            return note
        }
        let updatedArchived = movedArchived.map { note -> DockNote in
            var note = note
            note.workspaceID = workspaceID
            return note
        }
        let activeInsertion = notes.lastIndex(where: { $0.workspaceID == workspaceID }).map { $0 + 1 }
            ?? notes.endIndex
        notes.insert(contentsOf: updatedActive, at: activeInsertion)
        let archivedInsertion = archivedNotes.lastIndex(where: { $0.workspaceID == workspaceID }).map { $0 + 1 }
            ?? archivedNotes.endIndex
        archivedNotes.insert(contentsOf: updatedArchived, at: archivedInsertion)

        for sourceWorkspaceID in affectedSourceWorkspaceIDs where sourceWorkspaceID != workspaceID {
            if let rememberedID = workspace(id: sourceWorkspaceID)?.lastActiveNoteID,
               noteIDs.contains(rememberedID) {
                clearLastActiveNote(rememberedID, in: sourceWorkspaceID)
            }
        }
        if let activeNoteID, noteIDs.contains(activeNoteID),
           notes.first(where: { $0.id == activeNoteID })?.workspaceID != activeWorkspaceID {
            self.activeNoteID = preferredActiveNoteID(in: activeWorkspaceID)
            transitionDeck(.collapsed)
        }
        persist()
    }

    @discardableResult
    func deleteWorkspace(_ id: NoteWorkspace.ID) -> Bool {
        guard id != defaultWorkspaceID,
              let index = workspaces.firstIndex(where: { $0.id == id }),
              workspaces.contains(where: { $0.id == defaultWorkspaceID }) else { return false }
        let workspace = workspaces.remove(at: index)
        let activeNoteIDs = notes.filter { $0.workspaceID == id }.map(\.id)
        let archivedNoteIDs = archivedNotes.filter { $0.workspaceID == id }.map(\.id)
        for noteIndex in notes.indices where notes[noteIndex].workspaceID == id {
            notes[noteIndex].workspaceID = defaultWorkspaceID
        }
        for noteIndex in archivedNotes.indices where archivedNotes[noteIndex].workspaceID == id {
            archivedNotes[noteIndex].workspaceID = defaultWorkspaceID
        }
        let wasActive = activeWorkspaceID == id
        if wasActive {
            activeWorkspaceID = defaultWorkspaceID
            activeNoteID = preferredActiveNoteID(in: defaultWorkspaceID)
            if let activeNoteID { rememberLastActiveNote(activeNoteID, in: defaultWorkspaceID) }
            transitionDeck(.collapsed)
        }
        let pending = PendingWorkspaceDeletion(
            id: UUID(),
            workspace: workspace,
            originalIndex: index,
            activeNoteIDs: activeNoteIDs,
            archivedNoteIDs: archivedNoteIDs,
            wasActive: wasActive,
            expiresAt: .now.addingTimeInterval(10)
        )
        pendingWorkspaceDeletions.append(pending)
        workspaceDeletionTasks[pending.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            self.finalizeWorkspaceDeletion(pending.id)
        }
        persist()
        return true
    }

    func undoLatestWorkspaceDeletion() {
        guard let id = pendingWorkspaceDeletions.last?.id else { return }
        undoWorkspaceDeletion(id)
    }

    func undoWorkspaceDeletion(_ deletionID: PendingWorkspaceDeletion.ID) {
        guard let pendingIndex = pendingWorkspaceDeletions.firstIndex(where: { $0.id == deletionID }) else { return }
        let pending = pendingWorkspaceDeletions.remove(at: pendingIndex)
        workspaceDeletionTasks.removeValue(forKey: deletionID)?.cancel()
        guard !workspaces.contains(where: { $0.id == pending.workspace.id }) else { return }
        workspaces.insert(pending.workspace, at: min(pending.originalIndex, workspaces.count))
        let activeIDs = Set(pending.activeNoteIDs)
        let archivedIDs = Set(pending.archivedNoteIDs)
        for noteIndex in notes.indices where activeIDs.contains(notes[noteIndex].id) {
            notes[noteIndex].workspaceID = pending.workspace.id
        }
        for noteIndex in archivedNotes.indices where archivedIDs.contains(archivedNotes[noteIndex].id) {
            archivedNotes[noteIndex].workspaceID = pending.workspace.id
        }
        if pending.wasActive {
            activeWorkspaceID = pending.workspace.id
            activeNoteID = preferredActiveNoteID(in: pending.workspace.id)
            if let activeNoteID { rememberLastActiveNote(activeNoteID, in: pending.workspace.id) }
        }
        persist()
    }

    func finalizeWorkspaceDeletion(_ deletionID: PendingWorkspaceDeletion.ID) {
        workspaceDeletionTasks.removeValue(forKey: deletionID)?.cancel()
        pendingWorkspaceDeletions.removeAll { $0.id == deletionID }
    }

    func collapseActive(keepDeckOpen: Bool = false) {
        isPreferencesPresented = false
        transitionDeck(.collapsed)
        if keepDeckOpen {
            restTask?.cancel()
        } else {
            scheduleRest()
        }
    }

    func presentSettings() {
        let alreadyPresented = isPreferencesPresented
        isPreferencesPresented = true
        if alreadyPresented { utilityWindowRequests.send(.settings) }
    }

    func presentLibrary() {
        let alreadyPresented = isLibraryPresented
        isLibraryPresented = true
        if alreadyPresented { utilityWindowRequests.send(.library) }
    }

    func presentWorkspaceManagement() {
        isWorkspaceManagementPresented = true
    }

    func presentTaskCenter() {
        let alreadyPresented = isTaskCenterPresented
        isTaskCenterPresented = true
        if alreadyPresented { utilityWindowRequests.send(.taskCenter) }
    }

    func presentQuickCapture() {
        isQuickCapturePresented = true
        isPreferencesPresented = false
        isLibraryPresented = false
        isTaskCenterPresented = false
    }

    @discardableResult
    func saveQuickCapture(title: String, body: String, language: AppLanguage) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty || !cleanBody.isEmpty else {
            isQuickCapturePresented = false
            return false
        }
        var note = DockNote(
            title: cleanTitle.isEmpty ? L10n.text(.newNote, language: language) : cleanTitle,
            body: cleanBody,
            workspaceID: activeWorkspaceID,
            colorHex: NotePalette.colors[0]
        )
        Self.synchronizeTasksAndAdvanceRecurrences(in: &note)
        notes.append(note)
        activeNoteID = note.id
        rememberLastActiveNote(note.id, in: activeWorkspaceID)
        transitionDeck(.collapsed)
        isQuickCapturePresented = false
        persist()
        return true
    }

    func presentOnDesktop(_ id: DockNote.ID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        if desktopNoteIDs.contains(id) {
            desktopNoteIDs.removeAll { $0 == id }
            if note.workspaceID == activeWorkspaceID {
                activeNoteID = id
                rememberLastActiveNote(id, in: activeWorkspaceID)
                transitionDeck(.noteReturnedFromDesktop(id))
            } else {
                transitionDeck(.collapsed)
            }
            return
        }
        desktopNoteIDs.append(id)
        activeNoteID = id
        transitionDeck(.noteMovedToDesktop)
    }

    func closeDesktopNote(_ id: DockNote.ID) {
        desktopNoteIDs.removeAll { $0 == id }
    }

    func handleOutsideClick(keepDeckOpen: Bool = false) {
        guard trackedDeckLabels.isEmpty else { return }
        isPreferencesPresented = false
        restTask?.cancel()
        restTask = nil
        transitionDeck(.outsideClick(
            keepOpen: keepDeckOpen,
            activeNotePinned: activeNote?.isPinned == true
        ))
    }

    func addNote(language: AppLanguage) {
        let note = DockNote(
            title: L10n.text(.newNote, language: language),
            workspaceID: activeWorkspaceID,
            colorHex: NotePalette.colors[0]
        )
        notes.append(note)
        activeNoteID = note.id
        rememberLastActiveNote(note.id, in: activeWorkspaceID)
        transitionDeck(.noteSelected(note.id))
        persist()
    }

    @discardableResult
    func importNotes(from urls: [URL]) throws -> Int {
        let imported = try urls.map(NoteFileTransfer.importNote)
        guard !imported.isEmpty else { return 0 }
        let startingIndex = notes.count
        let styled = imported.enumerated().map { offset, importedNote in
            var note = importedNote
            note.workspaceID = activeWorkspaceID
            let gradient = NotePalette.gradients[(startingIndex + offset) % NotePalette.gradients.count]
            note.colorHex = gradient.startHex
            note.gradientEndHex = gradient.endHex
            return note
        }
        notes.append(contentsOf: styled)
        activeNoteID = styled.last?.id
        if let activeNoteID { rememberLastActiveNote(activeNoteID, in: activeWorkspaceID) }
        persist()
        return styled.count
    }

    func exportNotes(
        _ notesToExport: [DockNote],
        to directory: URL,
        format: NoteExportFormat
    ) throws -> [URL] {
        try NoteFileTransfer.export(notesToExport, to: directory, format: format)
    }

    func updateTitle(_ title: String) { mutateActive { $0.title = title } }
    func updateBody(_ body: String) {
        mutateActive {
            $0.body = body
            $0.bodyRTF = nil
            Self.synchronizeTasksAndAdvanceRecurrences(in: &$0)
        }
    }
    func updateTitle(_ title: String, for noteID: DockNote.ID) { mutate(noteID) { $0.title = title } }
    func updateBody(_ body: String, for noteID: DockNote.ID) {
        mutate(noteID) {
            $0.body = body
            $0.bodyRTF = nil
            Self.synchronizeTasksAndAdvanceRecurrences(in: &$0)
        }
    }
    func updateRichBody(_ body: String, rtfData: Data?, for noteID: DockNote.ID) {
        mutate(noteID) {
            $0.body = body
            $0.bodyRTF = rtfData
            Self.synchronizeTasksAndAdvanceRecurrences(in: &$0)
        }
    }
    func appendBody(_ suffix: String, for noteID: DockNote.ID) {
        guard !suffix.isEmpty else { return }
        mutate(noteID) { note in
            let originalBody = note.body
            note.body += suffix
            note.bodyRTF = RichTextBody.appendingPlainText(
                suffix,
                to: originalBody,
                rtfData: note.bodyRTF
            )
            Self.synchronizeTasksAndAdvanceRecurrences(in: &note)
        }
    }
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
    func setDueDate(_ date: Date?, language: AppLanguage = .system) {
        guard let activeNoteID else { return }
        setDueDate(date, for: activeNoteID, language: language)
    }
    func setDueDate(_ date: Date?, for noteID: DockNote.ID, language: AppLanguage = .system) {
        mutate(noteID) { $0.dueDate = date }
    }
    func insertTask() {
        guard let activeNoteID else { return }
        insertTask(for: activeNoteID)
    }
    func insertTask(for noteID: DockNote.ID) {
        guard let note = note(id: noteID) else { return }
        let separator = note.body.isEmpty || note.body.hasSuffix("\n") ? "" : "\n"
        appendBody(separator + "☐ ", for: noteID)
    }

    @discardableResult
    func setChecklistItemCompleted(_ itemID: ChecklistItemID, completed: Bool) -> Bool {
        guard let note = note(id: itemID.noteID) else { return false }
        if completed,
           let taskIndex = Self.taskIndex(in: note, for: itemID),
           let recurrence = note.tasks[taskIndex].recurrence {
            let requestedOccurrence = itemID.occurrenceIndex ?? recurrence.currentOccurrenceIndex
            guard requestedOccurrence == recurrence.currentOccurrenceIndex else { return false }
            var advanced = false
            mutate(itemID.noteID) { note in
                note.tasks = ChecklistParser.synchronizedTasks(in: note)
                guard let resolvedIndex = Self.taskIndex(in: note, for: itemID) else { return }
                advanced = Self.advanceCurrentOccurrence(
                    in: &note,
                    taskIndex: resolvedIndex,
                    outcome: .completed
                )
            }
            return advanced
        }
        let source = note.body as NSString
        let markerRange = NSRange(location: itemID.markerUTF16Offset, length: 1)
        guard markerRange.location >= 0,
              NSMaxRange(markerRange) <= source.length else { return false }
        let marker = source.substring(with: markerRange)
        guard ChecklistParser.isChecklistMarker(marker) else { return false }
        let replacement = ChecklistParser.replacementMarker(for: marker, completed: completed)
        guard replacement != marker else { return true }
        let updatedBody = source.replacingCharacters(in: markerRange, with: replacement)
        let updatedRTF = RichTextBody.replacingCharacters(
            in: markerRange,
            with: replacement,
            body: note.body,
            rtfData: note.bodyRTF
        )
        mutate(itemID.noteID) {
            $0.body = updatedBody
            $0.bodyRTF = updatedRTF
            Self.synchronizeTasksAndAdvanceRecurrences(in: &$0)
        }
        return true
    }

    @discardableResult
    func setChecklistItemDueDate(_ itemID: ChecklistItemID, date: Date?) -> Bool {
        guard let note = note(id: itemID.noteID),
              ChecklistParser.items(in: note).contains(where: {
                  $0.id.markerUTF16Offset == itemID.markerUTF16Offset
                      && (itemID.taskID == nil || $0.id.taskID == itemID.taskID)
              }) else { return false }
        mutate(itemID.noteID) { note in
            note.tasks = ChecklistParser.synchronizedTasks(in: note)
            let index = Self.taskIndex(in: note, for: itemID)
            guard let index else { return }
            if var recurrence = note.tasks[index].recurrence,
               let occurrenceIndex = itemID.occurrenceIndex {
                if let date {
                    recurrence.setOverride(for: occurrenceIndex, dueDate: date)
                    note.tasks[index].recurrence = recurrence
                    if occurrenceIndex == recurrence.currentOccurrenceIndex {
                        note.tasks[index].dueDate = date
                    }
                }
            } else {
                note.tasks[index].dueDate = date
            }
        }
        return true
    }

    @discardableResult
    func updateChecklistItemText(_ itemID: ChecklistItemID, text: String) -> Bool {
        guard let note = note(id: itemID.noteID) else { return false }
        let source = note.body as NSString
        let contentStart = itemID.markerUTF16Offset + 1
        guard contentStart >= 1, contentStart <= source.length else { return false }
        let remaining = NSRange(location: contentStart, length: source.length - contentStart)
        let lineBreak = source.range(of: "\n", options: [], range: remaining)
        let markerPattern = try? NSRegularExpression(pattern: "[☐☑□✓]")
        let nextMarker = markerPattern?.firstMatch(in: note.body, range: remaining)?.range.location
        let lineEnd = lineBreak.location == NSNotFound ? source.length : lineBreak.location
        let contentEnd = min(lineEnd, nextMarker ?? source.length)
        let range = NSRange(location: contentStart, length: max(0, contentEnd - contentStart))
        let originalContent = source.substring(with: range)
        let leadingWhitespace = String(originalContent.prefix { $0 == " " || $0 == "\t" })
        var trailingWhitespace = String(originalContent.reversed().prefix {
            $0 == " " || $0 == "\t"
        }.reversed())
        if nextMarker != nil, trailingWhitespace.isEmpty { trailingWhitespace = " " }
        let replacement = leadingWhitespace
            + text.trimmingCharacters(in: .whitespacesAndNewlines)
            + trailingWhitespace
        let updatedBody = source.replacingCharacters(in: range, with: replacement)
        let updatedRTF = RichTextBody.replacingCharacters(
            in: range,
            with: replacement,
            body: note.body,
            rtfData: note.bodyRTF
        )
        mutate(itemID.noteID) {
            $0.body = updatedBody
            $0.bodyRTF = updatedRTF
            Self.synchronizeTasksAndAdvanceRecurrences(in: &$0)
        }
        return true
    }

    @discardableResult
    func setTaskRecurrence(
        _ itemID: ChecklistItemID,
        rule: TaskRecurrenceRule,
        startingAt date: Date
    ) -> Bool {
        var updated = false
        mutate(itemID.noteID) { note in
            note.tasks = ChecklistParser.synchronizedTasks(in: note)
            guard let index = Self.taskIndex(in: note, for: itemID) else { return }
            note.tasks[index].recurrence = TaskRecurrenceState(rule: rule, startingAt: date)
            note.tasks[index].dueDate = date
            note.tasks[index].isCompleted = false
            Self.replaceTaskMarkerIfNeeded(in: &note, taskIndex: index, completed: false)
            updated = true
        }
        return updated
    }

    @discardableResult
    func updateTaskRecurrenceSeries(
        _ itemID: ChecklistItemID,
        rule: TaskRecurrenceRule,
        startingAt date: Date
    ) -> Bool {
        var updated = false
        mutate(itemID.noteID) { note in
            note.tasks = ChecklistParser.synchronizedTasks(in: note)
            guard let index = Self.taskIndex(in: note, for: itemID) else { return }
            let oldHistory = note.tasks[index].recurrence?.history ?? []
            var recurrence = TaskRecurrenceState(rule: rule, startingAt: date)
            recurrence.history = oldHistory
            note.tasks[index].recurrence = recurrence
            note.tasks[index].dueDate = date
            note.tasks[index].isCompleted = false
            Self.replaceTaskMarkerIfNeeded(in: &note, taskIndex: index, completed: false)
            updated = true
        }
        return updated
    }

    @discardableResult
    func rescheduleTaskOccurrence(_ itemID: ChecklistItemID, to date: Date) -> Bool {
        setChecklistItemDueDate(itemID, date: date)
    }

    @discardableResult
    func skipTaskOccurrence(_ itemID: ChecklistItemID) -> Bool {
        var updated = false
        mutate(itemID.noteID) { note in
            note.tasks = ChecklistParser.synchronizedTasks(in: note)
            guard let index = Self.taskIndex(in: note, for: itemID),
                  var recurrence = note.tasks[index].recurrence else { return }
            let occurrenceIndex = itemID.occurrenceIndex ?? recurrence.currentOccurrenceIndex
            if occurrenceIndex == recurrence.currentOccurrenceIndex {
                updated = Self.advanceCurrentOccurrence(
                    in: &note,
                    taskIndex: index,
                    outcome: .skipped
                )
            } else {
                recurrence.skip(occurrenceIndex)
                note.tasks[index].recurrence = recurrence
                updated = true
            }
        }
        return updated
    }

    @discardableResult
    func stopTaskRecurrence(_ itemID: ChecklistItemID) -> Bool {
        var updated = false
        mutate(itemID.noteID) { note in
            note.tasks = ChecklistParser.synchronizedTasks(in: note)
            guard let index = Self.taskIndex(in: note, for: itemID),
                  note.tasks[index].recurrence != nil else { return }
            note.tasks[index].recurrence = nil
            updated = true
        }
        return updated
    }
    func updateBodyWithDictation(base: String, transcript: String) {
        guard let activeNoteID else { return }
        updateBodyWithDictation(base: base, transcript: transcript, for: activeNoteID)
    }
    func updateBodyWithDictation(base: String, transcript: String, for noteID: DockNote.ID) {
        guard let current = note(id: noteID)?.body else { return }
        let effectiveBase = current == base ? base : current
        let separator = effectiveBase.isEmpty || effectiveBase.hasSuffix("\n") ? "" : "\n"
        appendBody(separator + transcript, for: noteID)
    }
    func togglePinned() { mutateActive { $0.isPinned.toggle() } }
    func togglePinned(_ noteID: DockNote.ID) { mutate(noteID) { $0.isPinned.toggle() } }

    func archiveActive() {
        guard let activeNoteID else { return }
        archive(activeNoteID)
    }

    func archive(
        _ noteID: DockNote.ID,
        obsidianDirectory: URL? = nil,
        obsidianBackupEnabled: Bool = false
    ) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        var note = notes.remove(at: index)
        note.isArchived = true
        note.modifiedAt = .now
        if obsidianBackupEnabled {
            if let obsidianDirectory {
                do {
                    lastObsidianBackupURL = try ObsidianArchiveExporter.export(note, to: obsidianDirectory)
                    lastObsidianBackupError = nil
                } catch {
                    lastObsidianBackupURL = nil
                    lastObsidianBackupError = .writeFailed(error.localizedDescription)
                }
            } else {
                lastObsidianBackupURL = nil
                lastObsidianBackupError = .missingFolder
            }
        }
        archivedNotes.insert(note, at: 0)
        desktopNoteIDs.removeAll { $0 == noteID }
        clearLastActiveNote(noteID, in: note.workspaceID)
        if activeNoteID == noteID {
            activeNoteID = preferredActiveNoteID(in: activeWorkspaceID)
            dismissDeck()
        }
        persist()
    }

    func restoreArchived(_ id: DockNote.ID, language: AppLanguage = .system) {
        guard let index = archivedNotes.firstIndex(where: { $0.id == id }) else { return }
        var note = archivedNotes.remove(at: index)
        note.isArchived = false
        if note.workspaceID.flatMap({ workspace(id: $0) }) == nil {
            note.workspaceID = defaultWorkspaceID
        }
        note.modifiedAt = .now
        notes.append(note)
        persist()
    }

    func openFromLibrary(_ id: DockNote.ID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        isLibraryPresented = false
        select(id)
    }

    func openFromTaskCenter(_ id: DockNote.ID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        isTaskCenterPresented = false
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
        if let index = archivedNotes.firstIndex(where: { $0.id == noteID }) {
            let note = archivedNotes.remove(at: index)
            enqueueDeletion(
                note: note,
                collection: .archived,
                originalIndex: index,
                wasActive: false,
                wasOnDesktop: false,
                previousDeckState: deckState
            )
            persist()
            return
        }
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let note = notes.remove(at: index)
        let wasActive = activeNoteID == noteID
        let wasOnDesktop = desktopNoteIDs.contains(noteID)
        let previousDeckState = deckState
        desktopNoteIDs.removeAll { $0 == noteID }
        clearLastActiveNote(noteID, in: note.workspaceID)
        if wasActive {
            activeNoteID = preferredActiveNoteID(in: activeWorkspaceID)
            if let activeNoteID {
                transitionDeck(.noteSelected(activeNoteID))
            } else {
                dismissDeck()
            }
        }
        enqueueDeletion(
            note: note,
            collection: .active,
            originalIndex: index,
            wasActive: wasActive,
            wasOnDesktop: wasOnDesktop,
            previousDeckState: previousDeckState
        )
        persist()
    }

    func undoLatestDeletion(language: AppLanguage = .system) {
        guard let id = pendingDeletions.last?.id else { return }
        undoDeletion(id, language: language)
    }

    func undoDeletion(_ deletionID: PendingDeletion.ID, language: AppLanguage = .system) {
        guard let pendingIndex = pendingDeletions.firstIndex(where: { $0.id == deletionID }) else { return }
        let pending = pendingDeletions.remove(at: pendingIndex)
        deletionTasks.removeValue(forKey: deletionID)?.cancel()
        switch pending.collection {
        case .active:
            var note = pending.note
            note.isArchived = false
            notes.insert(note, at: min(pending.originalIndex, notes.count))
            if pending.wasOnDesktop, !desktopNoteIDs.contains(note.id) {
                desktopNoteIDs.append(note.id)
            }
            if pending.wasActive {
                if let workspaceID = note.workspaceID,
                   workspaces.contains(where: { $0.id == workspaceID }) {
                    activeWorkspaceID = workspaceID
                    rememberLastActiveNote(note.id, in: workspaceID)
                }
                activeNoteID = note.id
                if pending.wasOnDesktop {
                    transitionDeck(.noteMovedToDesktop)
                } else if pending.previousDeckState.openNoteID == note.id {
                    transitionDeck(.noteSelected(note.id))
                } else if pending.previousDeckState == .resting {
                    transitionDeck(.dismissed)
                } else {
                    transitionDeck(.collapsed)
                }
            }
        case .archived:
            var note = pending.note
            note.isArchived = true
            archivedNotes.insert(note, at: min(pending.originalIndex, archivedNotes.count))
        }
        persist()
    }

    func finalizeDeletion(_ deletionID: PendingDeletion.ID) {
        deletionTasks.removeValue(forKey: deletionID)?.cancel()
        pendingDeletions.removeAll { $0.id == deletionID }
    }

    func finalizeAllPendingDeletions() {
        for task in deletionTasks.values { task.cancel() }
        deletionTasks.removeAll()
        pendingDeletions.removeAll()
        for task in workspaceDeletionTasks.values { task.cancel() }
        workspaceDeletionTasks.removeAll()
        pendingWorkspaceDeletions.removeAll()
    }

    private func enqueueDeletion(
        note: DockNote,
        collection: NoteCollection,
        originalIndex: Int,
        wasActive: Bool,
        wasOnDesktop: Bool,
        previousDeckState: DeckState
    ) {
        let pending = PendingDeletion(
            id: UUID(),
            note: note,
            collection: collection,
            originalIndex: originalIndex,
            wasActive: wasActive,
            wasOnDesktop: wasOnDesktop,
            previousDeckState: previousDeckState,
            expiresAt: .now.addingTimeInterval(10)
        )
        pendingDeletions.append(pending)
        deletionTasks[pending.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            self.finalizeDeletion(pending.id)
        }
    }

    private func mutateActive(_ mutation: (inout DockNote) -> Void) {
        guard let activeNoteID else { return }
        mutate(activeNoteID, mutation)
    }

    private func mutate(_ noteID: DockNote.ID, _ mutation: (inout DockNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        mutation(&notes[index])
        notes[index].modifiedAt = .now
        schedulePersist()
    }

    private func preferredActiveNoteID(in workspaceID: NoteWorkspace.ID) -> DockNote.ID? {
        let preferred = workspace(id: workspaceID)?.lastActiveNoteID
        return preferred.flatMap { preferred in
            notes.first(where: { $0.id == preferred && $0.workspaceID == workspaceID })?.id
        } ?? notes.first(where: { $0.workspaceID == workspaceID })?.id
    }

    private func rememberLastActiveNote(_ noteID: DockNote.ID, in workspaceID: NoteWorkspace.ID) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        workspaces[index].lastActiveNoteID = noteID
    }

    private func clearLastActiveNote(_ noteID: DockNote.ID, in workspaceID: NoteWorkspace.ID?) {
        guard let workspaceID,
              let index = workspaces.firstIndex(where: { $0.id == workspaceID }),
              workspaces[index].lastActiveNoteID == noteID else { return }
        workspaces[index].lastActiveNoteID = notes.first(where: { $0.workspaceID == workspaceID })?.id
    }

    private static func taskIndex(in note: DockNote, for itemID: ChecklistItemID) -> Int? {
        itemID.taskID.flatMap { taskID in
            note.tasks.firstIndex { $0.id == taskID }
        } ?? note.tasks.firstIndex { $0.sourceUTF16Offset == itemID.markerUTF16Offset }
    }

    private static func synchronizeTasksAndAdvanceRecurrences(
        in note: inout DockNote,
        completedAt: Date = .now,
        calendar: Calendar = .current
    ) {
        note.tasks = ChecklistParser.synchronizedTasks(in: note)
        let completedRecurringIndices = note.tasks.indices.filter {
            note.tasks[$0].isCompleted && note.tasks[$0].recurrence != nil
        }
        for taskIndex in completedRecurringIndices {
            _ = advanceCurrentOccurrence(
                in: &note,
                taskIndex: taskIndex,
                outcome: .completed,
                recordedAt: completedAt,
                calendar: calendar
            )
        }
    }

    @discardableResult
    private static func advanceCurrentOccurrence(
        in note: inout DockNote,
        taskIndex: Int,
        outcome: TaskOccurrenceOutcome,
        recordedAt: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard note.tasks.indices.contains(taskIndex),
              var recurrence = note.tasks[taskIndex].recurrence else { return false }
        let occurrenceIndex = recurrence.currentOccurrenceIndex
        guard let scheduledDate = recurrence.scheduledDate(
            for: occurrenceIndex,
            calendar: calendar
        ) else { return false }
        let effectiveDueDate = note.tasks[taskIndex].dueDate
            ?? recurrence.effectiveDate(for: occurrenceIndex, calendar: calendar)
            ?? scheduledDate

        if outcome == .skipped { recurrence.skip(occurrenceIndex) }
        if !recurrence.history.contains(where: {
            $0.occurrenceIndex == occurrenceIndex && $0.outcome == outcome
        }) {
            recurrence.history.append(TaskOccurrenceRecord(
                occurrenceIndex: occurrenceIndex,
                scheduledDate: scheduledDate,
                effectiveDueDate: effectiveDueDate,
                recordedAt: recordedAt,
                outcome: outcome
            ))
        }
        guard let nextIndex = recurrence.nextActiveOccurrenceIndex(after: occurrenceIndex),
              let nextDueDate = recurrence.effectiveDate(for: nextIndex, calendar: calendar) else {
            return false
        }
        recurrence.currentOccurrenceIndex = nextIndex
        note.tasks[taskIndex].recurrence = recurrence
        note.tasks[taskIndex].dueDate = nextDueDate
        note.tasks[taskIndex].isCompleted = false
        replaceTaskMarkerIfNeeded(in: &note, taskIndex: taskIndex, completed: false)
        return true
    }

    private static func replaceTaskMarkerIfNeeded(
        in note: inout DockNote,
        taskIndex: Int,
        completed: Bool
    ) {
        guard note.tasks.indices.contains(taskIndex),
              let markerOffset = note.tasks[taskIndex].sourceUTF16Offset else { return }
        let source = note.body as NSString
        let markerRange = NSRange(location: markerOffset, length: 1)
        guard markerOffset >= 0, NSMaxRange(markerRange) <= source.length else { return }
        let marker = source.substring(with: markerRange)
        guard ChecklistParser.isChecklistMarker(marker) else { return }
        let replacement = ChecklistParser.replacementMarker(for: marker, completed: completed)
        guard replacement != marker else { return }
        note.bodyRTF = RichTextBody.replacingCharacters(
            in: markerRange,
            with: replacement,
            body: note.body,
            rtfData: note.bodyRTF
        )
        note.body = source.replacingCharacters(in: markerRange, with: replacement)
    }

    private func transitionDeck(_ event: DeckEvent) {
        let nextState = DeckTransition.reduce(deckState, event: event)
        if nextState != deckState { deckState = nextState }
    }

    func persist() {
        let generation = beginSave()
        writeCurrentSnapshot(generation: generation)
    }

    func flushPendingSave() {
        guard case .saving = saveState else { return }
        saveTask?.cancel()
        saveTask = nil
        writeCurrentSnapshot(generation: saveGeneration)
    }

    func retrySave() {
        persist()
    }

    private func schedulePersist() {
        let generation = beginSave()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let self else { return }
            self.writeCurrentSnapshot(generation: generation)
        }
    }

    private func beginSave() -> UInt64 {
        saveTask?.cancel()
        saveTask = nil
        saveGeneration &+= 1
        saveState = .saving
        return saveGeneration
    }

    private func writeCurrentSnapshot(generation: UInt64) {
        guard generation == saveGeneration else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(currentDocument)
            try writeData(data, fileURL)
            try? writeData(data, backupURL)
            saveTask = nil
            saveState = .saved(.now)
        } catch {
            saveTask = nil
            saveState = .failed(error.localizedDescription)
        }
    }

    private var currentDocument: DockNotesDocument {
        DockNotesDocument(
            activeWorkspaceID: activeWorkspaceID,
            defaultWorkspaceID: defaultWorkspaceID,
            workspaces: workspaces,
            notes: notes + archivedNotes
        )
    }

    private func scheduleRest() {
        restTask?.cancel()
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.trackedDeckLabels.isEmpty, self.deckState == .fanned else { return }
                self.transitionDeck(.automaticRest)
                self.restTask = nil
            }
        }
    }
}
