import Foundation

struct DeckPlan: Equatable {
    let slots: [UUID?]
    let overflowIDs: [UUID]
}

enum DeckLayout {
    static let tabHeight: CGFloat = 96
    static let controlsHeight: CGFloat = 118
    static let maximumVisibleTabs = 7
    static let defaultVisibleTabs = 4
    static let windowWidth: CGFloat = 40
    static let tabWidth: CGFloat = 32

    static func dragPreviewOffset(for slot: Int, sourceSlot: Int, targetSlot: Int) -> CGFloat {
        if sourceSlot < targetSlot, slot > sourceSlot, slot <= targetSlot {
            return -tabHeight
        }
        if sourceSlot > targetSlot, slot >= targetSlot, slot < sourceSlot {
            return tabHeight
        }
        return 0
    }

    static func dragTarget(sourceSlot: Int, translation: CGFloat, slotCount: Int) -> Int {
        guard slotCount > 0 else { return 0 }
        let shift = Int((translation / tabHeight).rounded())
        return min(max(sourceSlot + shift, 0), slotCount - 1)
    }

    static func dragResidual(originSlot: Int, currentSlot: Int, translation: CGFloat) -> CGFloat {
        translation - CGFloat(currentSlot - originSlot) * tabHeight
    }

    static func capacity(for availableHeight: CGFloat, preferredVisibleCount: Int = defaultVisibleTabs) -> Int {
        let preferred = min(max(preferredVisibleCount, 1), maximumVisibleTabs)
        return min(preferred, max(1, Int((availableHeight - controlsHeight) / tabHeight)))
    }

    static func plan(
        notes: [DockNote],
        activeNoteID: UUID?,
        isExpanded: Bool,
        availableHeight: CGFloat,
        preferredVisibleCount: Int = defaultVisibleTabs
    ) -> DeckPlan {
        let capacity = capacity(for: availableHeight, preferredVisibleCount: preferredVisibleCount)
        let slottedNotes = Array(notes.prefix(capacity))
        let slots = slottedNotes.map { note -> UUID? in
            isExpanded && note.id == activeNoteID ? nil : note.id
        }
        let overflowIDs = notes
            .dropFirst(capacity)
            .filter { !(isExpanded && $0.id == activeNoteID) }
            .map(\.id)
        return DeckPlan(slots: slots, overflowIDs: overflowIDs)
    }
}
