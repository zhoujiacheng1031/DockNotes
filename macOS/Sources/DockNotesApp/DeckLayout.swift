import Foundation

struct DeckPlan: Equatable {
    let slots: [UUID?]
    let overflowIDs: [UUID]
}

enum DeckLayout {
    /// The visible paper tab stays long. Its pitch expands when only a few
    /// notes are visible and compresses into a denser stack as the user asks
    /// for more slots.
    static let tabHeight: CGFloat = 92
    static let preferredTabPitch: CGFloat = 154
    static let tabVisualHeight: CGFloat = 190
    static let controlsHeight: CGFloat = 150
    static let maximumVisibleTabs = 7
    static let defaultVisibleTabs = 4
    static let windowWidth: CGFloat = 60
    static let tabWidth: CGFloat = 48
    /// Keep the resting wake target flush with the screen edge. The visible
    /// indicator is wider, but hovering it before reaching the edge should not
    /// fan the deck open.
    static let restingActivationWidth: CGFloat = 2

    static var tabOverlap: CGFloat { tabVisualHeight - preferredTabPitch }

    static func tabPitch(for availableHeight: CGFloat, slotCount: Int) -> CGFloat {
        guard slotCount > 1 else { return preferredTabPitch }
        let fitted = (availableHeight - controlsHeight - tabVisualHeight) / CGFloat(slotCount - 1)
        return min(preferredTabPitch, max(tabHeight, fitted))
    }

    static func tabStackHeight(slotCount: Int, pitch: CGFloat) -> CGFloat {
        guard slotCount > 0 else { return 0 }
        return CGFloat(slotCount - 1) * pitch + tabVisualHeight
    }

    static func tiltDegrees(for slot: Int) -> Double {
        let pattern = [2.0, -1.25, 1.1, -1.7, 1.45, -0.9, 1.8]
        return pattern[abs(slot) % pattern.count]
    }

    static func dragPreviewOffset(
        for slot: Int,
        sourceSlot: Int,
        targetSlot: Int,
        pitch: CGFloat = tabHeight
    ) -> CGFloat {
        if sourceSlot < targetSlot, slot > sourceSlot, slot <= targetSlot {
            return -pitch
        }
        if sourceSlot > targetSlot, slot >= targetSlot, slot < sourceSlot {
            return pitch
        }
        return 0
    }

    static func dragTarget(
        sourceSlot: Int,
        translation: CGFloat,
        slotCount: Int,
        pitch: CGFloat = tabHeight
    ) -> Int {
        guard slotCount > 0 else { return 0 }
        let shift = Int((translation / pitch).rounded())
        return min(max(sourceSlot + shift, 0), slotCount - 1)
    }

    static func dragResidual(
        originSlot: Int,
        currentSlot: Int,
        translation: CGFloat,
        pitch: CGFloat = tabHeight
    ) -> CGFloat {
        translation - CGFloat(currentSlot - originSlot) * pitch
    }

    static func capacity(for availableHeight: CGFloat, preferredVisibleCount: Int = defaultVisibleTabs) -> Int {
        let preferred = min(max(preferredVisibleCount, 1), maximumVisibleTabs)
        let availableSteps = max(0, availableHeight - controlsHeight - tabVisualHeight)
        let feasible = Int(availableSteps / tabHeight) + 1
        return min(preferred, max(1, feasible))
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

enum EdgeTabLayout {
    /// Content is intentionally independent from the overlap pitch. Every tab
    /// therefore keeps the same title baseline when the visible-tab setting
    /// changes between the airy and dense stack layouts.
    static let titleContentLength: CGFloat = 60
    static let deadlineContentLength: CGFloat = 36
    /// About two CJK glyphs at the tab title's 11-point size.
    static let contentTopInset: CGFloat = 23
    static let deadlineTopInset: CGFloat = 3

}
