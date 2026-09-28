import Carbon
import Foundation

final class GlobalShortcutManager: @unchecked Sendable {
    enum Action: UInt32 {
        case quickCapture = 1
        case newNote = 2
        case workspace1 = 101
        case workspace2 = 102
        case workspace3 = 103
        case workspace4 = 104
        case workspace5 = 105
        case workspace6 = 106
        case workspace7 = 107
        case workspace8 = 108
        case workspace9 = 109

        var workspaceIndex: Int? {
            guard rawValue >= Self.workspace1.rawValue,
                  rawValue <= Self.workspace9.rawValue else { return nil }
            return Int(rawValue - Self.workspace1.rawValue)
        }
    }

    var onQuickCapture: () -> Void = {}
    var onNewNote: () -> Void = {}
    var onWorkspaceShortcut: (Int) -> Void = { _ in }

    private static let signature: OSType = 0x444E4F54 // DNOT
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [Action: EventHotKeyRef] = [:]
    private(set) var lastRegistrationStatuses: (quickCapture: OSStatus, newNote: OSStatus)?

    init() {}

    private func installHandlerIfNeeded() -> Bool {
        if eventHandler != nil { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == GlobalShortcutManager.signature,
                      let action = Action(rawValue: hotKeyID.id) else { return status }
                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    if let workspaceIndex = action.workspaceIndex {
                        manager.onWorkspaceShortcut(workspaceIndex)
                        return
                    }
                    switch action {
                    case .quickCapture: manager.onQuickCapture()
                    case .newNote: manager.onNewNote()
                    case .workspace1, .workspace2, .workspace3, .workspace4, .workspace5,
                         .workspace6, .workspace7, .workspace8, .workspace9:
                        break
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        return status == noErr && eventHandler != nil
    }

    @discardableResult
    func register(shortcut: QuickCaptureShortcut) -> Bool {
        guard installHandlerIfNeeded() else { return false }
        unregisterHotKeys()
        let quickStatus = register(
            action: .quickCapture,
            keyCode: UInt32(kVK_Space),
            modifiers: modifiers(for: shortcut)
        )
        let newNoteStatus = register(
            action: .newNote,
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(cmdKey | optionKey)
        )
        let workspaceActions: [Action] = [
            .workspace1, .workspace2, .workspace3, .workspace4, .workspace5,
            .workspace6, .workspace7, .workspace8, .workspace9
        ]
        let workspaceKeyCodes: [UInt32] = [
            UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
            UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9)
        ]
        let workspaceStatuses = zip(workspaceActions, workspaceKeyCodes).map { action, keyCode in
            register(action: action, keyCode: keyCode, modifiers: UInt32(cmdKey | optionKey))
        }
        lastRegistrationStatuses = (quickStatus, newNoteStatus)
        return quickStatus == noErr
            && newNoteStatus == noErr
            && workspaceStatuses.allSatisfy { $0 == noErr }
    }

    func stop() {
        unregisterHotKeys()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    /// Sends the same Carbon event produced by a registered global hot key.
    /// Used by the executable self-check to verify the handler and callback,
    /// not just successful registration with the window server.
    func dispatchForTesting(_ action: Action) -> OSStatus {
        guard installHandlerIfNeeded() else { return OSStatus(eventInternalErr) }
        var event: EventRef?
        let createStatus = CreateEvent(
            nil,
            OSType(kEventClassKeyboard),
            UInt32(kEventHotKeyPressed),
            GetCurrentEventTime(),
            0,
            &event
        )
        guard createStatus == noErr, let event else { return createStatus }
        defer { ReleaseEvent(event) }

        var hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let parameterStatus = SetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size,
            &hotKeyID
        )
        guard parameterStatus == noErr else { return parameterStatus }
        return SendEventToEventTarget(event, GetApplicationEventTarget())
    }

    private func register(action: Action, keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: action.rawValue),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference { hotKeys[action] = reference }
        return status
    }

    private func unregisterHotKeys() {
        for reference in hotKeys.values { UnregisterEventHotKey(reference) }
        hotKeys.removeAll()
    }

    private func modifiers(for shortcut: QuickCaptureShortcut) -> UInt32 {
        switch shortcut {
        case .shiftCommandSpace: UInt32(cmdKey | shiftKey)
        case .optionCommandSpace: UInt32(cmdKey | optionKey)
        case .controlOptionSpace: UInt32(controlKey | optionKey)
        }
    }
}
