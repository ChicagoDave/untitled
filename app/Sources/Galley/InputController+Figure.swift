//
//  InputController+Figure.swift
//  Galley
//
//  Purpose: Inline figure-caption editing in the main editor (LT4-2, ADR-0028
//  Option A). A figure block renders as two segments: a non-editable placeholder
//  box and an editable caption. This extension routes keystrokes that land in a
//  caption to the figure block via `WorkspaceDocument.setFigureCaption` (the pure
//  reducer, model-as-truth ADR-0004), and glides the caret off the non-editable box
//  onto the caption (down) or the previous block (up) — the box is never a resting
//  place, mirroring how chapter breaks are skipped (LT3). The caption is plain text
//  (no runs, ADR-0027); Enter does not split it.
//  Public interface: the `InputController` key/selection hooks call into these.
//  Owner context: Galley — the macOS shell's editing layer.
//

import AppKit
import GalleyCore

extension InputController {

    // MARK: Caption-position lookup

    /// The `(figureBlockID, offset)` of the caret when it sits in a figure caption,
    /// else `nil`.
    func caretCaptionPosition() -> (figureBlockID: BlockID, offset: Int)? {
        currentLayout.captionPosition(forCharacterAt: selectedRange().location)
    }

    /// The current caption text stored on the figure block, or `""` if the block is
    /// absent or not a figure.
    private func currentCaption(of blockID: BlockID) -> String {
        guard let block = buffer?.document.blocks.first(where: { $0.id == blockID }),
              case .figure(_, let caption) = block.content else { return "" }
        return caption
    }

    // MARK: Editing a caption

    /// Inserts text into the figure's caption at the caret, re-renders, and restores
    /// the caret after the inserted text.
    func insertIntoCaption(_ text: String, at position: (figureBlockID: BlockID, offset: Int)) {
        guard let buffer else { return }
        withoutSelectionSync {
            var characters = Array(currentCaption(of: position.figureBlockID))
            let offset = min(max(position.offset, 0), characters.count)
            characters.insert(contentsOf: Array(text), at: offset)
            buffer.setFigureCaption(atBlock: position.figureBlockID, to: String(characters))
            applyRender()
            if let caret = currentLayout.characterPosition(forCaptionBlock: position.figureBlockID, offset: offset + text.count) {
                setSelectedRange(NSRange(location: caret, length: 0))
            }
        }
    }

    /// Backspace in a caption: deletes the character before the caret. At the
    /// caption's start it is a no-op — the figure block is removed from the prose
    /// side (backspace at the start of the block after it, the same as a scene break),
    /// so a caption backspace never destroys the figure.
    func deleteBackwardInCaption(at position: (figureBlockID: BlockID, offset: Int)) {
        guard let buffer, position.offset > 0 else { return }
        withoutSelectionSync {
            var characters = Array(currentCaption(of: position.figureBlockID))
            let offset = min(position.offset, characters.count)
            guard offset > 0 else { return }
            characters.remove(at: offset - 1)
            buffer.setFigureCaption(atBlock: position.figureBlockID, to: String(characters))
            applyRender()
            if let caret = currentLayout.characterPosition(forCaptionBlock: position.figureBlockID, offset: offset - 1) {
                setSelectedRange(NSRange(location: caret, length: 0))
            }
        }
    }

    // MARK: Entering a caption (after a palette insert)

    /// Places the caret at the start of a freshly inserted figure's caption and takes
    /// focus, so the writer types the caption immediately (keyboard-first, LT4-2). The
    /// caption is empty on insert; this is the figure's keyboard-reachable surface.
    func beginCaptionEditing(figure blockID: BlockID) {
        endCompletion()
        endPalette()
        withoutSelectionSync {
            applyRender()
            if let caret = currentLayout.characterPosition(forCaptionBlock: blockID, offset: 0) {
                setSelectedRange(NSRange(location: caret, length: 0))
            }
            window?.makeFirstResponder(self)
        }
    }

    // MARK: Arrow-glide past the placeholder box

    /// Moves the caret off a figure's placeholder box (it is non-editable): onto the
    /// editable caption when gliding forward/down, or to the end of the previous block
    /// when backward/up. A no-op when the caret is not on a box.
    func glidePastFigureBox(forward: Bool) {
        let location = selectedRange().location
        guard let figureBlock = currentLayout.figureBoxBlockID(forCharacterAt: location) else { return }
        let target: Int? = forward
            ? currentLayout.characterPosition(forCaptionBlock: figureBlock, offset: 0)
            : positionAtEndOfBlockBefore(figureBlock)
        if let target {
            withoutSelectionSync { setSelectedRange(NSRange(location: target, length: 0)) }
        }
    }

    /// The caret position at the end of the prose block preceding `blockID`, or `nil`
    /// when there is none or it is not editable prose (the caret then simply stays).
    private func positionAtEndOfBlockBefore(_ blockID: BlockID) -> Int? {
        guard let buffer,
              let index = buffer.document.blocks.firstIndex(where: { $0.id == blockID }), index > 0,
              case .paragraph(let runs) = buffer.document.blocks[index - 1].content else { return nil }
        let end = runs.reduce(0) { $0 + $1.text.count }
        return currentLayout.characterPosition(forBlock: buffer.document.blocks[index - 1].id, offset: end)
    }
}
