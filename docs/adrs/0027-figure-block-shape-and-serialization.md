# ADR-0027 — Figure block: shape and serialization

## Context

Galley needs to let a writer place an image *reference* with a caption anywhere in the flat block stream, shown as a placeholder while drafting (the parked "Images" feature). The authoring/typesetting boundary ([ADR-0024](0024-authoring-and-typesetting-are-separate.md)) is the governing constraint: Galley records the *intent* — which image, what caption, where in the stream — and the typesetter places and sizes the real image. Galley never loads or renders the image.

Two shape/serialization questions had to be settled before touching `GalleyCore`:

1. What does the block carry, and how minimal can it be (ADR-0009 closed vocabulary)?
2. How does it round-trip through the prose + sidecar pair ([ADR-0007](0007-plain-text-files-chapters-in-sidecar.md)) given a figure has no ordinary prose text?

## Decision

**Block shape — `BlockContent.figure(imageRef: String, caption: String)`.** A closed case with two plain `String` fields:
- `imageRef` — a bare filename relative to the package's `images/` directory ([ADR-0020](0020-bible-index-in-app-layer.md) pattern), e.g. `cover.jpg`. Not a path or URL; the package root is implicit. Empty is a valid placeholder state (the writer fills it in).
- `caption` — plain text, **no inline runs** in v1. Keeping it flat avoids `[Run]` (de)serialization and matches the closed-minimal principle (ADR-0009). Italic/marked captions are a future amendment, not a v1 question. Empty is valid.

**Serialization — a single human-readable prose marker line, both fields in the prose.** A figure serializes to one line:
```
[figure: cover.jpg | A view of the harbor at dawn.]
```
The ` | caption` part is omitted when the caption is empty (`[figure: cover.jpg]`). The writer's caption thus lives in the **prose** file — diffable and writer-owned (ADR-0007's spirit), exactly like the `***` scene-break and `:::kind` set-piece markers already in the prose. The sidecar `BlockDTO` is **unchanged** (just `id` + `overrides`): a figure is an ordinary non-empty prose-content block, so it needs no new sidecar field and no change to the sidecar-reconstruction path added in the empty-paragraph fix.

`\`-escaping covers the delimiters: `\`, `]`, and `|` in `imageRef`/`caption` are backslash-escaped on write and unescaped on read, so a caption containing those characters round-trips. A genuine paragraph that happens to read like a marker (begins `[figure:`) is escaped on write (prefixed `\`), the same discipline `serializeParagraphLine` already applies to `***`/`#`/`:::`.

**`images/` package directory.** Per-project subdirectory (ADR-0020 pattern), alongside `bible/`, `snippets/`, `templates/`. For v1 the writer places files there manually — no in-app import. It is *assets, not an index*: no `ImageIndex` struct; ref validation is a `FileManager.fileExists` check done by `WorkspaceDocument` on open (warn on a missing ref; never reject the document).

## Consequences

- A reader of `prose.txt` sees the figure and its caption in place — the prose stays meaningfully complete and diffable (ADR-0007). The typesetter, or any downstream tool, can read the same marker.
- A figure is a normal prose-content block (like `sceneBreak`): `parseProseBlocks` recognizes the `[figure: …]` line and the sidecar codec needs **no** new field. The empty-paragraph sidecar-reconstruction logic is untouched.
- The closed vocabulary grows by exactly one block kind, justified to the reveal as a `[figure: <ref>]` chip (see the ADR-0009 amendment). Alt-text, layout hints, multi-image figures, and inline-run captions are explicitly **deferred** — each would need its own justification.
- Actual image loading/sizing/placement is **never** Galley's job (ADR-0024). The editor shows a placeholder only; the file on disk is the typesetter's input.
- Escaping is the one piece of new prose-format surface; it is contained to the figure marker and mirrors the existing run/marker escaping, so the round-trip stays total (`parse(serialize(doc)) == doc`).

## Session

LT4-1 (2026-06-07) — figure block shape (`imageRef`/`caption` plain strings) + single-line prose marker serialization with delimiter escaping; `images/` as an ADR-0020 package asset directory. Complements ADR-0007; justified to the reveal per the ADR-0009 amendment. Caption editability is ADR-0028.
