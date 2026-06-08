# Session Summary: 2026-06-07 - feat/lt2-lt3-section-inserts-numbering

## Goals
- Replace the 3-phase LT5 scaffold in plan.md with detailed, session-sized phases (LT5 planning).
- Implement LT5-1: Reveal Codes as a co-equal TextKit editing surface — read-only render + shared caret synchronized across prose and reveal panes.

## Phase Context
- **Plan**: macOS Editor Shell (Build Step 2) — LT5 track
- **Phase executed**: LT5-1 — "Read-only TextKit reveal render + shared caret rendered twice" (Medium)
- **Tool calls used**: not recorded in session-state (second unit of this session)
- **Phase outcome**: Completed

## Completed

### Unit A — LT5 Detailed Planning
Replaced the 3-phase LT5 SCAFFOLD in `docs/context/plan.md` with three detailed, session-sized phases: LT5-1 (Medium, 250-call budget), LT5-2 (Large, 400-call budget), and LT5-3 (Small, 100-call budget). Each phase carries tier/budget/entry state/deliverable/exit state/Integration-Reality gates and a References-consulted list. Candidate ADRs 0032 (reveal-surface architecture), 0033 (shared caret), and 0034 (code→InputEvent table) were enumerated. A `/devarch:plan-review` pass ran and surfaced one advisory TENSION: `ChapterEditor` is retired in LT5-1 before section-title editing in the reveal surface arrives in LT5-2, leaving a one-phase window where titles are only editable via the prose heading. User chose to start LT5-1 as written, accepting that window. Plan archived to `docs/work/plan-20260607-1553.md`.

### Unit B — LT5-1 Implementation
ADR-0032 and ADR-0033 were written and passed a multi-ADR review (2 seam findings were fixed before implementation began).

**ADR-0032** records the architecture choice: a dedicated `RevealController: NSTextView` subclass rendering `revealProjection()` via a `RevealLayout` annotated-stream projection; the two surfaces communicate only through `WorkspaceDocument`. A flat `revealSegments()` projection (in `GalleyShell`) is kept alongside the existing `revealProjection()` and drift-guarded by a test asserting their `CodeID` order agrees.

**ADR-0033** records the shared-caret ownership seam: one `currentCaret: Caret?` on `WorkspaceDocument` (already the undo owner, already `@MainActor`); both surfaces write it on selection change and read from it to reconcile. `performUndo`/`performRedo` were hoisted from their private location in `InputController+Title.swift` to `WorkspaceDocument`, so both panes can trigger the shared undo timeline.

**`GalleyShell` new file — `RevealSegments.swift`**: `RevealSegment` value type carrying `(blockID, offset)` for prose tokens and `CodeID` for code chips; `revealSegments(of:)` pure annotated projection. `WorkspaceDocument` gained `currentCaret: Caret?` and the hoisted `performUndo()`/`performRedo()` on the shared `(Document, Caret?)` timeline.

**`Galley` app new files**:
- `RevealLayout.swift` — converts the annotated segment stream into an `NSAttributedString` with `[label]` code chips and maintains a bidirectional caret↔character map via `modelPosition(forCharacterAt:)`, `characterRange(for:)`, `characterPosition(for:)`, and `codeSegment(at:)`.
- `RevealController.swift` — an `NSTextView` subclass that is read-only-as-to-model: renders on `render()`, reconciles the shared caret via `syncIfNeeded()` and `reconcileSharedCaret()`, publishes `currentCaret` on `setSelectedRanges`, steps the caret over code chips (one arrow jumps an entire `[i]` chip), routes `Cmd-Z`/`Cmd-Shift-Z` to `buffer.performUndo`/`Redo`, and intercepts `insertText`/`deleteBackward` as no-ops until LT5-2.
- `RevealPane.swift` rewritten as the `NSViewRepresentable` host; `FlowLayout`, `SectionChip`, `ChapterEditor`, and `ChapterAnchorRow` are all retired.

