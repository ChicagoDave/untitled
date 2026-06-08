# ADR-0020 — Reference indexes (bible, snippets) live in the app layer, over package files

## Context

The §9 reference system has two sources: the **bible** (one Markdown note per entity) and **snippets** (reusable text blocks). Two questions had to be settled: **where** the indexes live, and **what** their entries are stored as.

- `GalleyCore` carries `Bible` / `BibleEntry` value stubs on `Document`, "for later `@`-complete to index against."
- But the chosen source of truth (confirmed with the user) is **files inside the `.galley` package** — `bible/aldous-finch.md`, `snippets/dateline.txt` — names derived from filenames. That is file I/O, which the pure core must not do ([ADR-0002](0002-swift-core-mac-first-rust-deferred.md)).

## Decision

`BibleIndex` and `SnippetIndex` live in **`GalleyShell`** (the app layer). They read `bible/*.md` and `snippets/*.txt` from the package directory and own the fuzzy-match logic, which is factored into a shared pure `FuzzyMatch` (humanise + subsequence scorer). `BibleIndex` **reuses `GalleyCore.BibleEntry`** as its value type; `SnippetIndex` defines a small `Snippet` value. `GalleyCore` is left unchanged — its `Bible` stub stays unused by this path. Reference content is **not** stored in the sidecar; the package files are the writer-owned source (consistent with ADR-0007's spirit).

## Consequences

- File I/O stays out of the pure domain core (ADR-0002); both indexes carry no AppKit and are headlessly tested in `GalleyShellTests` (ADR-0011).
- `GalleyCore.BibleEntry` is reused (no duplicate wire type); `GalleyCore.Bible` (the container on `Document`) is now redundant for this feature — a later cleanup may remove `Document.bible` or wire it. **Amendment (Notes track, ADR-0036, NT1/NT3, session f1d4c9):** this cleanup is now actioned — `Bible`/`BibleEntry`/`Document.bible` are retired by the Notes track. Note this is **not** free: `Document.bible` is serialized (`Storage.swift` writes/reads a `bible: [BibleDTO]` sidecar array), so its removal edits `Storage.swift` and its round-trip tests and is a deliberate ADR-0007 format change (old sidecars' `bible` arrays are ignored on decode).
- The indexes are rebuilt fresh from disk on open and after save (`WorkspaceDocument.reloadIndexes()`); there is no in-model copy to keep in sync.
- Matching is a pure subsequence scorer over names; no external dependency, no AI (ADR-0008). The UX split that consumes these indexes — `@` for snippets, a panel for the bible — is recorded in [ADR-0021](0021-snippets-via-at-completion-bible-via-panel.md).

## Session

9ffa6f (2026-06-05) — Build Step 2, Phase 5.
