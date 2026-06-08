//
//  DisplayToken.swift
//  GalleyCore
//
//  Purpose: The plain-value vocabulary of the display projection (§5, ADR-0006) —
//  the companion to `RevealToken`. Where reveal surfaces codes as chips, display
//  carries the clean reading view as block-grained, typography-free *roles*: a
//  paragraph, a scene break, a set-piece line, a chapter opening. Concrete
//  typography (fonts, indents, the "* * *" ornament) is resolved by the shell, so
//  these values stay UI-free and testable headless.
//  Public interface: `DisplayToken`, `DisplaySpan`.
//  Owner context: GalleyCore — UI-free Swift, the model-as-truth (ADR-0004).
//

/// One element of the display stream: a renderable block in reading order (§5).
///
/// Display is the *clean* view (ADR-0006), the counterpart to the reveal truth
/// view. Each token names a display *role*; the shell's attribution step maps the
/// role to concrete type (body indent, verse centering, the scene-break
/// ornament, chapter spacing) — the closed typographic vocabulary lives there,
/// never in the model.
public enum DisplayToken: Equatable, Sendable {

    /// A body paragraph: its styled inline spans plus any per-block overrides.
    case paragraph(spans: [DisplaySpan], overrides: [PresentationOverride])

    /// The scene-break ornament. Carries no text; the shell renders the glyph.
    case sceneBreak

    /// One line of a set-piece (§7). The `kind` drives the line's derived
    /// alignment and italic in the shell; `overrides` are the block's escape-hatch
    /// presentation, applied to every line of the set-piece.
    case setPieceLine(kind: SetPieceKind, spans: [DisplaySpan], overrides: [PresentationOverride])

    /// A chapter opening spliced at a cut (ADR-0005). Carries the cut's `role`
    /// (ADR-0026) and its title, if any; the shell renders the heading — the title
    /// when set, else the role name for a non-chapter section, else a divider.
    case chapterStart(role: SectionRole, title: String?)

    /// A figure placeholder (LT4): the image reference and caption. The shell renders
    /// a placeholder (icon + ref + caption) — never the image itself (ADR-0024).
    case figure(imageRef: String, caption: String)
}

/// A run of display text plus its single inline mark.
///
/// Mirrors `Run` but carries only what the reading view needs: the literal text
/// and whether it is italic. Derived set-piece italic is *not* encoded here — it
/// comes from the enclosing `setPieceLine`'s `kind` — so `italic` reflects only an
/// explicit `Run.italic` mark (ADR-0009).
public struct DisplaySpan: Equatable, Sendable {

    /// The literal text of the span. Never empty in a projected token.
    public var text: String

    /// Whether this span carries the explicit italic inline mark.
    public var italic: Bool

    /// Creates a display span.
    /// - Parameters:
    ///   - text: the literal characters of the span.
    ///   - italic: whether the span is italicised; defaults to `false`.
    public init(text: String, italic: Bool = false) {
        self.text = text
        self.italic = italic
    }
}
