# ADR-0029 — Import is a separate, best-effort process that produces the `.galley` contract

## Context

Writers arrive with manuscripts already written elsewhere — Microsoft Word (`.docx`), Scrivener projects (`.scriv`), PDFs, plain text / Markdown / Fountain, RTF/ODT, Google Docs exports. Galley needs to ingest them.

The hard problem is **not the text** — it is the **structure**. Galley's model is a flat block stream in a closed vocabulary ({paragraph, sceneBreak, setPiece, figure}) plus a late-bound chapter overlay ([ADR-0005](0005-chapters-as-overlay-not-containers.md), [ADR-0009](0009-closed-vocabulary-codes-justify-to-reveal.md)). Import must detect **breaks** — chapter and section boundaries, scene breaks, set-pieces, figures — in the source and map them onto that model. Source formats carry wildly different amounts of real structure:

- **Scrivener** — a binder (project XML) of folders/documents, each with RTF content. The binder *is* the chapter/scene tree: highest structural fidelity.
- **Word `.docx`** — OOXML with paragraph styles (`Heading 1/2` → chapter/section), explicit page/section breaks, centered ornament lines (`* * *`) → scene breaks, embedded images → figures. High fidelity when the author used styles; low when they hand-formatted with blank lines and manual centering.
- **PDF** — layout, not structure. Text extraction is lossy; breaks can only be *inferred* from whitespace, font size, and position. Lowest fidelity.
- **Plain text / Markdown / Fountain** — little structure, or convention-based (Markdown `#`, Fountain scene headings).

Import is therefore inherently **lossy and heuristic**, and *where it lives* (inside the editor vs. a separate tool) is open.

## Decision

1. **Import produces the `.galley` contract — it is the mirror image of typesetting.** [ADR-0024](0024-authoring-and-typesetting-are-separate.md) made the `.galley` format the contract and typesetting a separate process that *consumes* it. Import is the symmetric process that *produces* it: a foreign document in → a `.galley` bundle (`prose.txt` + `sidecar.json`, [ADR-0007](0007-plain-text-files-chapters-in-sidecar.md)) out, expressed entirely in the closed vocabulary (ADR-0009). Import is **not** part of `GalleyCore`; the core stays UI-free and format-free ([ADR-0002](0002-swift-core-mac-first-rust-deferred.md)).

2. **Best-effort with mandatory human review — never silent guessing.** An importer detects breaks heuristically, maps what it can confidently classify, and **flattens everything else to plain paragraphs — never dropping the writer's text.** The output is a *draft* `.galley` the writer then reviews and corrects in Galley's reveal / chapter-slicing surface ([ADR-0006](0006-reveal-is-a-projection-and-slicing-surface.md)), which already exists for exactly this structural verification. Import quality degrades gracefully: the worst case is a wall of paragraphs the writer chapters by hand, not a failed or corrupt import.

3. **Importers are independent and format-specific, ranked by structural fidelity.** Each source format is its own importer with its own break-detection strategy (Scrivener: binder tree; Word: paragraph styles + breaks; PDF: layout heuristics). They share one target — the `.galley` writer — but no source logic. Highest-fidelity, most-requested formats first; **PDF is explicitly last-resort.**

4. **Likely a separate tool (CLI / importer library), not the editor.** Import is a batch, one-shot transform, not interactive editing. Packaging it as a standalone executable / library that emits a `.galley` keeps the editor focused and lets import evolve independently — new formats, better heuristics — without touching the authoring app. (Exact packaging — standalone CLI vs. an in-app "Import…" that shells out to it — is a follow-up; the *boundary* is what this ADR fixes.)

## Consequences

- **Break detection is the central difficulty and is per-format.** Each importer gets its own design (its own ADR/phase) recording its heuristic — e.g. docx `Heading 1` → chapter cut; a short centered line → `sceneBreak`; an embedded image → a `figure` block (ADR-0027) with the file extracted into `images/`. Galley's job *after* import is to make the detected structure trivially reviewable and fixable in the reveal pane.
- **Import cannot corrupt the model.** It only ever writes the `.galley` contract, so the same `parse`/round-trip invariants (ADR-0007) gate its output. A bad importer yields a *valid but poorly-structured* document, never an invalid one.
- **Heavy format dependencies stay out of the core and the editor.** A `.docx`/OOXML reader, a PDF text extractor, an RTF parser, a Scrivener binder parser — each lives in its importer, never burdening `GalleyCore` (ADR-0002) or the SwiftUI app (ADR-0011).
- **Import is one-directional by design.** Foreign format → `.galley`. Galley does not export back to Word/PDF; producing finished output is the typesetter's separate concern (ADR-0024).
- **Lossy edges are reported, not hidden.** Constructs Galley has no vocabulary for — footnotes, comments, tracked changes, arbitrary character styling — are flattened or dropped, and the import should surface a short report of what it could not represent, so the writer knows what to re-check.

### Open (follow-up decisions, not settled here)

- Exact tool packaging: standalone CLI vs. in-app "Import…" shell-out.
- Format priority order. Recommendation: **Scrivener and Word first** (highest fidelity, most common for novelists), then plain/Markdown/Fountain, **PDF last** (lossy).
- Whether a dedicated post-import "confirm the breaks" review affordance is added beyond the existing reveal pane.
- Image/figure extraction depth (embedded vs. linked; OCR of image-only PDFs is out of scope for v1).

## Session

(import track, future) 2026-06-07 — recorded the import architecture: import is the inverse of typesetting (it *produces* the `.galley` contract, ADR-0024), best-effort and human-reviewed (ADR-0006), format-pluggable and ranked by structural fidelity, living outside `GalleyCore` and likely as a separate tool. Per-format importer designs and the exact packaging are deferred to their own phases/ADRs.
