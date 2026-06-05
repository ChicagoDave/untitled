# ADR-0009 — Closed vocabulary; every code must justify itself to the reveal

## Context

The death of a tool like this is scope creep (§2), and the WordPerfect pain being avoided is open "code soup." The constraint — a tiny, closed vocabulary the writer thinks in — is the art, not a limitation. New codes are cheap to add and expensive to live with, since every code shows up as an addressable object in the reveal ([ADR-0006](0006-reveal-is-a-projection-and-slicing-surface.md)).

## Decision

Fix the vocabulary: block set = Paragraph, SceneBreak, SetPiece; inline = italic; structure = chapter cut. Any addition must justify itself to the reveal before it enters the vocabulary.

## Consequences

- Keeps the reveal legible and the product focused; resists code-soup.
- Some writers will want more (small-caps, centered one-offs); these are handled as rare per-block presentation overrides, not vocabulary growth.

## Session

ca5fff (2026-06-05) — extracted from overview §12, ADR-009.
