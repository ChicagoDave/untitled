//
//  Caret.swift
//  GalleyShell
//
//  Purpose: A model-coordinate text selection — the editing caret expressed in the
//  terms the document model owns (block id + character offset), never a TextKit
//  character index. Stable across re-projection and meaningful to any editing
//  surface, so one caret value can be shared by the prose editor and the Reveal
//  Codes surface (ADR-0030) and stored in the undo timeline (ADR-0031).
//  Public interface: `Caret`, its `start`/`end` `Position`s, the collapsed-caret
//  convenience initializer, and `isCollapsed`.
//  Owner context: GalleyShell — app-layer editing state. Foundation-free; depends
//  only on `GalleyCore.BlockID`.
//

import GalleyCore

/// A selection in model coordinates: an anchored range from `start` to `end`, each
/// a `(blockID, offset)` position in the document model. A collapsed caret has
/// `start == end`. Recorded with each undo entry so undo/redo restore the caret the
/// writer had, not a position re-derived from a document diff (ADR-0031).
public struct Caret: Equatable, Sendable {

    /// A single model-coordinate position: a character `offset` within block `blockID`.
    public struct Position: Equatable, Sendable {
        public var blockID: BlockID
        public var offset: Int

        public init(blockID: BlockID, offset: Int) {
            self.blockID = blockID
            self.offset = offset
        }
    }

    /// The selection's anchor end.
    public var start: Position
    /// The selection's focus end. Equal to `start` for a plain caret.
    public var end: Position

    /// Creates a selection spanning two positions.
    public init(start: Position, end: Position) {
        self.start = start
        self.end = end
    }

    /// Creates a collapsed caret at a single position.
    public init(blockID: BlockID, offset: Int) {
        let position = Position(blockID: blockID, offset: offset)
        self.start = position
        self.end = position
    }

    /// Whether this is a plain insertion caret (no selected range).
    public var isCollapsed: Bool { start == end }
}
