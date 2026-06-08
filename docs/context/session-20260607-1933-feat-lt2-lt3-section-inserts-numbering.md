# Session Summary: 2026-06-07 - feat/lt2-lt3-section-inserts-numbering

## Goals
- Complete Phase LT5-3 (configurable split orientation + persistence)
- Ship user-reported reveal/editor fixes discovered during post-LT5-2 testing
- Land ADR-0035 (structural-whitespace reveal codes: `[p]` and `[sp]`)

## Phase Context
- **Plan**: macOS Editor Shell (Build Step 2) — LT5 track
- **Phase executed**: Phase LT5-3 — "Configurable split orientation + persistence" (Small)
- **Tool calls used**: 134 / 100
- **Phase outcome**: Ran over budget (134 vs 100); follow-up fix rounds added scope after core phase delivered

## Completed

### Phase LT5-3: Orientation enum, persistence, and ContentView wiring
- `RevealOrientation: String, CaseIterable` enum added to `GalleyShell` (`left`/`right`/`below`, default `.right`, `label` + `next` for keyboard cycling).
- `WorkspaceSession` gained `save(orientation:)` / `loadOrientation()` with `UserDefaults` key `galley.session.revealOrientation`; `.right` default for back-compat with pre-LT5-3 sessions.
- `WorkspaceModel` gained `@Observable revealOrientation` (read from session on init) + `setRevealOrientation(_:)` as the single mutation point (updates property + persists).
- `ContentView` replaced the hard-coded 340pt right-column with placement driven by `workspace.revealOrientation`: flat `HStack` for left/right (fixed 340pt) and `VStack` for below (fixed 240pt). Bottom-bar segmented `Picker` (visible only when reveal is up) + ⌘⇧/ cycle shortcut.
- Critical deviation: an initial `HSplitView`/`VSplitView` attempt broke the prose `NSTextView`'s click hit-testing (the split view re-parents the hosted `NSScrollView`, causing clicks to land at end-of-text). Reverted to flat containers; user-draggable divider deferred (needs an `NSSplitViewController` host that preserves hit-testing).
- +5 real-path `UserDefaults` tests; mutation-verification clean.

### ADR-0035: Structural-whitespace reveal codes (`[p]` and `[sp]`)
- `CodeID.paragraph(BlockID)` → `[p]` hard-return chip emitted at the END of every `.paragraph` block in both `revealProjection` and the `revealSegments` projection; display-only (deletion deferred, mapped to `.deferred` in `revealDeleteAction`).
- `CodeID.sectionSpace(BlockID)` → `[sp]` section-opener spacing chip emitted AFTER each boundary cut's title in both projections; display-only. Fixes the reveal mashing `[Chapter]Chapter 1In the event…` into `[Chapter]Chapter 1[sp]In the event…`.
- Both codes added to the `RevealSegmentTests` drift guard (order is verified against the live `revealProjection` output).
- ADR-0035 extends ADR-0009's closed vocabulary by exactly two new members — deliberated and recorded.

### User-reported click fixes
- **Heading hit-test band**: `headingCut(atPoint:)` now hit-tests the heading's full vertical band rather than the tight glyph box; clicking past the end of a section-title line no longer glides the caret into the body.
- **Heading boundary half-open**: `EditorLayout.headingCut(forCharacterAt:)` previously claimed the heading/body boundary inclusively, causing `skipPastHeading` to glide the caret backward when clicking before the first prose word. Fixed by releasing a non-edited heading's end boundary to the prose (half-open); an actively-edited title retains end-caret inclusivity.

## Key Decisions

### 1. Flat HStack/VStack over HSplitView/VSplitView
`HSplitView`/`VSplitView` re-parents the hosted `NSScrollView`, breaking click hit-testing in the prose `NSTextView` (clicks land at end-of-text). Reverted to flat containers; the `.right` default is byte-for-byte equivalent to the pre-LT5-3 layout, preserving all existing click behavior. Draggable divider deferred to a future `NSSplitViewController`-based host. Recorded in plan.md LT5-3 status.

### 2. `[p]`/`[sp]` are display-only structural-whitespace codes
Both new chips are explicitly non-deletable (`.deferred` delete action) and have no prose-side semantic. They exist solely to prevent the reveal stream from running structure tokens directly into prose text — a readability affordance, not a model state. ADR-0035 records the closed addition and its non-deletable status.

## Next Phase
- **LT5 COMPLETE** — all three phases (LT5-1, LT5-2, LT5-3) are DONE. No next phase in the LT5 track.
- Remaining open work is outside any tracked plan phase (see Open Items below).

## Open Items

### Short Term
- Manual GUI verification of the three orientations + quit-relaunch persistence (AX harness unreliable per project memory `galley-gui-smoke-via-accessibility`; user has eyeballed and said "looks good" but a formal click-through is outstanding).
- Verify the two click fixes (heading band hit-test, heading boundary half-open) in the running app; user has not confirmed these interactively yet.
- Fix (1) (prose click at end-of-text from HSplitView revert) is folded into LT5-3's flat-container fix; no separate verify needed.

### Long Term
- User-draggable reveal divider (needs `NSSplitViewController` host preserving hit-testing).
- Open design question: should `[sp]` also appear at scene breaks / between plain paragraphs (currently section-opener-only)?
- Deletable reveal chips for `[p]` and `[sp]` (deletion deferred in ADR-0035).
- Per the LT5-2 deferred list: mid-block `[Chapter]` deletion, `[line]` (set-piece line) deletion, in-reveal section-title editing, figure `imageRef` editing from within the reveal surface.

## Files Modified

