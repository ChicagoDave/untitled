//
//  RevealController.swift
//  Galley
//
//  Purpose: The Reveal Codes editing surface (LT5, ADR-0030/ADR-0032) — an
//  `NSTextView` subclass that renders the model-annotated reveal stream
//  (`RevealLayout`) with codes as atomic bracketed chips, and shares one caret with
//  the prose editor through `WorkspaceDocument.currentCaret` (ADR-0033). In phase
//  LT5-1 it is read-only *as to the document model*: it positions and shares the
//  caret, steps the caret over a code as one unit, and triggers shared undo/redo —
//  but dispatches no `InputEvent` (no model mutation). Bidirectional code editing is
//  LT5-2 (ADR-0034). The model is the single source of truth (ADR-0004); the text
//  storage is never edited directly.
//  Public interface: `RevealController` (its `buffer`, `render`, `syncIfNeeded`,
//  `reconcileSharedCaret`).
//  Owner context: Galley — the macOS shell's editing layer (ADR-0003).
//

import AppKit
import GalleyCore
import GalleyShell

/// A read-from-model reveal view that shares the one caret with the prose editor.
final class RevealController: NSTextView {

    /// The document buffer being revealed. Weak: the workspace store owns it.
    weak var buffer: WorkspaceDocument?

    /// The layout from the most recent render — the reveal caret ↔ model map.
    private var layout = RevealLayout(attributedString: NSAttributedString(), segments: [])

    /// The document state the current render reflects, so external changes re-render
    /// without re-rendering on our own (caret-only) activity.
    private var lastRenderedDocument: Document?

    /// Guards the selection observer against re-entry while we reconcile or re-render.
    private var isSyncing = false

    /// The caret location at the last settled selection, so the step-over knows which
    /// way the caret moved and snaps off a code chip accordingly.
    private var lastCaretLocation = 0

    // MARK: Rendering

    /// Rebuilds the reveal layout from the model and pushes it into the text storage,
    /// then reconciles the caret to the shared `currentCaret`. Does not mutate the model.
    func render() {
        guard let buffer else { return }
        layout = RevealLayout.build(from: buffer.document)
        lastRenderedDocument = buffer.document

        let string = layout.attributedString
        if let contentStorage = textContentStorage, let backing = contentStorage.textStorage {
            contentStorage.performEditingTransaction {
                backing.setAttributedString(string)
            }
        } else {
            textStorage?.setAttributedString(string)
        }
        // A wholesale content-storage swap does not always repaint the TextKit 2 view;
        // force the viewport to re-lay-out and redraw (same fix as the prose editor).
        textLayoutManager?.textViewportLayoutController.layoutViewport()
        needsLayout = true
        needsDisplay = true

        reconcileSharedCaret()
    }

    /// Re-renders only if the model changed outside our own activity (an edit in the
    /// prose pane, an undo, a file open). A pure caret move does not change the model,
    /// so it falls through to a caret-only reconcile by the host.
    func syncIfNeeded() {
        guard let buffer else { return }
        if lastRenderedDocument != buffer.document { render() }
    }

    /// Reconciles this view's selection to the shared `currentCaret` (ADR-0033) — used
    /// when the *other* surface moved the caret. A no-op when the selection already
    /// matches, so the surface that originated the change does not loop.
    func reconcileSharedCaret() {
        guard let caret = buffer?.currentCaret, let range = layout.characterRange(for: caret) else { return }
        guard range != selectedRange() else { return }
        isSyncing = true
        defer { isSyncing = false }
        setSelectedRange(range)
    }

    // MARK: Caret sharing + step-over

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !isSyncing, !stillSelecting else { return }

        // The caret never rests inside a code chip — snap it off to the edge it was
        // moving toward, exactly as the prose editor glides past a heading (ADR-0030).
        let location = selectedRange().location
        if selectedRange().length == 0, let code = layout.codeSegment(forCharacterAt: location) {
            let forward = location >= lastCaretLocation
            let edge = forward ? code.utf16Range.location + code.utf16Range.length : code.utf16Range.location
            isSyncing = true
            setSelectedRange(NSRange(location: edge, length: 0))
            isSyncing = false
        }
        lastCaretLocation = selectedRange().location

