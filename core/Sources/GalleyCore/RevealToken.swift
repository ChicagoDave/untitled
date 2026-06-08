//
//  RevealToken.swift
//  GalleyCore
//
//  Purpose: The plain-value vocabulary of the reveal projection (§5, ADR-0006) —
//  the flat stream of literal text and addressable code chips the reveal pane
//  renders. Pure values only: no NSAttributedString, no AppKit, no rendering
//  types, so the projection is testable headless.
//  Public interface: `RevealToken`, `CodeID`.
//  Owner context: GalleyCore — UI-free Swift, the model-as-truth (ADR-0004).
//

/// One element of the reveal stream: either literal prose, or a visible,
/// addressable code chip (§5).
///
/// Reveal is the *truth* view (ADR-0006): codes are surfaced as objects the
/// writer can see and delete. Explicit inline italic (a `Run.italic` mark) is a
/// reveal code — `[i]`/`[/i]` chips around the run — per the closed inline
/// vocabulary (ADR-0009). A set-piece's italic is *derived from its kind*, not a
/// run mark, so it produces no `[i]` chips (matching the §7 verse example).
public enum RevealToken: Equatable, Sendable {

    /// Literal prose text, exactly as it reads.
    case text(String)

    /// A visible code chip with its display label and addressable identity.
    case code(label: String, id: CodeID)
}

/// The stable identity of a reveal code chip, so the reveal pane can address a
/// chip back to the model element it stands for (ADR-0006: codes are objects).
///
/// Every identity is derived from the model — a `BlockID`, a line index within a
/// set-piece, or a chapter cut's anchor — so the same code always carries the
/// same `CodeID` across projections.
public enum CodeID: Equatable, Hashable, Sendable {

    /// The `[SceneBreak]` chip for a scene-break block.
    case sceneBreak(BlockID)

    /// The opening `[Verse]`/`[Epigraph]`/`[Letter]` chip of a set-piece block.
    case setPieceOpen(BlockID)

    /// The closing `[/Verse]`/`[/Epigraph]`/`[/Letter]` chip of a set-piece block.
    case setPieceClose(BlockID)

    /// A `[line]` chip terminating a set-piece line, by block and line index.
    case line(BlockID, Int)

    /// A `[Chapter]` chip for a chapter cut, by anchored block and optional
    /// in-block offset (mirrors `ChapterCut.offsetInBlock`).
    case chapter(BlockID, Int?)

    /// An opening `[i]` chip, by block and the 0-based index of the italic span
    /// within that block (in document order). Pairs with `italicClose`.
    case italicOpen(BlockID, Int)

    /// A closing `[/i]` chip, by block and the same span index as its `italicOpen`.
    case italicClose(BlockID, Int)

    /// A presentation-override chip (`[center]`, `[smallCaps]`, `[quote]`, …) for a
    /// block, by block and the 0-based index of the override on it. Surfaces the
    /// closed override vocabulary in the reveal so it is visible and deletable
    /// (ADR-0009 "justify to reveal").
    case override(BlockID, Int)

    /// A `[figure: <ref>]` chip for a figure block (LT4), by block. The image
    /// reference and caption are intent the typesetter consumes; the chip is the
    /// addressable object the writer sees and can delete (ADR-0009 amendment).
    case figure(BlockID)

    /// The `[p]` hard-return chip terminating a paragraph block, by block — the
    /// WordPerfect-style paragraph mark that makes the block boundary visible in the
    /// reveal stream (ADR-0035). Display-only in v1: deleting it (a paragraph merge)
    /// is deferred, like mid-block `[Chapter]` and set-piece `[line]`.
    case paragraph(BlockID)

    /// The `[sp]` section-opener spacing chip, by the cut's anchor block — the visible
    /// marker of the vertical space a section break introduces between its heading and
    /// the body prose (ADR-0035). Emitted after a boundary cut's title. Display-only:
    /// the spacing is derived from the break, so the chip is not independently
    /// deletable (deletion deferred).
    case sectionSpace(BlockID)
}
