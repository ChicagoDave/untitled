//
//  Structure.swift
//  UntitledCore
//
//  Purpose: The structure layer of the document model — chapters as a movable
//  overlay of cut-points over the block stream, NOT as containers (ADR-0005).
//  A chapter is computed at render time by walking the stream and splicing at
//  the cuts; it is never a struct that owns blocks.
//  Public interface: `ChapterCut`, `TemplateRef`.
//  Owner context: UntitledCore — UI-free Swift, the model-as-truth (ADR-0004).
//

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

    /// Optional chapter title, set when the writer commits the boundary.
    public var title: String?

    /// Optional chapter-opener template applied at the cut (§9), instantiated at
    /// the cut operation rather than during drafting.
    public var opener: TemplateRef?

    /// Creates a chapter cut.
    /// - Parameters:
    ///   - blockID: the stable identity of the anchored block.
    ///   - offsetInBlock: mid-block character offset, or `nil` for a boundary cut.
    ///   - title: optional chapter title.
    ///   - opener: optional chapter-opener template reference.
    public init(blockID: BlockID, offsetInBlock: Int? = nil, title: String? = nil, opener: TemplateRef? = nil) {
        self.blockID = blockID
        self.offsetInBlock = offsetInBlock
        self.title = title
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
