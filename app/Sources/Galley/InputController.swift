//
//  InputController.swift
//  Galley
//
//  Purpose: The typing-simplicity input layer (§8) — an `NSTextView` subclass that
//  intercepts the primitive editing actions (insert, newline, backspace) and the
//  italic shortcut, translates each into a model-coordinate `InputEvent` against
//  the current caret, applies it through the current `WorkspaceDocument` buffer
//  (the pure reducer), then re-derives the whole rendered string from the model.
//  The model is the single source of truth (ADR-0004); the text storage is never
//  edited directly.
//  Public interface: `InputController` (its `buffer` and `renderFromModel`).
//  Owner context: Galley — the macOS shell's editing layer (ADR-0003).
//

import AppKit
import GalleyCore
import GalleyShell

/// A read-from-model / write-through-reducer text view.
///
/// Every keystroke becomes an `InputEvent` applied to the model; the view then
/// re-renders from the resulting document and restores the caret to its intended
/// model position. Because rendering is a pure function of the model, the view
/// can never drift from the truth.
final class InputController: NSTextView {

    /// The document buffer being edited. Weak: the workspace store owns it.
    weak var buffer: WorkspaceDocument?

    /// The layout from the most recent render — the caret ↔ model map.
    private var layout = EditorLayout(attributedString: NSAttributedString(), segments: [])

    /// The document state the current render reflects, so external changes (file
    /// open) can be detected without re-rendering on our own edits.
    private(set) var lastRenderedDocument: Document?

    // MARK: Snippet completion (§9) — see InputController+Snippets.swift

    /// The `@`-snippet completion list. Shown while the caret sits in an `@`-token
    /// that has matching snippets; the controller owns selection and key handling.
    let completionPopover = SnippetCompletionPopover()

    /// The active completion's anchor: the model position of the `@` and its block.
    /// `nil` when no completion session is open.
    var completionSession: (anchorOffset: Int, blockID: BlockID)?

    /// The snippet matches shown in the completion list, best-first.
    var completionMatches: [Snippet] = []

    /// The highlighted row in the completion list.
    var completionSelection = 0

    // MARK: Block palette (BP2) — see InputController+Palette.swift

    /// The Cmd-; block palette. Shown while the writer is choosing a block to
    /// insert; the controller owns selection and key handling.
    let palettePopover = BlockPalettePopover()

    /// The rows shown in the open palette, or empty when no palette is open.
    var paletteItems: [BlockPaletteItem] = []

    /// The highlighted row in the palette.
    var paletteSelection = 0

    /// The block the chosen item is inserted after — the caret's block when the
    /// palette was summoned. `nil` when no palette session is open.
    var paletteAnchor: BlockID?

    // MARK: Chapter-title editing (LT3) — see InputController+Title.swift

    /// The anchor block of the chapter cut whose heading is being edited inline, or
    /// `nil` when no heading is being edited. While set, that heading renders as the
    /// raw title (macros visible) and keystrokes edit the cut's title; every other
    /// heading shows the resolved title (spreadsheet rule, ADR-0026).
    var editingTitleCut: BlockID?

    /// Guards the selection observer against re-entry while it re-renders for the
    /// raw↔resolved heading swap (LT3).
    var isSyncingSelection = false

    /// The anchor block of a chapter cut whose break is awaiting a Y/N delete
    /// confirmation, or `nil`. While set, that heading shows the confirm prompt and
    /// the next key resolves it (LT3) — backspace never silently merges across a break.
    var pendingBreakDeletion: BlockID?

    /// The caret's character location at the last settled selection, so the selection
    /// observer can tell which way the caret moved and skip past a break accordingly.
    var lastCaretLocation = 0

    // MARK: Intercepted editing actions

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        guard !text.isEmpty else { return }

        // Editing a chapter heading inline routes to the cut's title, not prose (LT3).
        if let titlePosition = caretTitlePosition() {
            insertIntoTitle(text, at: titlePosition)
            return
        }

        // Typing in a figure caption routes to the figure block, not prose (LT4-2).
        if let captionPosition = caretCaptionPosition() {
            insertIntoCaption(text, at: captionPosition)
            return
        }

