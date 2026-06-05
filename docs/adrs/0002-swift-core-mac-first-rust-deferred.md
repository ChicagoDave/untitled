# ADR-0002 — Swift core, Mac-first; Rust extraction deferred

## Context

Given a native build ([ADR-0001](0001-native-not-html-electron.md)), the core domain logic could be written in a portable language (Rust) now to ease a future Windows/iPad port, or in Swift to stay close to the Mac platform. For a for-fun, donation-funded tool, cross-platform reach does not currently justify a two-language seam.

## Decision

Write the core in Swift and ship for Mac. Keep the core UI-free so it *could* move to Rust later without a rewrite.

## Consequences

- Single-language simplicity now; this is the "clean core, thin native shell" shape applied to text.
- The UI-free constraint is load-bearing for portability and for the headless-core build step — it is enforced by [ADR-0004](0004-own-model-is-source-of-truth.md) keeping the model independent of `NSAttributedString`.
- A future Windows/iPad port pays the Rust-extraction cost later, by design.

## Session

ca5fff (2026-06-05) — extracted from overview §12, ADR-002.
