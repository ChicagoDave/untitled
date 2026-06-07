# ADR-0030 — Reveal Codes is a co-equal, WordPerfect-fidelity editing surface

**Supersedes** [ADR-0006](0006-reveal-is-a-projection-and-slicing-surface.md) (reveal as a read-only projection) and [ADR-0014](0014-reveal-pane-swiftui-flow-layout.md) (reveal as a SwiftUI flow layout).

## Context

The original artifact overview described Galley as a WordPerfect-like surface. [ADR-0006](0006-reveal-is-a-projection-and-slicing-surface.md) interpreted "reveal" narrowly: a *read-only* truth view over the model that doubled as the chapter-slicing surface, and [ADR-0014](0014-reveal-pane-swiftui-flow-layout.md) built it as a `FlowLayout` of SwiftUI `Text` segments and capsule chips with no caret. The reveal pane today is exactly that — a 340pt fixed-width inspection column (`RevealPane.swift`, `ContentView.swift:71`), explicitly documented as "the truth view, not a second editing surface."

The intent was narrower and more specific than that interpretation: it is the **Reveal Codes** feature itself — not the whole app — that must work *exactly* like WordPerfect's. WordPerfect's Reveal Codes is not an inspector; it is a fully editable second view of the same document and the same cursor:

- **One document, one cursor, two views.** WordPerfect had a single document cursor; the Reveal Codes pane showed where that cursor sat *relative to the codes*. There was never an "editor caret" and a separate "reveal caret."
- **Codes are atomic, inline, bracketed tokens** (`[Italc On]…[Italc Off]`, `[HRt]`, `[Tab]`) shown inline with the prose. The cursor steps *over* a code as a single unit; it never lands inside one.
- **Fully editable, live, bidirectional.** Deleting a code in the codes pane drops its formatting in the document instantly; paired codes delete together; typing text inserts it in the document. Edits in either pane appear in both.

This is a natural fit for [ADR-0004](0004-own-model-is-source-of-truth.md) (the model is the truth; views are pure functions over it) — which is *why* WordPerfect's Reveal Codes worked in the first place (ADR-0006's own Context observed this). The earlier read-only restriction was the deviation, not the WordPerfect fidelity.

The scope of "exactly like WordPerfect" is the **Reveal Codes pane behavior only**. The main prose editor stays the keyboard-first surface already built (`InputController`, §8); WordPerfect conventions do not propagate to it.

## Decision

1. **Reveal Codes becomes a co-equal editing surface, not a read-only projection.** It is a second view that renders the reveal projection with codes made visible and atomic, and writes the *same* `InputEvent`s against the *same* `WorkspaceDocument` as the prose editor. Both panes are pure projections-of and writers-to the one model (ADR-0004), so they cannot drift — the same guarantee that protected the read-only view now protects two editable views.

2. **One model-coordinate selection, shared by both panes.** There is a single model-coordinate selection (a `(blockID, offset)` collapsed caret, or an anchor+caret range) expressed in the `EditorLayout` coordinate space — a range, not just a point, because `toggleItalic` and deleting a paired code both operate over a span. This matches [ADR-0031](0031-undo-redo-carries-the-caret.md)'s caret representation. Each pane maps that one selection into its own character coordinates for display. #2 ("the reveal caret matches the editor") is therefore *one selection rendered twice*, not two carets kept in sync.

3. **WordPerfect code semantics are the spec.** Codes render inline as atomic bracketed tokens. The caret steps over a code as one unit and never rests inside it. Editing is live and bidirectional: deleting a code removes its formatting in the prose pane immediately; **paired codes (italic open/close, set-piece open/close) delete together**; typing inserts text. These rules — not a freeform reverse-parser — define what "editable codes" means, which closes the open semantics question raised when this was first considered.

