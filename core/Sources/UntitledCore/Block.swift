//
//  Block.swift
//  UntitledCore
//
//  Purpose: The block layer of the document model — a flat, ordered stream of
//  blocks (§3, §4). No containment, no nesting. Every block carries a stable
//  identity (ADR-0010) so chapter cuts can anchor to it without rotting when
//  unrelated prose is edited.
//  Public interface: `BlockID`, `Block`, `BlockContent`, `SetPieceKind`,
//  `PresentationOverride`, `TextAlignment`.
//  Owner context: UntitledCore — UI-free Swift, the model-as-truth (ADR-0004).
//

/// A stable, never-reused identity for a block.
///
/// Cuts anchor to a block by `BlockID`, not by array index (ADR-0010): the index
/// is a derived, render-time convenience, so inserting or deleting unrelated
/// blocks never disturbs an existing cut. IDs are minted by `Document.mintBlockID()`.
public typealias BlockID = Int

/// One block in the flat block stream: a stable identity plus its content and any
/// bounded presentation overrides.
public struct Block: Equatable, Hashable, Sendable {

    /// This block's stable identity, immutable for the block's lifetime (ADR-0010).
    public let id: BlockID

    /// What the block actually is — paragraph, scene break, or set-piece.
    public var content: BlockContent

    /// Rare per-block presentation overrides (ADR-0009 escape hatch). Empty by
    /// default; a non-empty value is the exception, not the rule.
    public var overrides: [PresentationOverride]

    /// Creates a block.
    /// - Parameters:
    ///   - id: the stable identity, normally obtained from `Document.mintBlockID()`.
    ///   - content: the block's content.
    ///   - overrides: bounded presentation overrides; defaults to none.
    public init(id: BlockID, content: BlockContent, overrides: [PresentationOverride] = []) {
        self.id = id
        self.content = content
        self.overrides = overrides
    }
}

/// The content of a block — the closed set of block kinds (ADR-0009).
///
/// A flat, ordered sequence with no nesting. Each kind derives its own
/// presentation downstream; the model never stores typography.
public enum BlockContent: Equatable, Hashable, Sendable {

    /// A normal paragraph: a sequence of runs that soft-wraps; `Enter` ends it.
    case paragraph(runs: [Run])

    /// A scene-break ornament (the "* * *"). Carries no text of its own.
    case sceneBreak

    /// A set-piece (verse / epigraph / letter): lines with preserved hard breaks
    /// (§7). Each line is its own sequence of runs.
    case setPiece(kind: SetPieceKind, lines: [[Run]])
}

/// The kinds of set-piece. Each derives its own alignment, italics, and spacing.
public enum SetPieceKind: Equatable, Hashable, Sendable {
    case verse, epigraph, letter
}

/// A bounded, one-off presentation override on a single block (ADR-0009).
///
/// This is the deliberate escape hatch for rare cases (a left-aligned poem, a
/// small-caps opener). It is a **closed** set: adding a case demands the same
/// justification as any new code, so "rare override" cannot drift into an open
/// style system.
public enum PresentationOverride: Equatable, Hashable, Sendable {

    /// Force a specific alignment, e.g. a one-off left-aligned poem (§7).
    case alignment(TextAlignment)

    /// Render the block in small caps, e.g. a chapter-opener line (§14).
    case smallCaps
}

/// Horizontal alignment for a presentation override. Leading/center/trailing,
/// not left/right, to stay writing-direction agnostic.
public enum TextAlignment: Equatable, Hashable, Sendable {
    case leading, center, trailing
}
