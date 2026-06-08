# ADR-0036: Notes — a capture inbox replaces the named-entry bible

## Context

The bible (ADR-0021) modeled the writer's reference material as **named entries** —
one `bible/<name>.md` file per entity (a "Character: Stephanie" note), browsed
read-only in a side panel and edited externally. In practice that imposes a schema the
writer has not yet formed: at the inspired, random moment a thought arrives, you do not
know whether it is a "character" or a "place" note, and you should not have to name a
file to keep it.

The writer's actual workflow is **capture first, organize by retrieval**: jot the
fragment, tag it with whatever `#words` fit, find it later by tag or text. That is a
commonplace book / zettelkasten model (tags over hierarchy), and it fits Galley's
keyboard-first, capture-in-flow ethos better than the named-entry bible did.

## Decision

Replace the named-entry bible with **Notes** — a numbered, tag-searchable capture
inbox. This **supersedes the bible half of ADR-0021**; the snippets-via-`@`-completion
half of ADR-0021 is unaffected and remains in force.

**Data model — a note is a freeform markdown blob, no front-matter.**
- Each note is a file `notes/NNNN.md` inside the `.galley` package (zero-padded, e.g.
  `notes/0014.md`), consistent with the per-file package-directory convention for
  auxiliary content (ADR-0020).
- **The filename is the permanent ID.** Numbers increment from 1, are never reused and
  never renumbered — not on sort, not on delete. The number is a stable anchor (and a
  future cross-reference target, `#42`). Sorting and filtering change the *view*, never
  the number.
- **A persisted high-water mark guarantees no reuse.** The next number is **not**
  `max(existing) + 1` — deleting the highest note would then hand its number to the next
  capture, breaking the permanence promise. Instead a plain-integer counter file
  `notes/.next` holds the high-water mark: capture reads it, names the file, writes it
  back incremented; deletion never lowers it. The counter lives as a package file (not in
  the GalleyCore sidecar), keeping the numbering app-layer. Bootstrap: if `.next` is
  absent (a hand-created `notes/` dir, or first run), it is seeded from
  `max(existing) + 1` once, then is authoritative.
- **Tags are inline `#hashtags`, anywhere in the body**, parsed out for the index.
  Nothing extra to fill in — they are part of the prose you capture.
- The file body is the entire note. No title line, no metadata. Trivial to export and
  to read in any editor; git-friendly.

**Browse — the Notes panel (renamed from Bible, ⌘⇧B).**
- A scrollable list of note rows, **newest-first by number** (the default sort).
- Each row shows: the **number**, the **derived tag chips**, the **first ~30 characters**
  of the body as a blurb, and a **`[+]` expander**.
- **Search-as-you-type** filters the list, scoring body + tags through the existing
  `FuzzyMatch` scorer.
- A **tag-filter row** (the distinct tags across all notes) narrows the list on click —
  this is what recovers the old named-bible lookup ("everything about #stephanie")
  without any upfront schema. Retrieval is first-class because a capture stream lives or
  dies on it.
- An expanded row is **inline-editable** (writes through to the `notes/NNNN.md` file and
  re-indexes on save) and offers **copy** (to paste the fragment into the prose editor).

**Capture — a chord from the prose editor**, not a panel trip.
- A keybinding (proposed ⌘⇧N) opens a fresh note at the next number with the cursor
  ready; type, save (⏎) or cancel (esc), and the caret returns exactly where it was in
  the prose. This is the flow-preserving capture that is the whole point.

## Consequences

- ADR-0021's bible model is retired. `BibleIndex`/`BiblePane` are replaced by a
  `NoteIndex`/`NotesPane`; `BibleEntry` (named, structured) gives way to a flat `Note`
  value (id, body, derived tags).
- **Retiring `Document.bible` is a sidecar *format* change, not a free cleanup.**
  Contrary to ADR-0020's "flagged, not actioned" framing (now amended), `Document.bible`
  is still **serialized**: `Storage.swift` writes and reads a `bible: [BibleDTO]` array in
  the sidecar JSON. Removing `Bible`/`BibleEntry`/`Document.bible` therefore edits
  `Storage.swift` (drop `BibleDTO` and the `bible` field) and its round-trip tests, and
  existing `.galley` sidecars' `bible` arrays become dead data ignored on decode — a
  deliberate, tolerable ADR-0007 format change. **The Notes track does touch GalleyCore**
  (this single deletion), even though it adds no new GalleyCore type.
- **Migration is a conversion, not a drop.** Each existing `bible/<name>.md` is converted
  to a `notes/NNNN.md` whose body is the entry's note text with the entry name prepended
  as a leading `#tag` (so "Stephanie" notes are findable by `#stephanie`); no writer
  content is lost. The `bible/` directory is then removed. For `examples/GrayHarbor.galley`
  the converted notes are replaced with a small set of hand-authored example notes. The
  named-bible reader is removed, not kept in parallel.
- Snippets (`@`-completion reusable boilerplate, ADR-0021) are a *different* concept and
  remain untouched — deliberate reusable text vs. captured fragments.
- A new capture keybinding enters the chord space (⌘⇧N proposed; verified against ⌘⇧I
  fields, ⌘⇧B notes, ⌘/ reveal, ⌘; palette, ⌘⇧Z redo).
- Notes are plain markdown with no front-matter, so export is the files themselves and
  the on-disk format (ADR-0007) is unchanged in spirit (auxiliary content stays plain).
- Deferred: cross-note linking (`#42` as a reference), richer "insert into prose" beyond
  copy/paste, and any non-tag organization. These are explicitly out of v1.

## Worked scenario & rejections

**End-to-end (capture → retrieve):** the writer is drafting with the caret mid-sentence.
The high-water mark in `notes/.next` is `14`. They press ⌘⇧N, type
`David keeps a list of final #actions to execute. #david`, press ⏎. The store writes
`notes/0014.md` with exactly that body, bumps `notes/.next` to `15`, re-indexes, and the
prose caret returns to its original position. Opening the Notes panel (⌘⇧B) shows the new
note **first** (newest-first), row `#14  #actions #david · David keeps a list of fina…`.
Typing `actions` in search narrows to it; clicking the `#david` chip narrows to every
`#david` note.

**Rejections:**
- **Empty capture** (no non-whitespace body) on ⏎ or esc → **no file written**, `.next`
  unchanged. An accidental ⌘⇧N never litters the inbox or burns a number.
- **Missing `notes/` directory** on open → the index loads empty (normal), exactly like an
  absent `bible/` did; the directory is created lazily on the first save.
- **Unreadable / malformed note file** → that file is skipped (not fatal); the rest of the
  index loads. (A note is freeform text, so there is no "malformed body" — only an
  unreadable file.)
- **`notes/.next` absent or non-integer** → seeded once from `max(existing number) + 1`,
  then authoritative.

## Session

f1d4c9 (2026-06-07) — design converged in conversation with the writer; supersedes the
bible half of ADR-0021. ADR-reviewed before implementation; the high-water-mark numbering
and the `Document.bible` serialization reality were added as a result of that review.
