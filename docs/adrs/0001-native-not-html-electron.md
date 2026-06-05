# ADR-0001 — Native, not HTML/Electron

## Context

Untitled is, by weight, ~90% a text-editing engine: auto-indent, the reveal toggle, peek overlays, and the `@`-bible all ride on the editing surface. The first platform question is what substrate to build that surface on. A web/Electron shell would buy cross-platform reach for free, but the precise text mechanics that *are* the product would be implemented on top of `contenteditable`.

## Decision

Build natively. Reject web/Electron.

## Consequences

- `contenteditable` is the worst substrate for precise text mechanics; avoiding it removes a permanent source of friction on exactly the behaviors that define the product.
- We give up free cross-platform reach. The product is Mac-only at first (see [ADR-0002](0002-swift-core-mac-first-rust-deferred.md) for the deferred extraction path).

## Session

ca5fff (2026-06-05) — extracted from overview §12, ADR-001.
