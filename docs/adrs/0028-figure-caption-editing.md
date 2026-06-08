# ADR-0028 — Figure captions are edited inline in the editor

## Context

A figure block ([ADR-0027](0027-figure-block-shape-and-serialization.md)) renders in the editor as a placeholder: a non-editable box (an `NSTextAttachment`, the LT3 delete-prompt-chip technique) showing an image icon + the `imageRef`, plus the caption. The caption is writer-authored text; the question is whether it is editable *in the editor* or only set at insert time.

Two options:
- **Option A** — the caption is a plain-text editable segment shown beneath the placeholder box; the writer edits it in place, routed through a new pure reducer arm `InputEvent.setFigureCaption(blockID:caption:)`. Requires an editable `EditorLayout` segment mapped to the figure block's ID.
- **Option B** — the caption is non-editable in v1, set only at insert and changed by re-inserting or hand-editing the prose marker.

## Decision

**Option A — the caption is editable inline.** Picking a figure from the palette inserts the placeholder and drops the caret into an editable caption segment; typing routes to `setFigureCaption(blockID:caption:)` (pure, total — unknown or non-figure block ⇒ document unchanged), exactly as a chapter title's caret/segment routes to `setCutTitle` (LT3). Arrow keys glide past the non-editable placeholder box, as they glide past chapter headings and scene breaks.

Option B was rejected on the [ADR-0023](0023-insert-block-reducer-op-for-the-palette.md) "real, editable block" promise: the palette's job is to insert a block the writer can immediately engage from the keyboard. A figure whose caption is non-editable is a block the caret cannot enter *at all* — the same defect that kept empty set-pieces out of the palette (ADR-0023). Option A gives the inserted figure a genuine keyboard-reachable surface, keeping the palette's promise intact. (This was plan-review tension #2 on the LT4 plan.)

## Consequences

- The figure placeholder behaves like a chapter heading: a non-editable decoration (the box) plus an editable text field (the caption) anchored to the block ID. `EditorLayout` emits a non-editable attachment segment and an editable caption segment for a figure; `InputController` routes caption keystrokes through `setFigureCaption`. The caret never rests in the placeholder box itself.
- The reducer's public surface grows by one case (`setFigureCaption`), pure and headlessly testable (replaces caption / no-op on unknown or non-figure block / empty caption valid) — the same shape as the other LT3 arms.
- `imageRef` editing is **not** in v1 scope here: the writer sets the reference by placing the file in `images/` and supplying the name; an in-editor ref editor or file picker is deferred (ADR-0027). Only the caption is inline-editable.
- Consistency: title-like inline editing now appears in two places (chapter headings, figure captions) over the same `EditorLayout` editable-segment + per-block-ID reducer-arm pattern, so the mechanism is reused, not reinvented.

## Session

LT4-1 (2026-06-07) — decision recorded before code (the `setFigureCaption` arm and the editable caption segment land in LT4-2). Driven by the ADR-0023 editable-block promise.
