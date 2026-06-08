# ADR-0009 — Closed vocabulary; every code must justify itself to the reveal

## Context

The death of a tool like this is scope creep (§2), and the WordPerfect pain being avoided is open "code soup." The constraint — a tiny, closed vocabulary the writer thinks in — is the art, not a limitation. New codes are cheap to add and expensive to live with, since every code shows up as an addressable object in the reveal ([ADR-0006](0006-reveal-is-a-projection-and-slicing-surface.md)).

## Decision

Fix the vocabulary: block set = Paragraph, SceneBreak, SetPiece; inline = italic; structure = chapter cut. Any addition must justify itself to the reveal before it enters the vocabulary.

## Consequences

- Keeps the reveal legible and the product focused; resists code-soup.
- Some writers will want more (small-caps, centered one-offs); these are handled as rare per-block presentation overrides, not vocabulary growth.
- The override hatch is itself bounded: modeled as a small **closed** `PresentationOverride` enum on `Block` (overview §4), empty by default, so "rare override" can't quietly become an open style system. Adding a case demands the same justification as any new code.
- Because italic is named inline vocabulary, an **explicit** italic mark (`Run.italic`) is itself a code and therefore surfaces in the reveal as addressable `[i]`/`[/i]` chips ([ADR-0006](0006-reveal-is-a-projection-and-slicing-surface.md): every code is an object). This is distinct from **derived** italic — a set-piece is italic by *kind*, not by a run mark, so it carries no `[i]` chips (matching the §7 verse example). The rule: only marks stored on the model are revealed; presentation derived from a block kind is not.

## Amendment — `blockQuote` added to `PresentationOverride` (BP1, 2026-06-06)

The Block Palette track lets writers define reusable structural blocks. The two existing overrides (`alignment`, `smallCaps`) cover a centered epigraph and a small-caps dateline, but not the most common *non-verse* structural block: a passage set off from the margin — an inscription, an epitaph, a quoted document. A scoped, **closed** addition of one case — `blockQuote` (symmetric margin inset + leading alignment) — is therefore adopted.

This is weighed against the reveal, ADR-0009's real gate (carry-forward plan-review tension #1). `blockQuote` passes for the same reason it does not introduce a new *class* of state: it is a stored model mark on `Block.overrides`, exactly like `smallCaps` and `alignment`. It is a single, legible, addressable code (`[quote]`) — not open style soup — and it is no less reveal-justified than the two overrides already in the enum. Surfacing per-block overrides as reveal chips at all is a pre-existing gap affecting all three overrides equally (today none of them emit chips); closing it is a separate, all-overrides follow-up, not something `blockQuote` newly creates or that this amendment regresses.

The addition is deliberately bounded: any *further* override case demands its own justification to the reveal, as this one did. Templates may carry only these closed tokens; an unknown token is a hard rejection in both the sidecar and the template parser ([ADR-0022](0022-block-template-file-format.md)).

## Amendment — `figure` added to the block vocabulary (LT4, 2026-06-07)

The fixed block set in the Decision above was Paragraph, SceneBreak, SetPiece. A fourth block kind — **`figure`** (an image *reference* + caption; [ADR-0027](0027-figure-block-shape-and-serialization.md)) — is adopted as a scoped, closed addition. It is the first growth of the *block set* itself (the `blockQuote` amendment grew the override hatch, not the block set), so it is recorded here to keep this ADR the single source of truth for the closed vocabulary.

It passes ADR-0009's real gate — justify to the reveal: a figure surfaces as a single addressable `[figure: <ref>]` chip the writer can see and delete, exactly as the other block codes do. It is not an open media system: actual image rendering, sizing, and placement are explicitly *not* Galley's job (they belong to the typesetter, [ADR-0024](0024-authoring-and-typesetting-are-separate.md)); Galley stores only the reference + caption as intent. Any *further* figure-related vocabulary (alt-text, layout hints, inline-run captions, multi-image figures) demands its own justification to the reveal, as this one did — none are adopted here.

## Session

ca5fff (2026-06-05) — extracted from overview §12, ADR-009.

54ff60 (2026-06-05) — added the explicit-vs-derived italic consequence after Phase 4's `revealProjection` made the distinction concrete (`[i]`/`[/i]` chips for `Run.italic`; none for kind-derived italic).

bf5f1f (2026-06-06) — Phase BP1: amended the closed `PresentationOverride` vocabulary with `blockQuote`; recorded the reveal justification. Shared the override wire codec across the sidecar and the template front-matter (rule 8b).

LT4-1 (2026-06-07) — amended the block set with `figure` (image ref + caption), justified to the reveal as a `[figure: <ref>]` chip; rendering/placement deferred to the typesetter (ADR-0024, ADR-0027).
