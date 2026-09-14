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
        preferredVisibleCount: Int = defaultVisibleTabs,
        excludedNoteIDs: Set<UUID> = []
    ) -> DeckPlan {
        let desiredVisibleCount = capacity(for: availableHeight, preferredVisibleCount: preferredVisibleCount)
        let physicalSlotCount = capacity(
            for: availableHeight,
            preferredVisibleCount: maximumVisibleTabs
        )
        // Slots correspond to the canonical note order. A note detached to the
        // desktop reserves its former slot instead of making every later tab
        // jump upward. When vertical space remains, later notes fill additional
        // slots so "Visible Tabs" still counts actual collapsed labels.
        var slottedNotes: [DockNote] = []
        var visibleCount = 0
        for note in notes where slottedNotes.count < physicalSlotCount {
            slottedNotes.append(note)
            let hidden = excludedNoteIDs.contains(note.id)
                || (isExpanded && note.id == activeNoteID)
            if !hidden { visibleCount += 1 }
            if visibleCount == desiredVisibleCount { break }
        }
        let slots = slottedNotes.map { note -> UUID? in
            if excludedNoteIDs.contains(note.id) { return nil }
            return isExpanded && note.id == activeNoteID ? nil : note.id
        }
        let overflowIDs = notes
            .dropFirst(slottedNotes.count)
            .filter {
                !excludedNoteIDs.contains($0.id)
                    && !(isExpanded && $0.id == activeNoteID)
            }
            .map(\.id)
        return DeckPlan(slots: slots, overflowIDs: overflowIDs)
    }
}
