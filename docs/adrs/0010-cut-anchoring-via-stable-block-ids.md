# ADR-0010 — Cut anchoring via stable block IDs

## Context

Chapters are a movable overlay of cut-points over the block stream ([ADR-0005](0005-chapters-as-stream-overlay-not-containment.md)), persisted to a sidecar ([ADR-0007](0007-plain-text-files-chapters-in-sidecar.md)). The §4 model anchors a cut by **array index** (`ChapterCut.beforeBlock: Int`) plus a character offset (`offsetInBlock: Int?`). Both are *positional*, and positions are fragile under the one activity the product exists for: continuous editing of continuous prose.

- Insert or delete a block anywhere above a cut and every `beforeBlock` index shifts — the sidecar now points at the wrong block.
- Edit text before a mid-block cut and its `offsetInBlock` points at the wrong character.

The sidecar rots against the prose silently, with no error to catch it. The multi-ADR seam review (session ca5fff) flagged this as the one design question to resolve before the headless core is written, because it shapes the `ChapterCut` type that [ADR-0004](0004-own-model-is-source-of-truth.md)'s model, [ADR-0005](0005-chapters-as-stream-overlay-not-containment.md)'s overlay, and [ADR-0007](0007-plain-text-files-chapters-in-sidecar.md)'s persistence all hang off.

## Decision

Anchor every cut to a **stable block identity**, not a positional index.

- Each `Block` carries an immutable `BlockID`, assigned at creation and preserved for the block's lifetime.
- A `ChapterCut` references `(blockID, offset)`: `offset` is a character index within that block, or `nil` for a block-boundary cut. Array indices remain a *derived, render-time convenience* and are never persisted.
- IDs come from a **monotonic per-document counter** on `Document`, not UUIDs or timestamps — deterministic, diff-friendly in the sidecar, and trivially testable in the pure core.

Block-lifecycle rules (owned by the editing layer, exposed by the core):

- **Split** (Enter mid-paragraph): the original block keeps its ID; the new trailing block gets a fresh ID. A cut whose offset falls in the trailing half re-anchors to the new block.
- **Merge** (delete at a boundary): the first block's ID survives; the second is retired. Cuts anchored to the retired block re-anchor to the survivor at the merge offset.
- **Delete** (block removed entirely): its ID is retired; an anchored cut relocates to the nearest surviving block boundary (or is dropped if the document empties). This is the explicit teardown the seam review found missing.
- **Same-block edits**: insert/delete before a cut's `offset` shifts that offset; the editing layer adjusts affected same-block cut offsets in the same edit event (cheap — blocks are small).

## Consequences

- Cuts survive insertion, reordering, and deletion of *unrelated* blocks — the sidecar no longer rots on edits elsewhere in the stream. This is what makes "slice it later" safe across a long drafting session.
- The model gains a `BlockID` on every block, and serialization ([ADR-0007](0007-plain-text-files-chapters-in-sidecar.md)) must persist block IDs (the sidecar references IDs, not indices). The prose file stays clean; IDs live with the structure, not the prose.
- The split/merge/delete/same-block-edit rules become part of the core's contract and need behavioral tests — each rule is a `DOES`/`REJECTS WHEN` line.
- Resolves the dangling-cut lifecycle gap from the seam review: every block-teardown path now has a defined cut-relocation rule.
- Refines [ADR-0005](0005-chapters-as-stream-overlay-not-containment.md) and supersedes the positional-anchor detail of the §4 `ChapterCut` (`beforeBlock: Int` → `blockID: BlockID`). The overview §4 should be updated to match.
- Small cost: ID generation and a retirement/relocation pass on structural edits. Bounded and deterministic.

## Open question

- **Intra-block robustness.** `(blockID, offset)` is fully stable against cross-block edits but still positional *within* a block. The same-block-edit rule keeps it correct during live editing, but an external hand-edit of the prose file between sessions could still skew a mid-block offset. Acceptable for v1 (mid-block cuts are placed in the reveal surface, not by hand-editing prose); revisit only if hand-editing mid-cut prose becomes a real workflow.

## Session

ca5fff (2026-06-05) — authored to resolve the BLOCKER from the ADR-0004/0005/0006/0007 seam review.
