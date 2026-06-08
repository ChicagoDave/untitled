//
//  Structure.swift
//  GalleyCore
//
//  Purpose: The structure layer of the document model — chapters as a movable
//  overlay of cut-points over the block stream, NOT as containers (ADR-0005).
//  A chapter is computed at render time by walking the stream and splicing at
//  the cuts; it is never a struct that owns blocks.
//  Public interface: `ChapterCut`, `SectionRole`, `TemplateRef`.
//  Owner context: GalleyCore — UI-free Swift, the model-as-truth (ADR-0004).
//

/// The structural role of a section, as *intent* the typesetter consumes
/// (ADR-0024, ADR-0026).
///
/// A **closed** vocabulary (ADR-0009-style): a section of prose is structurally a
/// chapter (a movable `ChapterCut`, ADR-0005), but the typesetter must drive page
/// layout — a dedication centres on its own page, a prologue precedes chapter
/// numbering — from a reliable role, not a fragile free-form title. The raw value
/// is the wire token; it is its own exact inverse, so the sidecar codec cannot
/// drift from the enum.
public enum SectionRole: String, Equatable, Hashable, Sendable {

    /// An ordinary chapter — the default for every cut, including legacy sidecars.
    case chapter

    /// A prologue: prose before the first numbered chapter.
    case prologue

    /// An epilogue: prose after the last numbered chapter.
    case epilogue

    /// A dedication: a short titled section, typeset on its own page (ADR-0024).
    case dedication
}

/// A single chapter cut-point laid over the block stream.
///
/// A cut anchors to a block by `blockID` (ADR-0010), optionally at a character
/// offset *inside* that block so a chapter can begin mid-block, at an emotional
/// peak (§6). The cut carries no blocks of its own — chapters are an overlay,
/// not containment (ADR-0005).
public struct ChapterCut: Equatable, Hashable, Sendable {

    /// The stable identity of the block this cut anchors to (ADR-0010).
    public var blockID: BlockID

    /// Character offset within the anchored block at which the chapter begins,
    /// or `nil` for a clean block-boundary cut. A non-nil value is a mid-block
    /// cut "at the peak" (§6).
    public var offsetInBlock: Int?

    /// Optional chapter title, set when the writer commits the boundary. Free-form
    /// display text; the typesetter drives layout from `role`, not from this.
    public var title: String?

    /// The section's structural role — typesetter intent (ADR-0024, ADR-0026).
    /// Defaults to `.chapter`; a section insert (prologue/epilogue/dedication)
    /// sets it at creation.
    public var role: SectionRole

    /// Optional chapter-opener template applied at the cut (§9), instantiated at
    /// the cut operation rather than during drafting.
    public var opener: TemplateRef?

    /// Creates a chapter cut.
    /// - Parameters:
    ///   - blockID: the stable identity of the anchored block.
    ///   - offsetInBlock: mid-block character offset, or `nil` for a boundary cut.
    ///   - title: optional chapter title.
    ///   - role: the section's structural role; defaults to `.chapter`.
    ///   - opener: optional chapter-opener template reference.
    public init(blockID: BlockID, offsetInBlock: Int? = nil, title: String? = nil, role: SectionRole = .chapter, opener: TemplateRef? = nil) {
        self.blockID = blockID
        self.offsetInBlock = offsetInBlock
        self.title = title
        self.role = role
        self.opener = opener
    }
}

/// A reference to a saved chapter-opener template (§9).
///
/// Stub for the headless core: the template registry itself is a later concern;
/// here a cut only needs to *name* the pattern it applies.
public struct TemplateRef: Equatable, Hashable, Sendable {

    /// Stable identifier of the referenced template pattern.
    public var id: String

    /// Creates a reference to a template by its identifier.
    public init(id: String) {
        self.id = id
    }
}