**`Galley` app modified files**:
- `InputController` — `setSelectedRanges` publishes `currentCaret`; `reconcileSharedCaret()` added; `performUndo`/`performRedo` (in `InputController+Title`) delegate to `buffer.performUndo`/`Redo` then `restoreCaret`.
- `DocumentTextView` and `ContentView` — pass a `caretToken` so SwiftUI re-runs `updateNSView` for cross-pane reconcile on caret change.

**Tests — new `RevealSegmentTests.swift` (+7)** including the drift guard asserting `revealSegments()` `CodeID` order equals `revealProjection()`. Suites: 98 GalleyShell + 144 GalleyCore GREEN; `swift build` clean, 0 warnings. `RevealRendering.swift` (`RevealItem`/`chapterAnchors`) is kept and now used only by `RevealRenderingTests`.

**GUI smoke (Accessibility API)**: reveal renders atomic bracketed code chips (`[i]`/`[/i]`/`[Chapter]`); prose↔reveal caret sync works both directions at corresponding model offsets; code step-over (one arrow jumps a `[i]` chip); prose edit propagates to the reveal render; shared undo triggered from the reveal pane reverts a prose edit (verified via `AXNumberOfCharacters` 331→332→331). Two AX findings noted: `AXFocused` is unreliable for key delivery — real mouse clicks (click at coordinates) are required; and a consistent 1-off in `AXSelectedTextRange` at end-of-document is an AX quirk, not a feature bug.

## Key Decisions

### 1. ADR-0032 — Reveal surface architecture
Two separate controllers communicating only through `WorkspaceDocument`; `RevealController` holds its own `RevealLayout` and renders `revealSegments(of:)`. A flat annotated projection keeps the headlessly-testable pure path (the drift guard is the acceptance gate). The shared-controller alternative was rejected to avoid a new stateful coordinator object.

### 2. ADR-0033 — Shared-caret ownership seam
`currentCaret: Caret?` lives on `WorkspaceDocument` (already the undo owner, already `@MainActor`, already `Foundation`-only). `performUndo`/`performRedo` hoisted there so both panes dispatch into the same timeline. The alternative (a new `SharedEditingCoordinator`) was rejected as unnecessary indirection.

### 3. One-phase titling-via-prose-only window accepted
The plan-review TENSION that `ChapterEditor` retires in LT5-1 but section-title editing in the reveal surface does not arrive until LT5-2 was surfaced and the user explicitly chose to proceed as written. Section titles remain editable via the prose heading during the window between LT5-1 and LT5-2.

## Next Phase
- **Phase LT5-2**: "Code→event table + bidirectional code editing" (Large, 400-call budget).
- **Tier**: Large
- **Entry state**: LT5-1 committed; `RevealController` edit entry points (`insertText`, `deleteBackward`) are intercepted as no-ops; the shared caret syncs between panes; shared undo works from both panes. ADR-0034 (code→InputEvent table) must be written as the first act of LT5-2 before any editing code is written. New GalleyCore ops likely needed: `deleteBlock(blockID:)` and `clearOneOverride(blockID:override:)`.

## Open Items

### Short Term
- LT5-2: Write ADR-0034 (code→InputEvent table), add `deleteBlock`/`clearOneOverride` core ops with Behavior Statements + tests, wire `RevealController` editing dispatch, implement paired-code deletion, section-title editing in the reveal surface.
- LT5-3: Configurable split orientation (left/right/below) + session persistence.

### Long Term
- Figure `imageRef` editing from within the reveal surface (in-reveal ref editing deferred to post-LT5).
- Divider-position persistence across sessions (deferred from LT5-3).

## Files Modified

**New (GalleyShell)**:
- `app/Sources/GalleyShell/RevealSegments.swift` — `RevealSegment` value + `revealSegments(of:)` pure annotated projection

**Modified (GalleyShell)**:
- `app/Sources/GalleyShell/WorkspaceDocument.swift` — `currentCaret`, hoisted `performUndo`/`performRedo`

