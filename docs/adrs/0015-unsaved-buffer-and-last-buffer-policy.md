# ADR-0015 — Unsaved-buffer and last-buffer policy for the multi-project workspace

## Context

Build Step 3 makes the window hold several open projects at once as in-memory
buffers, switched by keyboard (Cmd-N new, Cmd-O open, Cmd-1..9 slots, Cmd-W
close). Two lifecycle questions have no obviously-right answer and would otherwise
be re-litigated every session:

1. A buffer created by **Cmd-N has no file yet**. What happens to it when the user
   switches away, and when they close it? Writing a temp file would pollute the
   user's disk with `Untitled` folders; prompting on every switch would make the
   keyboard-driven workflow miserable.
2. **Closing the last buffer** (Cmd-W on the only open project) — does the window
   quit, or stay alive empty?

The workspace also auto-saves on switch ([ADR-0016](0016-workspace-store-in-galleyshell.md)),
which removes the data-loss concern for *file-backed* buffers but not for buffers
that have never been saved.

## Decision

**Unsaved-New buffers live in memory only.** A buffer with no `fileURL` is never
written to a temp file and never prompts on switch-away — it simply stays in
memory. It is offered a save/discard choice only at **close** time, and only when
it actually `hasContent` (any run carries non-empty text). A pristine blank
(zero text) is discarded silently. `hasContent` is the gate.

**Auto-save on switch fires only for file-backed buffers.** `switchTo`/`new`/`open`
persist the *outgoing* buffer through `DocumentBundle` if and only if it has a
`fileURL`; an unsaved buffer is left untouched.

**Closing the last buffer replaces it with a fresh blank, never quits.** Cmd-W on
the only open project leaves the window showing a new empty buffer. Quitting is
Cmd-Q — a separate, explicit action.

## Consequences

- No surprise temp-file pollution; the disk only ever holds bundles the writer
  deliberately saved. The cost is that an unsaved buffer's content is RAM-only
  until first save — acceptable because close prompts before discarding content.
- The save/discard prompt is concentrated at exactly one moment (close-with-
  content), keeping switch and new/open silent and fast for the keyboard workflow.
- `hasContent` becomes load-bearing: it is the single predicate deciding silent
  discard vs. prompt, so it must count text accurately (it ignores text-free
  blocks like scene breaks). It is unit-tested.
- Cmd-W can never accidentally quit the app from the last document; the window is
  always live with at least one buffer. This makes "the workspace always has a
  current buffer" an invariant other code (e.g. `WorkspaceModel.current`) relies
  on — see [ADR-0016](0016-workspace-store-in-galleyshell.md).
- The close-time save/discard sheet is AppKit/SwiftUI and lives in the `Galley`
  executable; the GalleyShell `close(index:)` only *signals* unsaved content and
  never presents UI (implemented in Phase W2).

## Session

b8b0bd (2026-06-05) — Build Step 3, Phase W1 (policy decided; close-prompt
mechanics land in Phase W2).
