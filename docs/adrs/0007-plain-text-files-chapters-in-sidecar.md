# ADR-0007 — Plain-text, writer-owned files; chapters in a sidecar

## Context

The writer must own the file, and the format must round-trip through the §4 model ([ADR-0004](0004-own-model-is-source-of-truth.md)). Because chapters are a movable overlay rather than containment ([ADR-0005](0005-chapters-as-stream-overlay-not-containment.md)), the prose must stay continuous on disk so it remains re-sliceable; chapter boundaries cannot be baked into the prose stream.

## Decision

Store prose as plain text — a Fountain-for-prose syntax (`.untitled`/`.md`-ish) — parsed into the model on load and serialized back on save. Store chapter cut-points (positions, titles, opener refs) in a separate sidecar. Introduce SQLite only if cross-scene search becomes slow at scale, never as the source of truth.

## Consequences

- Portability, diffability, and ownership; the prose stays continuous and re-sliceable.
- Two artifacts (prose + sidecar) must be kept in sync. The sidecar references cut anchors by stable block ID ([ADR-0010](0010-cut-anchoring-via-stable-block-ids.md)), not by prose position, so unrelated prose edits don't rot it.

## Session

ca5fff (2026-06-05) — extracted from overview §12, ADR-007.
