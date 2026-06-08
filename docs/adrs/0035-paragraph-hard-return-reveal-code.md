# ADR-0035: structural-whitespace reveal codes (`[p]` hard return, `[sp]` section spacing)

## Context

The Reveal Codes surface (ADR-0030/0032) showed every structural element of a
document as an addressable chip — `[SceneBreak]`, `[Verse]`/`[/Verse]`, `[Chapter]`,
`[i]`/`[/i]`, override chips, `[figure: …]` — with one exception: the paragraph
boundary itself. A run of plain paragraphs rendered as bare lines of text with no
visible marker of where one paragraph ended and the next began. In a true
WordPerfect-style Reveal Codes view, the paragraph/hard-return mark is the most
fundamental code of all; its absence made the reveal stream read as undifferentiated
prose rather than as the document's structure.

`CodeID` (GalleyCore) is a **closed** vocabulary (ADR-0009) — every reveal chip is a
deliberate, enumerated member, not an open extension point. Adding a paragraph code
therefore is a vocabulary decision, not an incidental rendering tweak, and the LT5
plan-review gate explicitly guarded against expanding this vocabulary without
deliberation. This ADR is that deliberation.

## Decision

Add two closed members for the document's *structural whitespace* — the boundaries a
reader sees as blank space but that previously had no reveal marker:

1. **`CodeID.paragraph(BlockID)` — `[p]`, the hard-return terminator.** Emitted at the
   **end** of every `.paragraph` block, after the block's text and any inline chips.
2. **`CodeID.sectionSpace(BlockID)` — `[sp]`, the section-opener spacing.** Emitted
   **after a boundary cut's title** (a `[Chapter]`/`[Prologue]`/… with no in-block
   offset), before the body prose, marking the vertical space a section break opens
   between its heading and the body. Without it the reveal mashed the heading into the
   body (`[Chapter]Chapter 1In the event…`); now the title is bracketed by chips
   (`[Chapter]Chapter 1[sp]In the event…`).

Both are emitted in **both** projections — `revealProjection()` (the flat
`[RevealToken]` stream, GalleyCore/`Reveal.swift`) and `revealSegments(of:)` (the
model-annotated stream, GalleyShell) — at the same position, so the drift guard
(`RevealSegmentTests`, ADR-0032) stays honest: the two projections' `CodeID` order
remains identical (the section title is *text*, not a code, so it does not affect that
order).

Scope is deliberately narrow:

- **`[p]` on paragraph blocks only.** Scene breaks, set-pieces, and figures already
  carry their own terminal codes (`[SceneBreak]`, `[/Verse]`, `[figure: …]`); a hard
  return is a paragraph concept. An *empty* paragraph still emits its `[p]`.
- **`[sp]` on boundary section cuts only.** A plain paragraph with no break emits no
  `[sp]`; a mid-paragraph cut (which splits text inline) does not either — the spacing
  is the *opener* of a section, so it attaches to a block-boundary cut.
- **Display-only in v1.** Both are non-editable chips the caret steps over. Deleting
  `[p]` would mean a paragraph **merge**; `[sp]` spacing is *derived* from the break, so
  it is not independently deletable. Both map to `.deferred` in
  `revealDeleteAction(…)` — the same deferred class as mid-block `[Chapter]` and
  set-piece `[line]` deletion (ADR-0034) — and the surface ignores a delete gesture on
  them.

## Consequences

- The reveal stream now makes paragraph and section-opener structure visible, matching
  the WordPerfect mental model the surface is modeled on.
- The closed reveal vocabulary grows by exactly two members. Any future surface that
  switches exhaustively over `CodeID` (the code→event mapping, the caret-after-delete
  resolver) must handle `.paragraph` and `.sectionSpace`; both were updated here.
- Neither `[p]` nor `[sp]` is serialized — both are pure projection artifacts derived
  from block structure, like every other reveal code. The on-disk format (ADR-0007) is
  unchanged.
- A future session may promote `[p]` from display-only to deletable by mapping its
  deletion to a paragraph-merge reducer event; the `CodeID`s and both projections are
  already in place, so that change is local to `revealDeleteAction` and the surface.
- Existing exact-sequence reveal tests were updated to include the trailing `[p]` and
  the post-title `[sp]`; focused tests assert each marker (incl. the empty-paragraph
  case and the no-break case) and that each deletion is deferred.

## Session

f1d4c9 (2026-06-07) — follow-up to LT5-3, on user request to display paragraph codes
in the Reveal Codes pane.
