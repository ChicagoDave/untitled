# ADR-0006 — Reveal is a projection, and doubles as the slicing surface

## Context

Reveal Codes worked in WordPerfect because the document had nothing hidden — the codes *were* the truth. With the own-model decision ([ADR-0004](0004-own-model-is-source-of-truth.md)), the model is the truth and views are pure functions over it, so a truth-view is nearly free. Separately, chapters are placed by dragging cut-points over the stream ([ADR-0005](0005-chapters-as-stream-overlay-not-containment.md)) — which looks exactly like editing reveal codes.

## Decision

Model reveal as one of two pure render functions over the model. The reveal pane, in chapter-edit mode, *is* the surface where the writer places and drags chapter cuts.

## Consequences

- Views can never diverge from truth (shared with [ADR-0004](0004-own-model-is-source-of-truth.md)).
- The debug/inspection surface and the book-structuring surface are the same object — the surface built to debug formatting is the surface you carve the book with.
- The reveal pane now carries two responsibilities (truth view + structural editor) and must mode-switch cleanly.

## Session

ca5fff (2026-06-05) — extracted from overview §12, ADR-006.
