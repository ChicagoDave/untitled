//
//  InputEvent.swift
//  GalleyCore
//
//  Purpose: The model-coordinate vocabulary of editing intents (§8). The shell's
//  input hooks translate keystrokes into these events; the pure `applyInput`
//  reducer turns each into a model mutation, keeping the model the single source
//  of truth (ADR-0004) and block identities / cut anchors stable (ADR-0010).
//  Coordinates are always model coordinates — a `BlockID` and a character offset
//  within that block — never text-view positions.
//  Public interface: `InputEvent`.
//  Owner context: GalleyCore — UI-free Swift, the model-as-truth (ADR-0004).
//

/// One editing intent expressed in model coordinates (§8).
///
/// The writer never issues these deliberately; the text view's input hooks derive
/// them from keystrokes and the caret, then hand them to `applyInput(_:to:)`.
public enum InputEvent: Equatable, Sendable {

    /// Insert literal text into a paragraph at an in-block character offset. Smart
    /// typography (curly quotes, em dash, ellipsis) is applied contextually.
    case insertText(String, blockID: BlockID, offset: Int)

    /// Enter in a paragraph: split it at `offset` into two paragraphs (§8).
    case splitParagraph(blockID: BlockID, offset: Int)

    /// Enter in a set-piece: break `lineIndex` at `offset` into two preserved
    /// lines (a `[line]`, §7) rather than ending the block.
    case breakSetPieceLine(blockID: BlockID, lineIndex: Int, offset: Int)

    /// Backspace at `offset`: delete the preceding character, or — at offset 0 —
    /// merge with the previous paragraph or remove a preceding scene break.
    case deleteBackward(blockID: BlockID, offset: Int)

    /// Toggle the italic inline mark over the in-block range `start..<end` (§8).
    case toggleItalic(blockID: BlockID, start: Int, end: Int)

    /// Replace an (empty) paragraph with a scene-break ornament — typing `#` or
    /// `***` on an empty line (§8).
    case makeSceneBreak(blockID: BlockID)

    /// Toggle a paragraph to/from a set-piece of `kind` (the verse toggle, §8).
    case toggleSetPiece(blockID: BlockID, kind: SetPieceKind)

    /// Insert a pre-composed block — content plus presentation overrides —
    /// immediately after `afterBlockID`, minting a fresh identity (the Block
    /// Palette's template insertion, BP2). The inserted block is fully editable
    /// from the moment it lands; the caret is moved to it by the view layer.
    case insertBlock(content: BlockContent, overrides: [PresentationOverride], afterBlockID: BlockID)

    /// Insert a section — a fresh empty paragraph after `afterBlockID` with a
    /// boundary `ChapterCut` of `role` anchored to it (the palette's
    /// Prologue/Epilogue/Dedication/Chapter rows, LT2). One atomic step so the
    /// roled cut always anchors the seeded prose, never a half-applied state; the
    /// caret is moved into the seeded block by the view layer.
    case insertSection(role: SectionRole, afterBlockID: BlockID)

    /// Clear all presentation overrides from a block, returning it to plain prose
    /// (LT3) — the "second Enter ends the styled block" behaviour: pressing Enter on
    /// an empty styled paragraph drops its overrides rather than continuing the style.
    case clearOverrides(blockID: BlockID)

    /// Replace the caption of a figure block (LT4-2, ADR-0028 Option A). The caption
    /// is edited inline as a real, keyboard-reachable segment, so each keystroke is
    /// one of these events against the figure's block. `imageRef` is unaffected.
    case setFigureCaption(blockID: BlockID, caption: String)

    /// Delete a whole block by ID — the Reveal Codes surface deleting an atomic
    /// `[SceneBreak]` or `[figure]` code chip (LT5-2, ADR-0034). Relocates any cut
    /// anchored to the block (ADR-0010); a no-op on an unknown or only block.
    case deleteBlock(blockID: BlockID)

    /// Remove the single presentation override at `index` on a block — the Reveal
    /// Codes surface deleting one override chip (`[center]`, `[smallCaps]`, …)
    /// (LT5-2, ADR-0034). Unlike `clearOverrides` (which removes all), this targets
    /// one; a no-op on an unknown block or out-of-range index.
    case clearOverride(blockID: BlockID, index: Int)
}
