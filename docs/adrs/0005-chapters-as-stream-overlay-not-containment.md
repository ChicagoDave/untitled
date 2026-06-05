# ADR-0005 — Hybrid model; chapters are a stream-overlay, not containment

## Context

Every other tool — Scrivener, Ulysses, Word's outline — models chapters as *containers* of scenes: a tree. Untitled's defining writer-device is "slice it later": draft continuous logical units, then cut chapters at emotional/action peaks that deliberately do *not* align with the logical seams (the cliffhanger illusion). A containment tree cannot express a boundary that crosses its own contents.

## Decision

Use a hybrid model: a small closed tree at the inline/block layers, a flat *stream* at the block layer, and chapters as a movable cut-point **overlay** that references positions in the block stream — possibly mid-block.

## Consequences

- The writer's own habit ("slice at the peaks later") casts the deciding vote in the stream-vs-tree debate; this is the central decision of the design (§6).
- Rendering must splice cuts at walk time; chapter numbering is *computed*, never stored as structure.
- Enables the convergence in [ADR-0006](0006-reveal-is-a-projection-and-slicing-surface.md): a chapter cut is just a `[Chapter Break]` code in the reveal view.
- The file format ([ADR-0007](0007-plain-text-files-chapters-in-sidecar.md)) stores cuts in a sidecar so the prose stays continuous and re-sliceable.
- *How* a cut anchors to the stream (so it survives prose edits) is refined by [ADR-0010](0010-cut-anchoring-via-stable-block-ids.md): stable block IDs, not array indices.

## Session

ca5fff (2026-06-05) — extracted from overview §12, ADR-005.
