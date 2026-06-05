# ADR-0004 — Own document model is the source of truth (not NSAttributedString)

## Context

With TextKit 2 as the editing surface ([ADR-0003](0003-textkit2-nstextview-editing-surface.md)), the tempting shortcut is to let the platform's `NSAttributedString` *be* the document model. But the file format ([ADR-0007](0007-plain-text-files-chapters-in-sidecar.md)) and the reveal projection ([ADR-0006](0006-reveal-is-a-projection-and-slicing-surface.md)) both become ugly if the source of truth is a platform attributed string.

## Decision

Maintain the §4 domain model as the single source of truth. *Derive* the attributed string for display and the reveal projection as separate, pure functions over the model.

## Consequences

- Both views derive from one model and can never disagree — the property that makes reveal cheap ([ADR-0006](0006-reveal-is-a-projection-and-slicing-surface.md)).
- Keeps the core UI-free, satisfying [ADR-0002](0002-swift-core-mac-first-rust-deferred.md)'s portability constraint (`NSAttributedString` stays on the Mac side).
- A bridging layer (model ⇄ attributed string) is real engineering work we now own.

## Session

ca5fff (2026-06-05) — extracted from overview §12, ADR-004.