**GalleyShell** (5 files):
- `app/Sources/GalleyShell/RevealOrientation.swift` — new; `RevealOrientation` enum with `label`/`next`
- `app/Sources/GalleyShell/WorkspaceSession.swift` — `save(orientation:)` / `loadOrientation()` added
- `app/Sources/GalleyShell/WorkspaceModel.swift` — `revealOrientation` observable + `setRevealOrientation(_:)`
- `app/Sources/GalleyShell/RevealEditing.swift` — `.deferred` delete actions for `paragraph`/`sectionSpace`
- `app/Sources/GalleyShell/RevealSegments.swift` — `[p]`/`[sp]` chips emitted in `revealSegments(of:)`

**GalleyCore** (2 files):
- `core/Sources/GalleyCore/Reveal.swift` — `CodeID.paragraph`/`.sectionSpace`; both chips emitted in `revealProjection`
- `core/Sources/GalleyCore/RevealToken.swift` — `CodeID` cases added

**Galley executable** (3 files):
- `app/Sources/Galley/ContentView.swift` — orientation-driven placement; flat HStack/VStack; bottom-bar `Picker`; ⌘⇧/ shortcut
- `app/Sources/Galley/EditorLayout.swift` — `headingCut(atPoint:)` vertical-band hit-test; `headingCut(forCharacterAt:)` half-open boundary fix
- `app/Sources/Galley/InputController+Title.swift` — `headingCut(atPoint:)` call-site update
- `app/Sources/Galley/RevealController.swift` — `[p]`/`[sp]` rendered as display-only chips (no delete dispatch)

**Tests** (3 files):
- `app/Tests/GalleyShellTests/WorkspaceModelTests.swift` — +5 orientation UserDefaults tests
- `app/Tests/GalleyShellTests/RevealSegmentTests.swift` — drift guard updated for `[p]`/`[sp]`; +1 `[sp]` present/absent test
- `app/Tests/GalleyShellTests/RevealEditingTests.swift` — `.deferred` assertions for `paragraph`/`sectionSpace`
- `core/Tests/GalleyCoreTests/RevealTests.swift` — exact-sequence tests updated for `[p]`/`[sp]`; +2 new cases

**Docs** (2 files):
- `docs/adrs/0035-paragraph-hard-return-reveal-code.md` — new ADR
- `docs/context/plan.md` — LT5-3 status updated to COMPLETE; post-phase follow-ups recorded

## Notes

**Session duration**: ~2–3 hours (started at T+0, 134 tool calls)

**Approach**: LT5-3 core feature first (enum → persistence → ContentView); then iterative fix rounds for user-reported issues found during live testing. Each round: reproduce → identify root cause → implement minimal fix → update tests.

**NSSplitView pitfall (important for future sessions)**: Any future attempt at a user-draggable reveal divider must use `NSSplitViewController` (not bare `HSplitView`/`VSplitView`) because only the view-controller layer correctly preserves the `NSScrollView` view hierarchy and avoids the hit-test reparenting issue.

---

## Session Metadata

- **Status**: COMPLETE
- **Blocker**: N/A
- **Blocker Category**: N/A
- **Estimated Remaining**: N/A
- **Rollback Safety**: safe to revert

## Dependency/Prerequisite Check

- **Prerequisites met**: LT5-2 COMPLETE (bidirectional reveal editing), UX-1 COMPLETE (shared caret), `WorkspaceSession` with injectable `UserDefaults` (LT3i)
- **Prerequisites discovered**: None

## Architectural Decisions

- **ADR-0035** (new): `[p]` paragraph hard-return and `[sp]` section-opener spacing chips added to the closed reveal vocabulary as display-only structural-whitespace codes — rationale: prevents structure tokens from running directly into prose text in the reveal stream; non-deletable in v1.
- Pattern applied: same closed-vocabulary amendment process as the `blockQuote` ADR-0009 amendment (BP1) — deliberate, scoped, recorded.

## Mutation Audit

- Files with state-changing logic modified: `WorkspaceModel.swift` (orientation persistence), `WorkspaceSession.swift` (UserDefaults write), `Reveal.swift`/`RevealToken.swift`/`RevealSegments.swift` (projection mutation)
- Tests verify actual state mutations (not just events): YES — `WorkspaceModelTests` asserts the stored `UserDefaults` value and the `WorkspaceModel.revealOrientation` property after `setRevealOrientation(_:)`; `RevealSegmentTests` drift guard asserts the exact token sequence including `[p]`/`[sp]` positions
- Mutation-verification agent ran: clean

## Recurrence Check

- Similar to past issue? YES — `session-20260607-1641-feat-lt2-lt3-section-inserts-numbering.md` and LT3f (caret gliding past headings unexpectedly). The heading boundary / skip-past-heading mechanism has now been touched in four separate sessions (LT3b, LT3c, LT3f, this session). Consider a one-time audit of `EditorLayout.headingCut(forCharacterAt:)` and `skipPastHeading` to consolidate the logic and prevent further recurrence.

## Test Coverage Delta

- Tests added: 10 (GalleyShell: +5 orientation, +1 `[sp]` presence, +1 `[p]`/`[sp]` deferred-delete; GalleyCore: +2 `[p]`/`[sp]` projection sequence; RevealSegmentTests drift guard extended)
- Tests passing before: GalleyCore 151, GalleyShell 106
- Tests passing after: GalleyCore 155, GalleyShell 113
- Known untested areas: ContentView orientation-driven layout (AppKit; manual GUI only), `RevealController` chip rendering for `[p]`/`[sp]` (AppKit; manual GUI only), heading band hit-test / half-open boundary fix (AppKit caret layer; manual click-through outstanding)

---

**Progressive update**: Session completed 2026-06-07 19:33 CST
