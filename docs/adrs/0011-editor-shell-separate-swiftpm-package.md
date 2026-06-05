# ADR-0011 — The editor shell is a separate SwiftPM package depending on the core

## Context

Build step 2 (the macOS editor shell) is the first AppKit/SwiftUI code in the
project. It must sit on top of the headless `UntitledCore` library
([ADR-0002](0002-swift-core-mac-first-rust-deferred.md)) without ever dragging UI
types back into the core — dependencies flow inward only (DEVARCH rule 8). The
`core/Package.swift` manifest already declares, in its header, that it is UI-free
and that "the macOS shell consumes this package later."

Three structures were considered: (A) a separate SwiftPM package depending on
`core/`; (B) an additional executable target inside `core/Package.swift`; (C) an
Xcode project producing a bundled `.app`.

## Decision

Use a **separate SwiftPM package** at `app/`, depending on the local `core/`
package via `.package(path: "../core")`. Within `app/`, split the shell into a
pure, headlessly-testable library target (`UntitledShell`) and a thin
`@main` executable target (`UntitledApp`) that holds the AppKit/SwiftUI glue. The
app launches via `swift run` for development; producing a bundled, code-signed
`.app` is deferred to a later packaging concern.

Note: a path dependency's *package identity* is the directory name (`core`), so
product references are `.product(name: "UntitledCore", package: "core")`, not
`package: "UntitledCore"`.

## Consequences

- The core manifest stays UI-free and untouched; the boundary is enforced by the
  package graph itself — `UntitledCore` cannot import the shell because the
  dependency edge only points the other way (rule 8, ADR-0002, ADR-0004).
- The whole project remains on the `swift build` / `swift run` / `swift test`
  spine used since build step 1 — no Xcode project artifact to maintain, and CI
  can build and test without a GUI.
- `UntitledShell` (pure Foundation + UntitledCore) is unit-testable headlessly;
  the `UntitledApp` executable is the only target that needs a window server.
- The cost is deferred: `swift run` does not produce a sandboxed, code-signed
  `.app` bundle. When shipping, distribution metadata (Info.plist, entitlements,
  signing) must be added — likely as an Xcode wrapper or a SwiftPM bundler — and
  this ADR will need a follow-up.
- A bare SwiftPM executable launches without an activation policy; an
  `NSApplicationDelegate` sets `.regular` and activates on launch so the window
  appears during `swift run`.

## Session

6baa7e (2026-06-05) — Build step 2, Phase 1.