        guard let model = buffer, let caret = caretModelPosition() else { return }

        // Typing below the last block (caret clamped from the empty area beneath a
        // non-empty last paragraph) starts a fresh paragraph rather than appending,
        // so there is always a new line to begin in.
        if layout.isPastDocumentEnd(selectedRange().location), blockHasText(model.document, caret.blockID) {
            applyEdit(.splitParagraph(blockID: caret.blockID, offset: caret.offset))
            let doc = model.document
            if let index = doc.blocks.firstIndex(where: { $0.id == caret.blockID }), index + 1 < doc.blocks.count {
                let newBlock = doc.blocks[index + 1].id
                applyEdit(.insertText(text, blockID: newBlock, offset: 0))
                renderFromModel(caret: (newBlock, text.count))
                refreshCompletion()
                return
            }
        }

        applyEdit(.insertText(text, blockID: caret.blockID, offset: caret.offset))
        renderFromModel(caret: (caret.blockID, caret.offset + text.count))
        refreshCompletion()
    }

    /// Whether the paragraph block `blockID` carries any non-empty run text. A
    /// non-paragraph block (e.g. a clamped scene break) counts as having text so a
    /// fresh paragraph is started rather than typing into it.
    private func blockHasText(_ doc: Document, _ blockID: BlockID) -> Bool {
        guard let block = doc.blocks.first(where: { $0.id == blockID }),
              case .paragraph(let runs) = block.content else { return true }
        return runs.contains { !$0.text.isEmpty }
    }

    override func insertNewline(_ sender: Any?) {
        // Return in a heading commits the title and drops into the chapter's prose (LT3).
        if caretTitlePosition() != nil {
            exitTitleEditing(moveToBody: true)
            return
        }

        guard let model = buffer, let caret = caretModelPosition() else { return }

        // Second Enter ends a styled block: pressing Enter on an empty paragraph that
        // carries presentation overrides (e.g. a templated epigraph) drops the
        // overrides instead of continuing the style into another line (LT3).
        if let block = model.document.blocks.first(where: { $0.id == caret.blockID }),
           case .paragraph(let runs) = block.content,
           !block.overrides.isEmpty,
           runs.allSatisfy({ $0.text.isEmpty }) {
            applyEdit(.clearOverrides(blockID: caret.blockID))
            renderFromModel(caret: (caret.blockID, 0))
            return
        }

        applyEdit(.splitParagraph(blockID: caret.blockID, offset: caret.offset))

        // The caret follows the text into the new trailing block.
        let doc = model.document
        if let index = doc.blocks.firstIndex(where: { $0.id == caret.blockID }), index + 1 < doc.blocks.count {
            renderFromModel(caret: (doc.blocks[index + 1].id, 0))
        } else {
            renderFromModel(caret: caret)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        // Backspace inside a heading edits the cut's title (LT3).
        if let titlePosition = caretTitlePosition() {
            deleteBackwardInTitle(at: titlePosition)
            return
        }

        // Backspace inside a figure caption edits the figure's caption (LT4-2).
        if let captionPosition = caretCaptionPosition() {
            deleteBackwardInCaption(at: captionPosition)
            return
        }

        guard let model = buffer, let caret = caretModelPosition() else { return }

        if caret.offset > 0 {
            applyEdit(.deleteBackward(blockID: caret.blockID, offset: caret.offset))
            renderFromModel(caret: (caret.blockID, caret.offset - 1))
            refreshCompletion()
            return
        }

        // Offset 0 at a chapter start: do NOT merge across the break (that would
        // silently delete it). Raise a Y/N delete confirmation on the heading; the
        // next key resolves it (LT3).
        let doc = model.document
        if doc.cuts.contains(where: { $0.blockID == caret.blockID && $0.offsetInBlock == nil }) {
            editingTitleCut = nil
            pendingBreakDeletion = caret.blockID
            renderFromModel(caret: (caret.blockID, 0))   // caret stays in front of the break
            return
        }

        // Offset 0: the caret lands at the merge point in the previous paragraph,
        // or stays put when a preceding ornament is removed.
        guard let index = doc.blocks.firstIndex(where: { $0.id == caret.blockID }), index > 0 else { return }
        let previous = doc.blocks[index - 1]

        applyEdit(.deleteBackward(blockID: caret.blockID, offset: 0))

        if case .paragraph(let runs) = previous.content {
            renderFromModel(caret: (previous.id, runs.reduce(0) { $0 + $1.text.count }))
        } else {
            renderFromModel(caret: (caret.blockID, 0))
        }
    }

    override func keyDown(with event: NSEvent) {
        // A pending break-deletion is modal: the next key is its Y/N answer (LT3).
        if pendingBreakDeletion != nil { handleBreakDeletionKey(event); return }
        // Completion navigation (arrows/return/tab/esc) wins while the list is up.
        if completionPopover.isShown, handleCompletionKey(event) { return }
        // The palette captures the same navigation keys while it is open.
        if palettePopover.isShown, handlePaletteKey(event) { return }

        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z":
                if event.modifierFlags.contains(.shift) { performRedo() } else { performUndo() }
                return
            case "y": performRedo(); return   // Windows-style redo alias (macOS native is Cmd-Shift-Z)
            case "i": toggleItalicAtSelection(); return
            case ";": showBlockPalette(); return
            default: break
            }
        }
        // Esc commits an in-progress heading edit and returns to the prose.
        if event.keyCode == 53, editingTitleCut != nil {
            exitTitleEditing(moveToBody: true)
            return
        }
        super.keyDown(with: event)   // routes typing to insertText/insertNewline/deleteBackward
    }

    /// A click dismisses any `@`-token/palette and answers a pending delete "no". A
    /// click on a chapter heading enters inline title editing; clicks elsewhere leave
    /// any heading being edited. Only a click edits a break — arrows glide past (LT3).
    override func mouseDown(with event: NSEvent) {
        endCompletion()
        endPalette()
        if let pending = pendingBreakDeletion { cancelBreakDeletion(pending) }

        let point = convert(event.locationInWindow, from: nil)
        if let cut = headingCut(atPoint: point) {
            beginTitleEditing(cut: cut)
            return
        }
        if editingTitleCut != nil { exitTitleEditing(moveToBody: false) }
        super.mouseDown(with: event)
    }

    /// After any settled selection change, leave a heading the caret has exited and
    /// skip the caret past any break it landed on, so arrows move freely past breaks
    /// (LT3). The caret never rests inside a non-edited heading.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !isSyncingSelection, !stillSelecting else { return }
        syncTitleEditingToCaret()
        // Publish this surface's caret to the shared one so the reveal pane reflects it
        // and the undo timeline records the live (incl. post-edit) caret (ADR-0033).
        // Suppressed during our own re-render/reconcile via `isSyncingSelection`.
        buffer?.currentCaret = caretModelSelection()
    }

    /// Reconciles this view's selection to the shared `currentCaret` (ADR-0033) — used
    /// when the *other* surface moved the caret. A no-op when the view's selection
    /// already matches, so the surface that originated the change does not loop.
    func reconcileSharedCaret() {
        guard let caret = buffer?.currentCaret,
              let lower = layout.characterPosition(forBlock: caret.start.blockID, offset: caret.start.offset),
              let upper = layout.characterPosition(forBlock: caret.end.blockID, offset: caret.end.offset) else { return }
        let target = NSRange(location: lower, length: max(0, upper - lower))
        guard target != selectedRange() else { return }
        withoutSelectionSync { setSelectedRange(target) }
    }

    // MARK: Commands

    /// Toggles italic over the current selection (Cmd-I, §8). A collapsed caret is
    /// a no-op — there is nothing to mark.
    func toggleItalicAtSelection() {
        guard buffer != nil else { return }
        let selection = selectedRange()
        guard let start = layout.modelPosition(forCharacterAt: selection.location),
              let end = layout.modelPosition(forCharacterAt: selection.location + selection.length),
              start.blockID == end.blockID, end.offset > start.offset else { return }

        applyEdit(.toggleItalic(blockID: start.blockID, start: start.offset, end: end.offset))
        renderFromModel(selection: (start, end))
    }

    /// Converts the paragraph at the caret to/from a verse set-piece (§8).
    @objc func toggleVerse(_ sender: Any?) {
        guard let caret = caretModelPosition() else { return }
        applyEdit(.toggleSetPiece(blockID: caret.blockID, kind: .verse))
        renderFromModel(caret: (caret.blockID, 0))
    }

    // MARK: Rendering

    /// Re-derives the rendered string from the model and restores a single caret.
    func renderFromModel(caret: (blockID: BlockID, offset: Int)?) {
        applyRender()
        if let caret, let position = layout.characterPosition(forBlock: caret.blockID, offset: caret.offset) {
            setSelectedRange(NSRange(location: position, length: 0))
        }
    }

    /// Re-renders and restores a selection spanning two model positions.
    private func renderFromModel(selection: (start: (blockID: BlockID, offset: Int), end: (blockID: BlockID, offset: Int))) {
        applyRender()
        if let lower = layout.characterPosition(forBlock: selection.start.blockID, offset: selection.start.offset),
           let upper = layout.characterPosition(forBlock: selection.end.blockID, offset: selection.end.offset) {
            setSelectedRange(NSRange(location: lower, length: max(0, upper - lower)))
        }
    }

    /// Re-renders from the model if it changed outside our own editing (e.g. a
    /// file was opened), placing the caret at the document start.
    func syncFromModelIfNeeded() {
        guard let model = buffer else { return }
        if lastRenderedDocument != model.document {
            renderFromModel(caret: layout.firstEditablePosition() ?? EditorLayout.build(from: model.document).firstEditablePosition())
        }
    }

    // MARK: Internals

    /// The caret's model position, or `nil` when it sits in non-editable
    /// decoration. Visible module-wide so the reference extension can read it.
    func caretModelPosition() -> (blockID: BlockID, offset: Int)? {
        layout.modelPosition(forCharacterAt: selectedRange().location)
    }

    /// The current selection in model coordinates (collapsed for a plain caret), or
    /// `nil` when neither end maps to an editable position. Threaded into edits so the
    /// undo timeline restores the caret the writer had (ADR-0031).
    func caretModelSelection() -> Caret? {
        let range = selectedRange()
        guard let start = layout.modelPosition(forCharacterAt: range.location) else { return nil }
        let end = layout.modelPosition(forCharacterAt: range.location + range.length) ?? start
        return Caret(
            start: Caret.Position(blockID: start.blockID, offset: start.offset),
            end: Caret.Position(blockID: end.blockID, offset: end.offset)
        )
    }

    /// Applies an editing intent through the buffer, recording the pre-edit caret with
    /// the undo checkpoint so undo lands the caret where the edit began (ADR-0031).
    /// The single choke point for editor mutations, so the caret is captured uniformly.
    func applyEdit(_ event: InputEvent) {
        buffer?.apply(event, caret: caretModelSelection())
    }

    /// The layout the most recent render produced — exposed so the title-editing
    /// extension can map caret positions to titles.
    var currentLayout: EditorLayout { layout }

    /// Rebuilds the layout + attributed string from the model and pushes it into
    /// the TextKit 2 content storage. Does not touch the selection. The heading being
    /// edited (if any) renders raw; all others resolved (LT3).
    func applyRender() {
        guard let model = buffer else { return }
        let newLayout = EditorLayout.build(from: model.document, editingTitleCut: editingTitleCut, confirmingDeleteCut: pendingBreakDeletion)
        layout = newLayout
        lastRenderedDocument = model.document

        let string = newLayout.attributedString
        if let contentStorage = textContentStorage, let backing = contentStorage.textStorage {
            contentStorage.performEditingTransaction {
                backing.setAttributedString(string)
            }
        } else {
            textStorage?.setAttributedString(string)
        }
        // Replacing the content storage wholesale does not always repaint the
        // editable TextKit 2 view; force the viewport to re-lay-out and redraw.
        textLayoutManager?.textViewportLayoutController.layoutViewport()
        needsLayout = true
        needsDisplay = true
    }
}
