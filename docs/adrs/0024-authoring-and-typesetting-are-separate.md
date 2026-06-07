# ADR-0024 — Authoring and typesetting are separate concerns; the `.galley` format is the contract

## Context

Designing block templates, structural sections (prologue/epilogue/dedication), and eventually images surfaced a recurring pull toward output-layout features: a dedication is "vertically centered on its own page," chapters "start on a new page," images need "final placement and sizing." Each of these is a **typesetting/production** concern — pagination, page layout, final asset placement — not a drafting concern.

The real-world workflow that prose tools mirror keeps these apart: an author writes a manuscript (content + structure + intent); a separate production step typesets it for output (Scrivener → Vellum/InDesign; manuscript → typesetter). Galley is the **authoring** tool. Letting page-layout and rendering leak into it would re-create the "code soup" ADR-0009 exists to prevent, and would couple the editor to an output model it has no business owning.

The user framed it directly: the entire print/typesetting process is a separate process, and whether it ever lives in Galley (in-app), as a CLI, or as a wholly separate tool is an **open question** that does not need answering to proceed with authoring.

## Decision

**Galley is the authoring tool. It captures the manuscript's content, structure, and semantic *intent* — never its typeset output.** Galley does not paginate, does not lay out pages, does not vertically-center, does not render final image placement.

**Typesetting/production is a separate concern that consumes the `.galley` document format.** The format (plain-text prose + JSON sidecar + package asset files, ADR-0007/ADR-0020) is the **contract** between authoring and typesetting. Therefore the format must carry enough *semantic intent* for a downstream typesetter to do its job:

- Structural roles as **intent**, not layout: a section is marked `dedication` / `prologue` / `epilogue` / `chapter` (a closed `SectionRole`), and the typesetter decides that a dedication is centered on its own page. Galley stores the role; it does not store "vertically centered."
- Assets (e.g. images) as **references + caption + position**, not rendered output: Galley records that an image belongs at a point in the stream and what it is; the typesetter places and sizes it. Galley shows a placeholder.

**The packaging of the typesetting process — in-app, CLI, or separate tool — is explicitly deferred and out of scope.** What matters now is that authoring never absorbs typesetting, and the format carries intent.

## Consequences

- **A hard line for every future session:** do not build pagination, page layout, vertical centering, or final image rendering into Galley. When a feature is about *how output looks on a page*, it belongs to the typesetting process, not the editor. When it is about *what the manuscript means*, it belongs in Galley's model and format.
- **The `.galley` format becomes the load-bearing interface.** New authoring features are evaluated by what intent they add to the format, and whether that intent is sufficient and unambiguous for a typesetter to consume. This raises the bar on format/serialization design (it is now a public contract, not just Galley's own persistence).
- **Section roles supersede bare cut titles for structural intent.** A title string (`"Dedication"`) cannot reliably drive typesetting (renames, custom titles, localization). A closed `SectionRole` on `ChapterCut` carries the intent robustly; the title remains free-form display text. (Implemented in the section-inserts phase.)
- **Images become an "asset reference" feature, not an image-rendering feature** — a referenced package file with caption and stream position, shown as a placeholder in the editor. Deferred as its own future feature.
- **Output-dependent rendering is deferred wholesale** to the typesetting process: the dedication's vertical centering, new-page breaks, and image placement are not Galley deliverables. Galley's editor renders the *editing* view (continuous, intent-revealing), which it already does.
- This is consistent with ADR-0001 (native, not a web layer — unchanged), ADR-0007 (plain-text prose + sidecar — now reframed as an inter-process contract), and ADR-0009 (closed vocabulary — roles and asset refs are closed, intent-bearing additions, not open style).

## Session

bf5f1f (2026-06-06) — Recorded during the Layered Templates + Structural Inserts design. Establishes the authoring/typesetting boundary that scopes the section-role and (future) image-reference work, and explicitly removes vertical-centering / pagination from Galley's scope.
