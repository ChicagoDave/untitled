# ADR-0012 — `displayProjection` emits pure tokens in the core; attribution lives in the shell

## Context

The reading view needs a render function over the model, the companion to
`revealProjection` ([ADR-0006](0006-reveal-is-a-projection-and-slicing-surface.md):
"two pure render functions over the model"). The open question for build step 2
was *where* it lives: entirely in the macOS shell returning an
`NSAttributedString` directly, or in the headless core returning plain values
that the shell later attributes.

The core is deliberately UI-free ([ADR-0002](0002-swift-core-mac-first-rust-deferred.md)),
and `revealProjection` already established the pattern of projecting to a plain
token enum (`RevealToken`) with no rendering types.

## Decision

`displayProjection` lives in `UntitledCore` and returns a pure `[DisplayToken]`
stream — `paragraph` / `sceneBreak` / `setPieceLine` / `chapterStart`, carrying
`DisplaySpan`s and the block's `PresentationOverride`s. Tokens name display
*roles*, not typography. A separate `Attribution` module in the shell maps
`[DisplayToken]` → `NSAttributedString`, and is the only place concrete type is
decided (body indent, verse centering and italic, the scene-break ornament,
chapter headings, small-caps).

Set-piece italic is *derived* from the line's `kind` in the attribution step (a
verse renders italic); only an explicit `Run.italic` mark sets `DisplaySpan.italic`
— consistent with the explicit/derived distinction in
[ADR-0009](0009-closed-vocabulary-codes-justify-to-reveal.md).

## Consequences

- The core stays headlessly testable: `displayProjection` is asserted on exact
  token sequences (chapter splicing, mid-paragraph offset splits, italic
  preservation) with no AppKit in the test target.
- Reveal and display are now symmetric — both are pure `Document` → `[…Token]`
  functions; a reader of one understands the other.
- The closed typographic vocabulary (fonts, indents, ornaments) is isolated in
  one shell file (`Attribution`), so a typographic change never touches the model
  and a model change cannot smuggle in a font.
- The cost: two representations to keep in step (token role ↔ attribution case).
  A new display role requires a token case *and* an attribution arm — the same
  two-sided cost `RevealToken` already carries, and the type checker flags a
  missing arm.

## Session

6baa7e (2026-06-05) — Build step 2, Phase 2.
