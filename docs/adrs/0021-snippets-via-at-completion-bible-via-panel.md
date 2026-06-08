# ADR-0021 — Snippets via `@`-completion; the bible via a read-only side panel

> **Status note (session f1d4c9):** the **bible half** of this ADR — the read-only
> bible side panel (decision 2) and its `BibleIndex`/`BiblePane` — is **superseded by
> [ADR-0036](0036-notes-capture-inbox-replaces-bible.md)** (Notes capture inbox). The
> **snippets half** (decision 1, `@`-completion) remains in force.

## Context

Phase 5 was first built as the overview's §9 literal reading suggested: inline `@`-bible completion that inserted an entity's canonical name, an `NSPopover` **peek** of the entity's notes (Tab), a **flick-to-last** keybinding (Cmd-Y), and a "scene remembers its references" annotation. In live use this fought the drafting flow: reading reference notes through transient inline popovers was fiddly to position and dismiss, and the remembered-references mechanism added surface without aiding writing. The writer's actual two needs are distinct: **insert reusable text** quickly while typing, and **read reference material** without losing the cursor.

## Decision

Split the two needs:

1. **`@`-completion inserts snippets** — reusable text blocks from `snippets/*.txt` in the package. Typing `@` lists snippet names; choosing one inserts its body (multi-line bodies become successive paragraphs). `@` no longer touches the bible.
2. **The bible is a read-only side panel** — a toggleable, searchable panel (Cmd-Shift-B), peer to the reveal and fields panels: a search box, the entry list, and the selected entry's full note. Reading references is deliberate browsing, not an inline interruption.

**Removed:** inline `@`-bible completion, the peek overlay, flick-to-last (Cmd-Y), and the scene-references annotation (`SceneReferences`).

## Consequences

- `@` is now unambiguously the **snippet** trigger; references are never inserted by `@`. The closed completion-popover mechanism is reused as-is for snippets.
- Reading the bible is panel-based and persistent (stays open while you write), replacing the transient peek. `BibleIndex` now feeds the panel's search instead of inline completion.
- "Scene remembers its references" is dropped — there is no per-scene reference memory in v1. If revived, it would attach to the panel, not to inline peeking.
- The bottom-bar buttons reveal their keyboard shortcuts while Command is held (a small discoverability aid added alongside this work).
- This reverses the inline-reference reading of §9; future reference features should extend the panel, not re-add inline reference popovers.

## Session

9ffa6f (2026-06-05) — Build Step 2, Phase 5.
