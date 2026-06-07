# ADR-0031 — Undo/redo carries the caret; no diff-based caret recovery

## Context

Undo/redo stores whole-`Document` snapshots in `WorkspaceDocument` (`undoStack`/`redoStack`, `WorkspaceDocument.swift:39-43`); `checkpoint()` pushes the prior document before each edit. The model restores correctly. The *caret*, however, is not stored — after `undo()`/`redo()`, `InputController` **infers** where the caret should land by diffing the old and new documents: `changeSite`/`changeOffset` in `InputController+Title.swift:294-332` walk the two block arrays, find the first differing block, and compute an offset from the shared prefix/suffix of the text.

This diffing is fragile and approximate:

- It guesses caret intent from a text delta rather than recording where the caret actually was. Equal-but-relocated text, multi-site edits, and non-paragraph content (it returns offset 0 for anything that is not a `.paragraph`) all defeat it.
- It couples caret recovery to the *shape* of the change, so every new edit kind (e.g. figure caption edits, ADR-0028) risks a new diffing edge case.
- [ADR-0030](0030-reveal-codes-is-a-co-equal-editing-surface.md) introduces a second editable surface sharing one caret. With two surfaces, "diff the document to find the caret" is no longer even well-defined — the caret that should be restored is the one that existed at edit time, which only the editor knew and threw away.

The fix is to treat the caret as part of the undoable state, which is what mature editors do.

## Decision

1. **Each undo entry stores the caret, not just the document.** The undo and redo stacks hold `(Document, caret)` pairs, where `caret` is a model-coordinate selection (a `(blockID, offset)` collapsed caret, or a start/end range). `checkpoint()` captures the caret *as it was before the edit*; `undo()`/`redo()` restore the stored caret exactly.

2. **The caret is recorded in model coordinates, owned outside the view.** The caret stored is the `EditorLayout` `(blockID, offset)` position — never a TextKit character index — so it is stable across re-projection and meaningful to both editing surfaces (ADR-0030). The model-coordinate caret is owned at the `WorkspaceDocument` (or shared workspace) level so both surfaces read and write the one value.

3. **`changeSite`/`changeOffset` diffing is deleted.** `performUndo`/`performRedo` (`InputController+Title.swift`) stop diffing and simply place the caret the stack hands back. The two private diffing helpers are removed.

4. **Restore is clamped, never invented.** If a stored caret no longer maps to a valid position after restore (block removed, offset past end), it clamps to the nearest valid position and falls back to the first editable position — the existing `restoreCaret` fallback ladder. It never re-derives the caret from a document diff.

## Consequences

- **Undo lands the caret where the writer's attention was**, because that is what was recorded — not where a text-delta heuristic guessed. This is correct by construction for every edit kind, including non-paragraph content and caption edits, with no per-kind special-casing.
- **The undo API surface changes.** `WorkspaceDocument.undo()/redo()` and `checkpoint()` gain a caret parameter / return value; `apply(_:)` must receive the pre-edit caret (the input layer already knows it via `caretModelPosition()`), and `setCutTitle`/`placeCut`/the other editing mutators that call `checkpoint()` must thread it too. The `WorkspaceUndoTests` are updated to assert the restored caret, not only the restored document — turning today's document-only assertions into `(document, caret)` assertions (closing a YELLOW: the suite currently asserts state but not the caret contract this ADR establishes).
- **Memory cost is negligible.** A caret is two integers per snapshot atop a whole-`Document` value; the `undoLimit = 500` budget is unaffected.
- **This unblocks ADR-0030.** A single stored, model-coordinate caret is the shared-caret prerequisite for two editable surfaces. The two ADRs are designed together, but this one is **independent to implement** and can land before LT5 as a small standalone item — it improves the current single-surface editor on its own.
- **Boundary touched:** `WorkspaceDocument` is a store (rule 8a). A Boundary Statement is produced before editing it — the caret added here is per-document editing state the store legitimately owns (it already owns the undo timeline), not per-render view state.

## Session

ce486f (2026-06-07) — recorded alongside [ADR-0030](0030-reveal-codes-is-a-co-equal-editing-surface.md). Replaces the diff-inferred caret recovery (`changeSite`/`changeOffset`) with a caret stored in each undo entry, in model coordinates, owned at the store level. Sequenced as a small standalone item, ahead of or interleaved with LT5.