4. **The reveal surface is a TextKit view, not a flow layout.** A shared caret, atomic editable codes, and configurable orientation require a real text-editing surface. The reveal pane is rebuilt as a TextKit surface (likely a second `InputController`-style view rendering the reveal projection), superseding ADR-0014's `FlowLayout` of `Text`+chips. The pure projection logic (`revealProjection` in `GalleyCore`; the view-model mapping in `GalleyShell`) is reused; only the AppKit rendering changes.

5. **Orientation is user-configurable; default right.** WordPerfect used a horizontal top/bottom split because of monochrome, fixed-font, narrow screens. On modern wide monitors a vertical split is the better default, so the panes may be arranged **left, right, or below**, user-selectable, defaulting to **right**. This is the one deliberate deviation from WordPerfect's physical layout; the *behavior* is unchanged.

6. **Scope is the Reveal Codes pane only.** The main prose editor remains the keyboard-first surface (§8, memory: keyboard-first-writing-ux). WordPerfect conventions are confined to the codes pane.

## Consequences

- **The chapter-slicing role of the reveal pane (ADR-0006) is re-homed, not lost.** Chapter cuts are placed/retitled inline in the editing surfaces (LT2/LT3 already moved titling into the stream). The dedicated "Edit Chapters" mode and the `ChapterEditor`/`ChapterAnchorRow` list (a panel of toggles) are superseded by editing the codes directly — consistent with the keyboard-first principle (structure via typing/codes, not panels).
- **Two editable surfaces share one caret and one undo timeline.** The caret must live in model coordinates owned at the `WorkspaceDocument`/workspace level (or a shared controller), not privately inside one `InputController`. This is the direct prerequisite that makes [ADR-0031](0031-undo-redo-carries-the-caret.md) (undo carries the caret) necessary rather than optional: with two surfaces, diff-inferring a caret position is no longer even well-defined.
- **Undo/redo dispatch is shared, not per-surface.** Cmd-Z / Cmd-Shift-Z dispatch to the one workspace-level undo timeline ([ADR-0031](0031-undo-redo-carries-the-caret.md)) regardless of which pane has focus; the restored selection updates *both* panes, and focus stays with the active pane. Today `performUndo`/`performRedo` live privately in the prose `InputController` — with a second editable surface, the undo command and its caret restore must be hoisted to the shared owner. (The mechanics belong to LT5 planning; the contract is fixed here.)
- **A reverse path from reveal edits to `InputEvent`s is required.** Today reveal is one-way (`Document → [RevealToken]`). Editing the codes pane needs each atomic code edit (delete a code, type between codes) to map to an existing `InputEvent` (e.g. deleting an `[Italc On]/[Italc Off]` pair → `toggleItalic` over the run span; deleting an `[HRt]` → `deleteBackward` at a block boundary). New core ops are added only where no existing `InputEvent` expresses the edit.
- **`FlowLayout` and the SwiftUI chip views are retired** for the reveal pane (ADR-0014). `RevealItem`/`revealItems(from:)` stay as the pure mapping if still useful, but the rendering moves to TextKit.
- **Figure blocks (ADR-0027) must render as an editable code.** LT4 introduced `BlockContent.figure` with a `[figure: ref]` reveal chip; under this ADR that chip becomes an atomic, deletable code in the editable reveal surface. LT5 therefore follows LT4 so figures already exist when the editable surface is built.
- **A settings surface for orientation is introduced.** Left/right/below is a user preference that must persist (alongside the existing session-restore machinery).
- **This is a track, not a phase.** It is captured as **LT5** in `plan.md`, sequenced after LT4-2, and planned in detail (with its own plan-review) once figures land.

## Session

ce486f (2026-06-07) — recorded after the user clarified that the WordPerfect-fidelity requirement applies specifically to the Reveal Codes pane (shared cursor, atomic editable codes, live bidirectional sync), not to the whole app. Reverses ADR-0006's read-only stance and ADR-0014's flow-layout choice; orientation made user-configurable (default right) for wide monitors. Pairs with [ADR-0031](0031-undo-redo-carries-the-caret.md).