**New (Galley app)**:
- `app/Sources/Galley/RevealLayout.swift` — annotated stream → `NSAttributedString` + caret↔char map
- `app/Sources/Galley/RevealController.swift` — read-only-as-to-model `NSTextView` subclass

**Rewritten (Galley app)**:
- `app/Sources/Galley/RevealPane.swift` — `NSViewRepresentable` host; `FlowLayout`/`SectionChip`/`ChapterEditor`/`ChapterAnchorRow` retired

**Modified (Galley app)**:
- `app/Sources/Galley/InputController.swift` — publishes `currentCaret`, `reconcileSharedCaret()`
- `app/Sources/Galley/InputController+Title.swift` — `performUndo`/`performRedo` delegate to store
- `app/Sources/Galley/DocumentTextView.swift` — `caretToken` for cross-pane SwiftUI reconcile
- `app/Sources/Galley/ContentView.swift` — passes `caretToken` to both panes

**New (tests)**:
- `app/Tests/GalleyShellTests/RevealSegmentTests.swift` — +7 tests incl. drift guard

**Documentation**:
- `docs/adrs/0032-reveal-surface-architecture.md` — new
- `docs/adrs/0033-shared-caret-ownership.md` — new
- `docs/context/plan.md` — LT5 scaffold replaced with detailed phases; LT5-1 marked COMPLETE
- `docs/work/plan-20260607-1553.md` — archived plan snapshot

## Notes

**Session duration**: ~2–3 hours (this unit; follows UX-1 earlier in the same session).

**Approach**: ADR-first (0032 + 0033 written and multi-ADR-reviewed before any code); headless pure projection extracted to `GalleyShell` for testability; AppKit rendering layer kept in the `Galley` executable only per ADR-0002/0011. GUI smoke used the macOS Accessibility API; `AXFocused` unreliability required click-based key delivery.

---

## Session Metadata

- **Status**: COMPLETE
- **Blocker**: N/A
- **Blocker Category**: N/A
- **Estimated Remaining**: N/A
- **Rollback Safety**: safe to revert

## Dependency/Prerequisite Check

- **Prerequisites met**: LT4-2 COMPLETE (figures exist for the reveal surface to render); UX-1 COMPLETE (`Caret` type + `performUndo`/`performRedo` + `applyEdit` choke point available to hoist).
- **Prerequisites discovered**: None.

## Architectural Decisions

- ADR-0032: `RevealController` `NSTextView` + flat annotated `revealSegments()` projection, drift-guarded — keeps the pure testable path separate from the AppKit rendering.
- ADR-0033: `currentCaret: Caret?` on `WorkspaceDocument`; `performUndo`/`performRedo` hoisted to the store; both surfaces write and read the one published caret.

## Mutation Audit

- Files with state-changing logic modified: `WorkspaceDocument.swift` (new `currentCaret` setter), `InputController.swift` (publishes `currentCaret`), `InputController+Title.swift` (delegates undo/redo to store).
- Tests verify actual state mutations (not just events): YES — `RevealSegmentTests` asserts on `revealSegments` output (segment identity + CodeID order); `WorkspaceUndoTests` (inherited from UX-1) asserts on `(Document, Caret)` pairs. The AppKit caret-sync behavior is covered by the manual GUI smoke check (AX verification of `AXNumberOfCharacters` before/after undo).

## Recurrence Check

- Similar to past issue? NO — the AX `AXFocused` unreliability is newly noted here; no prior session recorded it.

## Test Coverage Delta

- Tests added: +7 (`RevealSegmentTests`)
- Tests passing before: GalleyShell 91, GalleyCore 144
- Tests passing after: GalleyShell 98, GalleyCore 144
- Known untested areas: `RevealController` rendering and caret-sync behavior (AppKit, no headless path); covered by GUI smoke only.

---

**Progressive update**: Session completed 2026-06-07 16:41 CST
