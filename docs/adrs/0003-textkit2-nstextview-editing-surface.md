# ADR-0003 — TextKit 2 / NSTextView as the editing surface

## Context

A native Mac editor ([ADR-0001](0001-native-not-html-electron.md), [ADR-0002](0002-swift-core-mac-first-rust-deferred.md)) needs a text-layout engine. The choice is between rolling custom layout and adopting Apple's modern text stack. The product's hard requirements — typing-simplicity input hooks, a reveal toggle that renders codes as decorations, and a clean separation of content from layout — map directly onto TextKit 2 capabilities.

## Decision

Use TextKit 2 + `NSTextView`, hosted in SwiftUI via `NSViewRepresentable`, rather than rolling custom layout.

## Consequences

- TextKit 2 already separates content (`NSTextContentStorage`, `NSTextParagraph`) from layout (`NSTextLayoutManager`), provides input hooks for the typing rules (§8), and supports custom decoration rendering for the reveal toggle.
- We are bound to Apple's text stack and its quirks; this surface is part of the Mac-only UI layer and does not run on the headless core.

## Session

ca5fff (2026-06-05) — extracted from overview §12, ADR-003.
