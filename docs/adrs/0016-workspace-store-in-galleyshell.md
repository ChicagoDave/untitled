# ADR-0016 — The workspace/buffer store lives in GalleyShell, AppKit-free

## Context

Build Step 3 replaces the window's single `DocumentModel` with a workspace holding
an ordered set of open buffers plus a current index. The workspace owns the risky
logic of the feature — New/Open/switch/close, index bookkeeping, and auto-save on
switch — so that logic must be **unit-testable**.

[ADR-0011](0011-editor-shell-separate-swiftpm-package.md) §Consequences fixes the
testability boundary: "`GalleyShell` (pure Foundation + GalleyCore) is unit-testable
headlessly; the `Galley` executable is the only target that needs a window server."
The original `DocumentModel` lived in the executable and mixed two concerns: AppKit
file panels (`NSOpenPanel`/`NSSavePanel`) and headless buffer state + bundle I/O.
Putting the new workspace store in the executable alongside it would have made its
tests depend on a window server — a direct conflict with ADR-0011 (caught in plan
review before implementation).

## Decision

Split `DocumentModel`'s two concerns and place the testable half in `GalleyShell`:

- **`WorkspaceDocument`** (GalleyShell) — one buffer's headless state: the live
  `Document`, its `fileURL`, a `status`, `hasContent`, and `load`/`persist`/`apply`/
  `setMetadata`/chapter-overlay mutations. No AppKit, no SwiftUI.
- **`WorkspaceModel`** (GalleyShell) — the `@Observable @MainActor` store owning
  `[WorkspaceDocument]` + `currentIndex`, with `new`/`open(url:)`/`switchTo`/`close`.
  No AppKit, no SwiftUI.
- The `Galley` executable keeps only the **panel-runner** (`FilePanels` plus a
  `WorkspaceModel` extension) that presents `NSOpenPanel`/`NSSavePanel` and hands the
  chosen URLs into the headless store. `DocumentModel` is removed.

Observability uses the `Observation` module (`@Observable`), which is part of the
toolchain, not SwiftUI — so the store stays headless while the SwiftUI view tree
still observes it directly.

## Consequences

- `WorkspaceModel`/`WorkspaceDocument` are tested in `GalleyShellTests` with no
  window server — New/Open/switch/auto-save/hasContent/load/persist all have
  behavioral tests that assert on real state, including disk round-trips through the
  real `DocumentBundle` (no stub). This satisfies ADR-0011 without amending it.
- GalleyShell's charter widens slightly: it is no longer only file-pair I/O but also
  hosts app-layer document/window **state**. Its invariant stays "Foundation +
  GalleyCore + Observation; no AppKit/SwiftUI." The package header records this.
- Every view that bound to `DocumentModel` (`ContentView`, `DocumentTextView`,
  `InputController`, `RevealPane`, `MetadataPanel`) now binds to `WorkspaceDocument`.
  SwiftUI-only conveniences that cannot live in a headless type — notably the
  metadata `Binding` — are provided by a thin executable-side extension over the
  headless `setMetadata` mutator.
- `WorkspaceModel.current` relies on the invariant that the store is never empty and
  `currentIndex` is always in range (upheld by [ADR-0015](0015-unsaved-buffer-and-last-buffer-policy.md)'s
  last-buffer-replacement rule).
- The dependency edge is unchanged: GalleyShell → GalleyCore → Foundation, and the
  executable → GalleyShell. Nothing UI ever flows back into GalleyCore
  ([ADR-0002](0002-swift-core-mac-first-rust-deferred.md)).

## Session

b8b0bd (2026-06-05) — Build Step 3, Phase W1.
