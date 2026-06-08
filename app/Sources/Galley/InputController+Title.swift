//
//  InputController+Title.swift
//  Galley
//
//  Purpose: Inline chapter-title editing in the main editor (LT3) and the
//  model-snapshot undo/redo hooks (Cmd-Z / Cmd-Shift-Z). Every heading is a
//  navigable, editable segment; edit-mode follows the caret (the selection
//  observer): whichever heading the caret enters — by click or arrow key — renders
//  the raw title (the macro visible) and routes keystrokes to the cut's title via
//  `WorkspaceDocument.setCutTitle`; every other heading shows the resolved title
//  (numbering rendered) — the spreadsheet rule (ADR-0026). Leaving a heading
//  restores its resolved form. Backspace never silently merges across a break: at a
//  chapter's prose start it moves up into the title, and removing the break is a
//  deliberate backspace at the title's start.
//  Public interface: the `InputController` key/mouse/selection hooks call into these.
//  Owner context: Galley — the macOS shell's editing layer.
//

import AppKit
import GalleyCore
import GalleyShell

extension InputController {

    // MARK: Title-position lookup

    /// The `(cutBlockID, offset)` of the caret when it sits in a heading, else `nil`.
    func caretTitlePosition() -> (cutBlockID: BlockID, offset: Int)? {
        currentLayout.titlePosition(forCharacterAt: selectedRange().location)
    }

    /// The raw (macro-bearing) title stored on the boundary cut at `blockID`.
    private func rawTitle(of blockID: BlockID) -> String {
        buffer?.document.cuts.first { $0.blockID == blockID && $0.offsetInBlock == nil }?.title ?? ""
    }

    /// Runs `body` with the selection observer suppressed, restoring the prior state
    /// so nested calls compose correctly. Internal so the figure-caption extension
    /// (LT4-2) reuses the same suppression while it re-renders.
    func withoutSelectionSync(_ body: () -> Void) {
        let wasSyncing = isSyncingSelection
        isSyncingSelection = true
        defer { isSyncingSelection = wasSyncing }
        body()
    }

    // MARK: Selection-driven exit + arrow-glide past breaks

    /// After a settled selection change: leave the heading being edited if the caret
    /// has exited it, then skip the caret past any (non-edited) break it landed on so
    /// arrows glide over breaks (LT3). Editing a break is only ever entered by click.
    func syncTitleEditingToCaret() {
        // 1. Exit the edited heading once the caret moves out of it (e.g. arrow down
        //    into the prose, or up into the previous block).
        if let editing = editingTitleCut,
           currentLayout.headingCut(forCharacterAt: selectedRange().location) != editing {
            let landing = caretModelPosition()
            ensureNonEmptyTitle(editing)
            editingTitleCut = nil
            withoutSelectionSync {
                applyRender()
                if let landing, let position = currentLayout.characterPosition(forBlock: landing.blockID, offset: landing.offset) {
                    setSelectedRange(NSRange(location: position, length: 0))
                }
            }
        }

        // 2. If the caret landed inside a (non-edited) heading, glide it past — to the
        //    chapter's prose when moving down, to the previous section's end when up.
        let location = selectedRange().location
        if editingTitleCut == nil, let heading = currentLayout.headingCut(forCharacterAt: location) {
            skipPastHeading(cut: heading, forward: location >= lastCaretLocation)
        }

        // 3. If the caret landed on a figure's placeholder box, glide it onto the
        //    editable caption (down) or the previous block (up) — the box is never a
        //    resting place (LT4-2), mirroring how breaks are skipped.
        if editingTitleCut == nil {
            glidePastFigureBox(forward: selectedRange().location >= lastCaretLocation)
        }
        lastCaretLocation = selectedRange().location
    }

    /// Moves the caret off a break heading: to the start of the chapter's prose when
    /// gliding forward/down, or to the end of the previous section when backward/up.
    private func skipPastHeading(cut: BlockID, forward: Bool) {
        guard let buffer else { return }
        let doc = buffer.document
        var target: (blockID: BlockID, offset: Int) = (cut, 0)
        if !forward, let index = doc.blocks.firstIndex(where: { $0.id == cut }), index > 0 {
            let previous = doc.blocks[index - 1]
            if case .paragraph(let runs) = previous.content {
                target = (previous.id, runs.reduce(0) { $0 + $1.text.count })
            } else {
                target = (previous.id, 0)
            }
        }
        if let position = currentLayout.characterPosition(forBlock: target.blockID, offset: target.offset) {
            withoutSelectionSync { setSelectedRange(NSRange(location: position, length: 0)) }
        }
    }

