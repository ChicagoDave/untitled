//
//  BuiltInTemplates.swift
//  GalleyShell
//
//  Purpose: The built-in block templates shipped with the app (LT1) — the bottom
//  layer of the layered template library (ADR-0025). These are in-code
//  `BlockTemplate` values, not files, so they require no disk path and are present
//  in EVERY buffer, including a brand-new unsaved one (the fix for "a new project's
//  palette is empty"). They are the writer's starting toolkit; the user-level and
//  per-project layers override and extend them by name (story > user > built-in).
//  Each carries only the closed `PresentationOverride` vocabulary (ADR-0009) and an
//  empty body — picking one inserts a blank, correctly-styled paragraph to type into.
//  Public interface: `BuiltInTemplates.all`.
//  Owner context: GalleyShell — app-layer reference data. Foundation + GalleyCore.
//

import GalleyCore

/// The block templates shipped with the app, always available (ADR-0025).
public enum BuiltInTemplates {

    /// The built-in templates, in display order. Empty bodies: a built-in is a
    /// *style* starting point (a blank styled paragraph), not seeded content — the
    /// writer types their own text. A user or story template of the same name
    /// overrides the built-in.
    public static let all: [BlockTemplate] = [
        BlockTemplate(name: "Epigraph", body: "", overrides: [.alignment(.center), .smallCaps]),
        BlockTemplate(name: "Dateline", body: "", overrides: [.smallCaps]),
        BlockTemplate(name: "Block Quote", body: "", overrides: [.blockQuote]),
    ]
}
