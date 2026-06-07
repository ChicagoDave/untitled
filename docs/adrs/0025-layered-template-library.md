# ADR-0025 — Block templates are a layered library (built-in + user + story)

## Context

After BP1, block templates lived only in the per-project `templates/` directory ([ADR-0022](0022-block-template-file-format.md)) — the same project-scoped pattern as the bible and snippets ([ADR-0020](0020-bible-index-in-app-layer.md)). That made the Block Palette empty in a brand-new, never-saved project: there was no project on disk, so no templates, so Cmd-; offered only the Scene Break built-in. That is unrealistic — the writer expects their block toolkit immediately.

The fix exposes a modeling distinction. Bible and snippets are **project data** — *this* novel's characters, *this* novel's reusable prose — correctly project-scoped. Block templates are the **writer's toolkit** — "I always set epigraphs centered + small-caps" — which is cross-project by nature. Lumping templates in with project data was the mismodel.

## Decision

Block templates load from **three layers, merged at load time**, with the most-specific layer winning on a case-insensitive name collision — **story > user > built-in**:

1. **Built-in** — in-code `[BlockTemplate]` values shipped with the app (`BuiltInTemplates.all` in `GalleyShell`): Epigraph, Dateline, Block Quote. Not files; no disk path; **present in every buffer, including a brand-new unsaved one**. Empty bodies — a built-in is a *style* starting point, not seeded content.
2. **User** — a global, cross-project directory, `~/Library/Application Support/Galley/templates/`, of plain `.galley-template` files (ADR-0022 format) the writer edits in any text editor. Available to every project.
3. **Story** — the existing per-project `<project>.galley/templates/` directory (ADR-0022, BP1). Unchanged.

`TemplateIndex.merged(builtIns:userDirectory:storyDirectory:)` performs the overlay. No seeding or copying between layers — each loads independently and the merge dedupes by name. `WorkspaceDocument.reloadIndexes()` (and `init`) build the merged index, so a fresh buffer already carries built-in + user templates; the story layer joins once the buffer is saved.

This **amends ADR-0022**'s "templates live in the per-project `templates/` folder" decision to add the built-in and user layers. **ADR-0020 is unchanged** — bible and snippets remain project-scoped, which is exactly correct for project data; only templates get the cross-project treatment.

## Consequences

- A new project's palette is non-empty immediately (built-in toolkit), resolving the reported gap. The user layer makes a writer's personal toolkit follow them across projects without per-project setup.
- Override semantics are intuitive and closed: a project can specialize a built-in (a project-specific "Epigraph"), and a user template can override a built-in globally, by simply using the same name. Precedence is fixed (story > user > built-in), not configurable.
- Built-in templates use the **same `BlockTemplate` type** as file-based ones — no parallel type — and only the closed `PresentationOverride` vocabulary (ADR-0009). Built-ins are values, so they need no parser; the user/story layers reuse the BP1 file parser and its hard-reject-on-unknown-token behavior.
- The user-directory layer is plain editable files, consistent with the "templates are just files" principle (ADR-0022) and the authoring-owns-intent boundary (ADR-0024) — no opaque store.
- `bibleIndex`/`snippetIndex` keep their project-only loading; only `templateIndex` changed. The merge is deterministic (stable order, name-keyed) so it is headlessly testable with explicit layer directories — tests pass temp dirs, never the developer's real home directory.

## Session

bf5f1f (2026-06-06) — Phase LT1. Built-in + user + story layered template library; amends ADR-0022. Built-ins: Epigraph, Dateline, Block Quote. (Dedication moved to the section-insert track, LT2/ADR-0026, since it is a titled prose section, not a styled block.)
