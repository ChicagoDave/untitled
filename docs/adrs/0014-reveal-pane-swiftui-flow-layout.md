# ADR-0014 — The reveal pane renders as a SwiftUI flow layout

> **Superseded by [ADR-0030](0030-reveal-codes-is-a-co-equal-editing-surface.md).** An editable, shared-caret Reveal Codes surface requires a real text-editing view; the `FlowLayout` of `Text`+chips is replaced by a TextKit surface. The pure projection/view-model mappings are retained.

## Context

Build step 2, Phase 4 builds the reveal pane ([ADR-0006](0006-reveal-is-a-projection-and-slicing-surface.md))
— a truth view over the `revealProjection` token stream that doubles as the
chapter-slicing surface. The hard constraint: in chapter-edit mode each
`[Chapter]` chip and each candidate cut point must be an *individually
interactive* control (toggle / retitle / move / remove), not inert glyphs. Three
renderers were weighed: a SwiftUI flow of views, a custom `NSView` with manual
hit-testing, or a non-editable `NSTextView` with the chips as text attachments.

## Decision

Render the reveal stream as a **SwiftUI flow layout** (`FlowLayout: Layout`) of
per-token views — prose as `Text`, codes as colored capsule chips. The pure
view-model mapping lives in `UntitledShell` (`revealItems(from:)`,
`chapterAnchors(of:)`) and is unit-tested headless; the SwiftUI views consume it.
Chapter-slicing is a list of `ChapterAnchor` rows (one per block) with a cut
toggle and a title field, editing the overlay through `DocumentModel` →
`Document.placeChapterCut` / `removeChapterCut` / `moveChapterCut` /
`setChapterCutTitle`.

## Consequences

- Chips and anchor rows are first-class SwiftUI views, so selection, toggling,
  titling, and (later) drag come from the framework rather than hand-rolled
  hit-testing.
- The reveal pane shares no machinery with the TextKit 2 editor — the two
  surfaces stay independent, as ADR-0006 anticipated ("must mode-switch
  cleanly").
- The token → item and block → anchor mappings are pure and tested; only the view
  composition and the live chapter edits are AppKit/SwiftUI glue, covered by a
  manual smoke check (place/retitle/remove a cut, save, reopen — the cut survives
  via the sidecar).
- Phase 4 scope: cuts are placed at block boundaries via toggles (a move is a
  remove-then-place). Drag-to-reposition a chip and mid-block cut placement are
  deferred refinements; the model already supports mid-block cuts (it is the UI
  that is boundary-only for now).
- Whole-stream re-projection on each model change is fine at a scene's scale.

## Session

6baa7e (2026-06-05) — Build step 2, Phase 4.
