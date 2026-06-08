//
//  Block.swift
//  GalleyCore
//
//  Purpose: The block layer of the document model — a flat, ordered stream of
//  blocks (§3, §4). No containment, no nesting. Every block carries a stable
//  identity (ADR-0010) so chapter cuts can anchor to it without rotting when
//  unrelated prose is edited.
//  Public interface: `BlockID`, `Block`, `BlockContent`, `SetPieceKind`,
//  `PresentationOverride`, `TextAlignment`.
//  Owner context: GalleyCore — UI-free Swift, the model-as-truth (ADR-0004).
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

    /// A figure: an image *reference* (a filename in the package's `images/`
    /// directory) plus a plain-text caption (LT4, ADR-0027). Carries no rendered
    /// image — Galley stores intent only; the typesetter places and sizes the image
    /// (ADR-0024). The editor shows a placeholder. Both fields may be empty (an
    /// unfilled placeholder). A closed addition to the block vocabulary (ADR-0009
    /// amendment), justified to the reveal as a `[figure: <ref>]` chip.
    case figure(imageRef: String, caption: String)
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

    /// Render the block as a block quote: indented from the margin, leading
    /// alignment — the common non-verse structural block (a set-off passage,
    /// an inscription). Added under the ADR-0009 amendment (BP1) as a scoped,
    /// closed addition, justified to the reveal as `[quote]`.
    case blockQuote
}

// MARK: - Wire tokens (ADR-0009)

extension PresentationOverride {

    /// The wire token for this override — the single source of truth for both the
    /// JSON sidecar (`Storage.swift`) and the template front-matter
    /// (`GalleyShell.TemplateIndex`). Both readers share this codec so the closed
    /// vocabulary can never drift between the two formats (rule 8b).
    ///
    /// - Invariant: every case maps to exactly one token, and `init?(token:)` is
    ///   its exact inverse — `PresentationOverride(token: o.token) == o` for all `o`.
    public var token: String {
        switch self {
        case .smallCaps: return "smallCaps"
        case .blockQuote: return "blockQuote"
        case .alignment(.leading): return "align:leading"
        case .alignment(.center): return "align:center"
        case .alignment(.trailing): return "align:trailing"
        }
    }

    /// Decodes a wire token to its override, or `nil` if the token is outside the
    /// closed vocabulary (ADR-0009). Callers turn `nil` into a hard rejection — an
    /// unknown token is never silently dropped.
    ///
    /// - Parameter token: a sidecar or template-front-matter override token.
    public init?(token: String) {
        switch token {
        case "smallCaps": self = .smallCaps
        case "blockQuote": self = .blockQuote
        case "align:leading": self = .alignment(.leading)
        case "align:center": self = .alignment(.center)
        case "align:trailing": self = .alignment(.trailing)
        default: return nil
        }
    }
}

/// Horizontal alignment for a presentation override. Leading/center/trailing,
/// not left/right, to stay writing-direction agnostic.
public enum TextAlignment: Equatable, Hashable, Sendable {
    case leading, center, trailing
}
