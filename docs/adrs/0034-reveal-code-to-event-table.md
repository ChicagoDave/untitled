# ADR-0034 — The reveal code→`InputEvent` reverse-mapping table

## Context

[ADR-0030](0030-reveal-codes-is-a-co-equal-editing-surface.md) requires the Reveal Codes surface to be **live and bidirectional**: deleting a code drops its formatting in the document instantly, paired codes delete together, and typing inserts text — all by writing the *same* `InputEvent`s against the *same* `WorkspaceDocument` as the prose editor. [ADR-0032](0032-reveal-surface-architecture.md) built the read side (`RevealController` renders `revealSegments(of:)`, shares the caret). LT5-1 left `RevealController`'s editing entry points (`insertText`/`deleteBackward`/…) as deliberate no-ops.

ADR-0030 fixed the rule: "each atomic code edit must map to an existing `InputEvent` where one exists; new core ops are added only where none fits." This ADR is that table — enumerated before any editing code, so the seam is designed once rather than discovered per-keystroke. The reducer (`applyInput`, `Input.swift`) and its events (`InputEvent.swift`) are the target vocabulary; `CodeID` (`RevealToken.swift`) is the source.

## Decision

Each atomic reveal code, when **deleted** from the codes surface, dispatches the `InputEvent` below. Text typed/deleted in an editable prose segment dispatches the ordinary text events. The caret never rests inside a code (ADR-0030); a code is deleted when the caret is adjacent to it (or it is selected).

| Source `CodeID` | Reveal chip | Delete dispatches | New core op? |
|---|---|---|---|
| `sceneBreak(b)` | `[SceneBreak]` | `deleteBlock(blockID: b)` | **NEW** `deleteBlock` |
| `figure(b)` | `[figure: ref]` | `deleteBlock(blockID: b)` | (same new op) |
| `italicOpen(b,n)` / `italicClose(b,n)` | `[i]` / `[/i]` | `toggleItalic(blockID: b, start, end)` over the n-th italic span | existing |
| `override(b,i)` | `[center]`/`[smallCaps]`/`[quote]`/`[left]`/`[right]` | `clearOverride(blockID: b, index: i)` | **NEW** `clearOverride` |
| `chapter(b, nil)` | `[Chapter]`/`[Prologue]`/… | `removeCut(atBlock: b)` (existing `WorkspaceDocument` mutator → `removeChapterCut`) | existing |
| `setPieceOpen(b)` / `setPieceClose(b)` | `[Verse]`/`[/Verse]`/… | `toggleSetPiece(blockID: b, kind:)` (set-piece → paragraph) | existing |
| editable prose text | the prose itself | `insertText(_:blockID:offset:)` / `deleteBackward(blockID:offset:)` | existing |

**Paired codes delete together.** `[i]`/`[/i]` are one italic span: deleting either chip dispatches one `toggleItalic` over the span's `start..<end`, which removes both chips (the span is no longer italic). `[Verse]`/`[/Verse]` are one set-piece: deleting either dispatches one `toggleSetPiece`, collapsing the block back to a paragraph and removing both chips. The span's offsets / the block's kind are looked up from the document by `RevealLayout` (the `CodeID` carries `blockID` and the span index).

**Two new `GalleyCore` ops are added — and only these two:**

1. **`deleteBlock(blockID:)`** — removes the block by ID, delegating to `Document.deleteBlock(id:)` (ADR-0010 relocation of any anchored cut). No existing `InputEvent` removes a *non-paragraph* block by ID (`deleteBackward` removes the *preceding* ornament at a paragraph boundary, which a code-chip deletion is not). **Total and guarded:** a no-op on an unknown block, and a no-op when it is the only block (the document keeps a caret home — REJECTS WHEN only-block).
2. **`clearOverride(blockID:, index:)`** — removes the single override at `index`. The existing `clearOverrides(blockID:)` clears *all* overrides; deleting one `[center]` chip must remove just that one. **Total:** a no-op on an unknown block or an out-of-range index.

## Consequences

- **The reverse path reuses the forward reducer.** Five of seven rows map to existing `InputEvent`s; only block-by-id deletion and single-override removal are new. Both surfaces drive the one reducer, so they cannot diverge (ADR-0004).
- **`deleteBlock` is the shared op for scene-break and figure chips** — both are non-paragraph "ornament" blocks the writer deletes as a unit.
- **Caret after a code deletion** lands via the shared `currentCaret` (ADR-0033): the dispatch writes the pre-edit caret and the post-edit landing exactly as the prose editor does, so undo restores it (ADR-0031).
- **Explicitly deferred (noted so a future session does not assume them shipped):**
  - **`chapter(b, offset)` (mid-block cut) deletion** — offset-anchored cuts are rare (v1 places boundary cuts); deleting a mid-block `[Chapter]` is deferred. Boundary `chapter(b, nil)` deletion ships.
  - **`line(b, i)` (`[line]`) deletion** — merging a set-piece line. Set-piece line text is non-editable in the reveal surface (LT5-1), so this is low-value now; deferred (a future `mergeSetPieceLine` op or a `deleteBackward` at the line boundary).
  - **Section-title editing in the reveal surface** — titles remain editable in the prose pane (LT3b); the reveal title text stays non-editable. This is the accepted one-phase gap from LT5 planning (ChapterEditor retired in LT5-1). Deferred to a later phase.
  - **Figure `imageRef` editing from the reveal chip** — the chip deletes the whole figure block; editing the ref text is a future enhancement (the caption is edited in the prose pane, ADR-0028).

## Session

6d262e (2026-06-07) — recorded as the first act of phase LT5-2, before any reveal-editing code. Enumerates the complete code→`InputEvent` table, adds exactly two new total reducer ops (`deleteBlock`, `clearOverride`), and lists the deferred cases. Builds on [ADR-0030](0030-reveal-codes-is-a-co-equal-editing-surface.md) (the bidirectional contract), [ADR-0032](0032-reveal-surface-architecture.md) (the surface), and [ADR-0033](0033-shared-caret-ownership.md) (the shared caret the edits move).
