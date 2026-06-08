# ADR-0026 — Section inserts carry a closed `SectionRole`, applied via one atomic reducer arm

## Context

LT2 adds Prologue / Epilogue / Dedication / Chapter to the Cmd-; palette. Structurally, a section of prose is already a chapter: a movable `ChapterCut` laid over the flat block stream ([ADR-0005](0005-chapters-as-overlay-not-containers.md)), not a container. So a "section insert" is two things at once — a fresh prose block to write into, and a cut that begins the new section at that block.

Two questions had to be resolved before coding:

1. **How does the typesetter tell a prologue from a chapter?** The authoring/typesetting boundary ([ADR-0024](0024-authoring-and-typesetting-are-separate.md)) makes Galley capture *intent*; the typesetter consumes it (a dedication centres on its own page; a prologue precedes chapter numbering). A free-form `title` string ("Prologue") is fragile intent — it breaks under translation, capitalization, or a writer who titles their prologue "Before".
2. **How is the insert applied without partial state?** The op must mint a fresh block *and* anchor a roled cut to that exact block. The minted `BlockID` is only known inside the reducer ([ADR-0010](0010-stable-block-identity.md)).

## Decision

**(a) A closed `SectionRole` enum on `ChapterCut`.** `SectionRole` is `chapter | prologue | epilogue | dedication` — a closed vocabulary in the spirit of [ADR-0009](0009-closed-vocabulary-codes-justify-to-reveal.md). It is added as `ChapterCut.role`, defaulting to `.chapter`. The `String` raw value is the sidecar wire token, its own exact inverse, so the codec cannot drift from the enum. `title` stays free-form display text; `role` is the reliable intent the typesetter drives layout from. Roles beyond the four (e.g. "Part One") are deferred.

Sidecar codec ([ADR-0007](0007-plain-text-files-chapters-in-sidecar.md)): `CutDTO.role` is optional. A missing token decodes to `.chapter` (a legacy roleless sidecar is unchanged), and serialize **omits** the default `.chapter` so existing sidecars round-trip byte-identical. A present-but-unknown token is a hard `ParseError.unknownSectionRole` — never silently defaulted — mirroring the closed-vocabulary rejection of override tokens.

**(b) One atomic reducer arm, `InputEvent.insertSection(role:afterBlockID:)`** — not a composition of existing ops. The arm seeds a fresh empty paragraph immediately after the anchor and appends a boundary `ChapterCut` of `role` anchored to *that* seeded block, in one step, where the minted ID is in hand. It is pure and total: an unknown anchor is a no-op (no block, no cut, counter untouched), so a stale palette event can never crash editing.

Composition was rejected against the plan's own criterion ("if any partial-state risk, require the single reducer arm"): composing `insertBlock` + a separate place-cut event forces the app layer to re-find the new block by array position *between* two events — exactly the half-applied window (block seeded, cut not yet placed, or placed on the wrong block) the atomic arm eliminates.

**(c) The role is surfaced, and titles are named inline in the truth view — never in a panel.** `revealProjection` labels each cut chip by its role (`Prologue` / `Epilogue` / `Dedication` / `Chapter`), so a prologue reads as a prologue rather than an indistinct chapter. A section's title is set or changed at any time by tapping it inline on its reveal chip (the `name…` placeholder when empty). The palette is a pure insert surface — picking a section inserts it and drops the caret into the fresh prose; it does not title. The reveal pane's "Edit Chapters" slide-out no longer titles either — it only places/removes cuts. This follows the keyboard-first principle and the reason Phase 6's panel-driven chapter UX was reverted: structure is named where it lives, in the flow of writing, in exactly one place.

> A first cut at collecting the title *in the Cmd-; palette popover* (a typed prompt before insert) was built and removed the same session — it was unreliable in the live editor, and inline tap-to-edit on the chip already covers naming at creation and any time after. One titling home, not two.

## Consequences

- The typesetter reads one closed field for page-layout decisions; it never parses titles. The four roles share one code path — the palette differs only in the role it passes.
- Role is visible where structure lives (the reveal stream), and titling has exactly one home — inline on the chip. An untitled cut is a valid state, so a section is inserted first and named whenever the writer chooses.
- `ChapterCut` gains a field; its `Equatable/Hashable/Sendable` conformances and the "overlay, not container" promise are intact. `moveChapterCut` preserves the role for free (it only re-anchors `blockID`).
- Back-compatible by construction: every sidecar written before LT2 decodes identically, and every plain chapter still serializes without a `role` key.
- The insert path is headlessly testable on the production reducer (no stubs): the seeded block, the roled cut's anchor, the minted ID, and the no-op are all asserted in `SectionInsertTests`; the role's sidecar round-trip, the legacy default, and the unknown-token rejection in `StorageTests`.
- The closed vocabulary is the constraint to honor next: chapter-numbering-that-skips-prologues and a real manuscript TOC are deferred and must be built *on* the role, not by re-parsing titles. Output layout (the dedication's vertical centering, new-page breaks) stays out of Galley (ADR-0024).

**(d) Titles are explicit and never empty; chapters auto-number via macros (LT3).** A section title is always authored — inserting a section seeds a non-empty default (`SectionRole.defaultTitle`: Chapter → `Chapter #a`, others → the role name) that the writer edits; clearing a title reverts to the default rather than going blank. Numbering is a title **macro**: `#a` → arabic (1, 2, 3), `#r` → roman (I, II, III), resolving to the chapter number counted role-aware (`Document.chapterOrdinal` — only `.chapter` cuts count; prologues/epilogues/dedications are skipped). The stored title keeps the macro (intent for the typesetter, ADR-0024); `Document.resolvedTitle(forCutAt:)` is the pure render-time resolution shared by the editor preview and (eventually) the typesetter, so inserting a prologue or reordering renumbers for free. The title follows a **spreadsheet rule**: the resolved value is shown when displayed, the raw macro when editing.

## Session

LT3 (2026-06-06) — `#a`/`#r` numbering macros + role-aware `chapterOrdinal`/`resolvedTitle` + `SectionRole.defaultTitle` in `GalleyCore` (`ChapterNumbering.swift`); `insertSection` seeds the non-empty default title. **Inline title editing in the main editor** (`InputController+Title.swift`, `EditorLayout` title segments): a heading shows resolved, and clicking it (or inserting a section) enters raw edit routed to `setCutTitle`; Enter/Esc commit and drop into the chapter's prose; an emptied title reverts to its default. The reveal chip (`SectionChip`) is now read-only resolved. **Model-snapshot undo/redo** (`WorkspaceDocument` checkpoint stacks; Cmd-Z / Cmd-Shift-Z in `InputController`). +8 GalleyCore tests (124 GREEN) + 6 GalleyShell undo tests (78 GREEN). Integration Reality: undo/redo and title mutation are headlessly tested; the AppKit caret/click routing for inline editing is a manual GUI gate.

LT2 (2026-06-06) — `SectionRole` on `ChapterCut`; `InputEvent.insertSection` atomic reducer arm; sidecar role token codec (default omitted, unknown rejected); palette unified into three groups (Scene Break / templates / section inserts). +6 GalleyCore reducer tests, +4 GalleyCore storage tests (114 GREEN). Builds on ADR-0005, ADR-0009, ADR-0010, ADR-0024.
