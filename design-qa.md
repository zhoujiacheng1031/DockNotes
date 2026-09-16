# DockNotes Stacked Edge Tabs — Design QA

## Evidence

- Source visual truth: `/private/var/folders/5y/z4zf9kqs7q9b6r0dxj3t00840000gn/T/codex-clipboard-6efddc85-7bc4-4bf2-bd0a-23907547631b.png`
- Final implementation capture: `/private/tmp/docknotes-stacked-deck-final4.png`
- Combined comparison: `/private/tmp/docknotes-design-comparison-final-v2.png`
- State: expanded right-edge deck, light appearance, four visible notes plus overflow and utility controls.
- Source pixels: 106 × 810; source density is unknown and was normalized to 105 × 800 for comparison.
- Implementation pixels: 120 × 1600, representing a 60 × 800 point SwiftUI surface rendered at 2×; normalized to 60 × 800.
- Viewport: `DeckWindowView`, 60 × 800 points.

## Full-view comparison evidence

The final side-by-side comparison shows that both designs use a roughly 48-point paper strip, long vertical titles, rounded free-edge corners, a flush screen edge, soft shadow, and small alternating angles. DockNotes intentionally shows four notes and its existing overflow/add/library/settings controls, while the reference crop shows three notes and only part of an add control.

## Focused region evidence

The full implementation capture is already a focused component-only capture at 2× density. Titles, deadline capsules, seams, corners, shadows, and overlap boundaries are legible at original size, so a second crop would not add evidence.

## Comparison history

### Iteration 1 — blocked

- [P1] The first implementation used 48 × 126 point tabs with a fixed 96-point pitch. In the normalized comparison they read as short cards rather than the reference's long paper labels.
- [P1] Icon, title, and deadline shared too little length, causing early title truncation.
- Fix: increased the visible label to 48 × 190 points and introduced an adaptive pitch: four labels retain airy spacing while five to seven labels compress into a denser stack without shrinking the labels.

### Iteration 2 — blocked

- [P2] Several gradient endpoints were darker and more saturated than the pastel reference, reducing title contrast.
- [P2] SwiftUI's semantic black resolved inconsistently in the offscreen render on rotated labels.
- Fix: added a restrained white wash to the existing user-selected gradient, increased the free-edge radius, and used device-space AppKit ink color for deterministic dark typography.

### Final iteration

- No actionable P0, P1, or P2 mismatch remains.
- Remaining P3: the reference uses a more condensed handwritten display face. DockNotes retains the rounded system font for Chinese/English consistency and reliable truncation.
- Intentional deviation: DockNotes retains compact deadline capsules because reminders are an existing product requirement absent from the visual reference. Decorative classification icons were removed to match the reference and preserve title length.

## Required fidelity surfaces

- Fonts and typography: vertical orientation, weight, size, one-line truncation, and dark ink now match the reference hierarchy. The exact display family remains a documented P3 deviation.
- Spacing and layout rhythm: 48-point width, 190-point length, adaptive overlap, alternating 0.9–2 degree tilt, rounded free edge, seam, and control clearance pass.
- Colors and visual tokens: existing note gradients remain user-controlled but receive a light paper wash for the reference's pastel character and readable black text.
- Image quality and asset fidelity: the source contains no raster illustration, logo, or custom icon asset. Native SF Symbols are retained for functional app controls; no placeholder imagery is used.
- Copy and content: real note titles, localized deadline values, overflow count, and existing actions remain intact. Four-tab and seven-tab live states both keep titles in the exposed part of each stacked label.

## Interaction verification

- Dynamic pitch is shared by slot positioning, drag targeting, adjacent-tab preview motion, and drop settling.
- Self-checks cover four-tab defaults, seven-tab capacity, alternating tilt, stack height, drag target bounds, and residual drop positioning.
- The live seven-tab state was expanded in the packaged application and verified to keep each label's title in its visible segment while retaining deadline display.
- The application builds successfully and all DockNotes self-checks pass.

## Follow-up polish

- P3: consider an optional condensed display font for edge labels if a future typography pass can preserve CJK and English coverage.

final result: passed
