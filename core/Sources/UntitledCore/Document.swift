//
//  Document.swift
//  UntitledCore
//
//  Purpose: The document aggregate (§4) — the continuous draft (a flat block
//  stream), the late-bound chapter overlay, the reference bible, and metadata.
//  This is the model-as-truth (ADR-0004): every view is a projection of it.
//  Public interface: `Document`, plus the `Bible` / `BibleEntry` / `Metadata`
//  stubs it aggregates.
//  Owner context: UntitledCore — UI-free Swift, the one bounded context.
//

/// The whole document: the thing the writer writes, plus its overlays.
///
/// `blocks` is the continuous draft. `cuts` is the movable chapter overlay
/// (ADR-0005), anchored by `BlockID` (ADR-0010). `nextBlockID` is a monotonic
/// counter that mints never-reused block identities.
///
/// Invariant: `nextBlockID` is strictly greater than every existing block's
/// `id`, so a minted ID can never collide with a live block (ADR-0010).
public struct Document: Equatable, Sendable {

    /// The continuous draft — the ordered block stream the writer types into.
    public var blocks: [Block]

    /// The late-bound chapter overlay, ordered by position in the stream.
    public var cuts: [ChapterCut]

    /// The reference index (§9).
    public var bible: Bible

    /// Document-level metadata.
    public var meta: Metadata

    /// The next block identity to hand out. Monotonic; never decreases; IDs are
    /// never reused (ADR-0010). Mutated only through `mintBlockID()`.
    public private(set) var nextBlockID: BlockID

    /// Creates a document.
    ///
    /// - Parameters:
    ///   - blocks: the initial block stream; defaults to empty.
    ///   - cuts: the initial chapter overlay; defaults to empty.
    ///   - bible: the reference index; defaults to empty.
    ///   - meta: document metadata; defaults to empty.
    ///   - nextBlockID: the starting value of the ID counter; defaults to `0`.
    /// - Precondition: `nextBlockID` exceeds every `id` in `blocks` (ADR-0010).
    public init(
        blocks: [Block] = [],
        cuts: [ChapterCut] = [],
        bible: Bible = Bible(),
        meta: Metadata = Metadata(),
        nextBlockID: BlockID = 0
    ) {
        precondition(
            blocks.allSatisfy { $0.id < nextBlockID },
            "nextBlockID must exceed every existing block id (ADR-0010: IDs are never reused)"
        )
        self.blocks = blocks
        self.cuts = cuts
        self.bible = bible
        self.meta = meta
        self.nextBlockID = nextBlockID
    }

    /// Returns a fresh, never-reused block identity and advances the counter.
    ///
    /// - Returns: the current `nextBlockID`, before incrementing.
    public mutating func mintBlockID() -> BlockID {
        defer { nextBlockID += 1 }
        return nextBlockID
    }
}

/// The reference bible — a fuzzy index over the writer's own entities (§9).
///
/// Stub for the headless core: enough structure for `Document` to compile and
/// for later `@`-complete to index against. Mechanical lookup only, never
/// editorial (ADR-0008).
public struct Bible: Equatable, Sendable {

    /// The entries available for reference and `@`-complete.
    public var entries: [BibleEntry]

    /// Creates a bible.
    public init(entries: [BibleEntry] = []) {
        self.entries = entries
    }
}

/// A single bible entry: a named entity with its canonical spelling and notes.
public struct BibleEntry: Equatable, Hashable, Sendable {

    /// The entry's display name / lookup key (e.g. a character or place).
    public var name: String

    /// The canonical text `@`-complete inserts verbatim (e.g. the exact spelling).
    public var canonicalText: String

    /// Free-form notes shown when the entry is peeked.
    public var notes: String

    /// Creates a bible entry.
    public init(name: String, canonicalText: String, notes: String = "") {
        self.name = name
        self.canonicalText = canonicalText
        self.notes = notes
    }
}

/// Document-level metadata.
///
/// Stub for the headless core: the minimum needed for `Document` to compile and
/// round-trip. Grows as the format demands.
public struct Metadata: Equatable, Sendable {

    /// The work's title.
    public var title: String

    /// The author's name.
    public var author: String

    /// Creates document metadata.
    public init(title: String = "", author: String = "") {
        self.title = title
        self.author = author
    }
}