        // Publish this surface's caret to the shared one so the prose pane reflects it.
        buffer?.currentCaret = layout.modelPosition(forCharacterAt: selectedRange().location).map {
            Caret(blockID: $0.blockID, offset: $0.offset)
        }
    }

    // MARK: Key handling

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z":
                // Shared timeline: undo/redo work identically from either pane (ADR-0033).
                if event.modifierFlags.contains(.shift) { buffer?.performRedo() } else { buffer?.performUndo() }
                render()
                return
            case "y":
                buffer?.performRedo(); render(); return
            default: break
            }
        }
        // Arrow/navigation keys fall through; LT5-1 dispatches no editing events, so
        // typing and deletion are intercepted as no-ops below.
        super.keyDown(with: event)
    }

    // MARK: Bidirectional editing (LT5-2, ADR-0034)

    /// Typing in an editable prose segment inserts text into the model at the caret's
    /// model position; both panes follow the one model change (ADR-0004).
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        guard !text.isEmpty, let buffer,
              let pos = layout.modelPosition(forCharacterAt: selectedRange().location) else { return }
        let pre = buffer.currentCaret
        buffer.apply(.insertText(text, blockID: pos.blockID, offset: pos.offset), caret: pre)
        buffer.currentCaret = Caret(blockID: pos.blockID, offset: pos.offset + text.count)
        render()
    }

    /// Backspace deletes the code chip immediately before the caret (the WordPerfect
    /// "delete a code" gesture, ADR-0030/ADR-0034) or, in prose, the preceding
    /// character (which at a block boundary merges/removes via the reducer).
    override func deleteBackward(_ sender: Any?) {
        guard let buffer else { return }
        let sel = selectedRange()
        // A selection covering a code chip (the writer selected the chip), or a
        // collapsed caret just after one, deletes that chip.
        if let code = codeWithin(sel) ?? layout.codeEndingAt(sel.location), let id = code.codeID { deleteCode(id); return }
        let loc = sel.location
        guard let pos = layout.modelPosition(forCharacterAt: loc) else { return }
        let pre = buffer.currentCaret
        buffer.apply(.deleteBackward(blockID: pos.blockID, offset: pos.offset), caret: pre)
        buffer.currentCaret = Caret(blockID: pos.blockID, offset: max(0, pos.offset - 1))
        render()
    }

    /// Forward Delete removes the code chip immediately after the caret (or one the
    /// selection covers).
    override func deleteForward(_ sender: Any?) {
        let sel = selectedRange()
        guard let code = codeWithin(sel) ?? layout.codeStartingAt(sel.location), let id = code.codeID else { return }
        deleteCode(id)
    }

    /// The code chip a non-empty selection covers (overlaps), if any — so selecting a
    /// chip and pressing Delete/Backspace removes it (a robust deletion gesture
    /// alongside caret-adjacency).
    private func codeWithin(_ range: NSRange) -> RevealLayout.Segment? {
        guard range.length > 0 else { return nil }
        let lo = range.location, hi = range.location + range.length
        return layout.segments.first { seg in
            guard seg.isCode else { return false }
            let s = seg.utf16Range.location, e = s + seg.utf16Range.length
            return s < hi && e > lo   // overlap
        }
    }

    /// Structural newline insertion from the reveal surface is deferred (LT5-2 edits
    /// text and codes; splitting blocks from reveal is a later concern).
    override func insertNewline(_ sender: Any?) { /* deferred */ }

    /// Deletes the model element a reveal code chip addresses, per the pure code→edit
    /// mapping (`revealDeleteAction`, ADR-0034). Paired codes (`[i]`/`[/i]`, set-piece
    /// open/close) collapse together because one event removes both. A thin dispatcher:
    /// the mapping logic is headlessly tested in `RevealEditingTests`.
    private func deleteCode(_ id: CodeID) {
        guard let buffer else { return }
        let pre = buffer.currentCaret
        switch revealDeleteAction(for: id, in: buffer.document) {
        case .event(let event):
            buffer.apply(event, caret: pre)
            buffer.currentCaret = caretAfterDelete(id)
        case .removeCut(let blockID):
            buffer.removeCut(atBlock: blockID, caret: pre)
            buffer.currentCaret = Caret(blockID: blockID, offset: 0)
        case .deferred:
            return
        }
        render()
    }

    /// Where the caret lands after a code deletion: the affected block's start when it
    /// survives (override/italic/set-piece), or `nil` (reconcile falls back to the
    /// first editable position) when the block itself is removed (scene break/figure).
    private func caretAfterDelete(_ id: CodeID) -> Caret? {
        switch id {
        case .sceneBreak, .figure: return nil
        case .override(let b, _), .italicOpen(let b, _), .italicClose(let b, _),
             .setPieceOpen(let b), .setPieceClose(let b):
            return Caret(blockID: b, offset: 0)
        case .chapter, .line: return nil
        }
    }
}