    // MARK: Click hit-testing

    /// The cut whose heading covers `point` (view coordinates), for click-to-edit.
    ///
    /// A heading owns its whole line, so the hit-test matches the click's *vertical*
    /// band rather than the tight glyph box: clicking anywhere on the heading line —
    /// including the empty space past the end of the title text — enters title editing
    /// instead of falling through to the prose below (which would glide the caret off
    /// the heading and read as the caret "jumping").
    func headingCut(atPoint point: NSPoint) -> BlockID? {
        for segment in currentLayout.segments where segment.titleCutBlockID != nil {
            if let box = rect(forUTF16Range: segment.utf16Range), point.y >= box.minY, point.y <= box.maxY {
                return segment.titleCutBlockID
            }
        }
        return nil
    }

    /// The bounding rectangle of a UTF-16 range in this view's coordinates, via the
    /// TextKit 2 layout (the same segment geometry the caret anchor uses).
    private func rect(forUTF16Range range: NSRange) -> NSRect? {
        guard let layoutManager = textLayoutManager,
              let contentStorage = textContentStorage,
              let start = contentStorage.location(contentStorage.documentRange.location, offsetBy: range.location),
              let end = contentStorage.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return nil }

        var union: NSRect?
        layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            union = union.map { $0.union(frame) } ?? frame
            return true
        }
        guard let box = union else { return nil }
        let origin = textContainerOrigin
        return box.offsetBy(dx: origin.x, dy: origin.y)
    }

    // MARK: Editing a title

    /// Inserts text into the heading's raw title at the caret, re-renders raw, and
    /// restores the caret after the inserted text.
    func insertIntoTitle(_ text: String, at position: (cutBlockID: BlockID, offset: Int)) {
        guard let buffer else { return }
        editingTitleCut = position.cutBlockID
        withoutSelectionSync {
            var characters = Array(rawTitle(of: position.cutBlockID))
            let offset = min(max(position.offset, 0), characters.count)
            characters.insert(contentsOf: Array(text), at: offset)
            buffer.setCutTitle(atBlock: position.cutBlockID, to: String(characters))
            applyRender()
            if let caret = currentLayout.characterPosition(forTitleCut: position.cutBlockID, offset: offset + text.count) {
                setSelectedRange(NSRange(location: caret, length: 0))
            }
        }
    }

    /// Backspace in a heading: deletes the character before the caret. At the title's
    /// start it is a no-op — removing a break is done from the prose side via the Y/N
    /// confirm prompt (LT3), so a title backspace never destroys structure.
    func deleteBackwardInTitle(at position: (cutBlockID: BlockID, offset: Int)) {
        guard let buffer, position.offset > 0 else { return }
        editingTitleCut = position.cutBlockID

        withoutSelectionSync {
            var characters = Array(rawTitle(of: position.cutBlockID))
            let offset = min(position.offset, characters.count)
            guard offset > 0 else { return }
            characters.remove(at: offset - 1)
            buffer.setCutTitle(atBlock: position.cutBlockID, to: String(characters))
            applyRender()
            if let caret = currentLayout.characterPosition(forTitleCut: position.cutBlockID, offset: offset - 1) {
                setSelectedRange(NSRange(location: caret, length: 0))
            }
        }
    }

    // MARK: Entering / leaving / removing

    /// Enters inline editing for the heading of the cut at `cut`: renders it raw,
    /// caret at the end of the title, takes focus.
    func beginTitleEditing(cut: BlockID) {
        if let current = editingTitleCut, current != cut { ensureNonEmptyTitle(current) }
        endCompletion()
        endPalette()
        editingTitleCut = cut
        withoutSelectionSync {
            applyRender()
            if let caret = currentLayout.endOfTitle(cutBlockID: cut) {
                setSelectedRange(NSRange(location: caret, length: 0))
            }
            window?.makeFirstResponder(self)
        }
    }

    /// Leaves title editing: an emptied title reverts to its role default (never
    /// blank), the heading re-renders resolved, and — when `moveToBody` — the caret
    /// drops into the chapter's first prose block.
    func exitTitleEditing(moveToBody: Bool) {
        guard let cut = editingTitleCut else { return }
        ensureNonEmptyTitle(cut)
        editingTitleCut = nil
        withoutSelectionSync {
            if moveToBody {
                renderFromModel(caret: (cut, 0))   // the cut anchors the chapter's prose block
            } else {
                applyRender()
                let length = (string as NSString).length
                setSelectedRange(NSRange(location: min(selectedRange().location, length), length: 0))
            }
        }
    }

    // MARK: Break-deletion confirmation (Y/N)

    /// Resolves a pending break deletion from its confirming key: `y` removes the
    /// break, anything else (including `n` and Esc) cancels (LT3).
    func handleBreakDeletionKey(_ event: NSEvent) {
        guard let pending = pendingBreakDeletion else { return }
        if event.charactersIgnoringModifiers?.lowercased() == "y" {
            confirmBreakDeletion(pending)
        } else {
            cancelBreakDeletion(pending)
        }
    }

    /// Removes the break (its boundary cut), leaving the prose block, and lands the
    /// caret at the end of the previous section.
    func confirmBreakDeletion(_ cut: BlockID) {
        guard let buffer else { return }
        pendingBreakDeletion = nil
        let doc = buffer.document
        var caret: (BlockID, Int) = (cut, 0)
        if let index = doc.blocks.firstIndex(where: { $0.id == cut }), index > 0 {
            let previous = doc.blocks[index - 1]
            if case .paragraph(let runs) = previous.content {
                caret = (previous.id, runs.reduce(0) { $0 + $1.text.count })   // end of previous section
            } else {
                caret = (previous.id, 0)
            }
        }
        withoutSelectionSync {
            buffer.removeCut(atBlock: cut)
            renderFromModel(caret: caret)
        }
    }

    /// Dismisses the prompt without deleting; the caret returns in front of the break
    /// (the chapter's prose start).
    func cancelBreakDeletion(_ cut: BlockID) {
        pendingBreakDeletion = nil
        withoutSelectionSync {
            renderFromModel(caret: (cut, 0))
        }
    }

    /// Restores the role's default title if the cut's title was cleared to empty.
    private func ensureNonEmptyTitle(_ cut: BlockID) {
        guard let buffer, rawTitle(of: cut).isEmpty else { return }
        let role = buffer.document.cuts.first { $0.blockID == cut && $0.offsetInBlock == nil }?.role ?? .chapter
        buffer.setCutTitle(atBlock: cut, to: role.defaultTitle)
    }

    // MARK: Undo / redo (Cmd-Z, Cmd-Shift-Z)

    /// Restores the previous document state and lands the caret where it was *before*
    /// the undone edit — the caret recorded with that edit, not a position re-derived
    /// from a document diff (ADR-0031). Dispatches to the shared workspace-level
    /// timeline (ADR-0033) so undo works identically from either editing surface; the
    /// restored caret updates `currentCaret`, which both panes then reconcile to.
    func performUndo() {
        guard let buffer else { return }
        editingTitleCut = nil
        pendingBreakDeletion = nil
        buffer.performUndo()
        restoreCaret(buffer.currentCaret)
    }

    /// Re-applies the most recently undone state, landing the caret where it was after
    /// that edit (the caret recorded at undo time), as redo conventionally does. Shares
    /// the workspace-level timeline with the reveal surface (ADR-0033).
    func performRedo() {
        guard let buffer else { return }
        editingTitleCut = nil
        pendingBreakDeletion = nil
        buffer.performRedo()
        restoreCaret(buffer.currentCaret)
    }

    /// Re-renders after an undo/redo and restores `caret` (clamped to a valid mapped
    /// position), falling back to the first editable position so the caret never lands
    /// in the void. Never re-derives the caret from a document diff (ADR-0031).
    private func restoreCaret(_ caret: Caret?) {
        withoutSelectionSync {
            applyRender()
            if let caret,
               let lower = currentLayout.characterPosition(forBlock: caret.start.blockID, offset: caret.start.offset),
               let upper = currentLayout.characterPosition(forBlock: caret.end.blockID, offset: caret.end.offset) {
                setSelectedRange(NSRange(location: lower, length: max(0, upper - lower)))
            } else if let first = currentLayout.firstEditablePosition(),
                      let position = currentLayout.characterPosition(forBlock: first.blockID, offset: first.offset) {
                setSelectedRange(NSRange(location: position, length: 0))
            } else {
                let length = (string as NSString).length
                setSelectedRange(NSRange(location: min(selectedRange().location, length), length: 0))
            }
        }
    }
}
