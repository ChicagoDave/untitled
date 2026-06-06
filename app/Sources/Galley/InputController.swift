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

    // MARK: Intercepted editing actions

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        guard let model = buffer, let caret = caretModelPosition(), !text.isEmpty else { return }

        model.apply(.insertText(text, blockID: caret.blockID, offset: caret.offset))
        renderFromModel(caret: (caret.blockID, caret.offset + text.count))
    }

    override func insertNewline(_ sender: Any?) {
        guard let model = buffer, let caret = caretModelPosition() else { return }

        model.apply(.splitParagraph(blockID: caret.blockID, offset: caret.offset))

        // The caret follows the text into the new trailing block.
        let doc = model.document
        if let index = doc.blocks.firstIndex(where: { $0.id == caret.blockID }), index + 1 < doc.blocks.count {
            renderFromModel(caret: (doc.blocks[index + 1].id, 0))
        } else {
            renderFromModel(caret: caret)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        guard let model = buffer, let caret = caretModelPosition() else { return }

        if caret.offset > 0 {
            model.apply(.deleteBackward(blockID: caret.blockID, offset: caret.offset))
            renderFromModel(caret: (caret.blockID, caret.offset - 1))
            return
        }

        // Offset 0: the caret lands at the merge point in the previous paragraph,
        // or stays put when a preceding ornament is removed.
        let doc = model.document
        guard let index = doc.blocks.firstIndex(where: { $0.id == caret.blockID }), index > 0 else { return }
        let previous = doc.blocks[index - 1]

        model.apply(.deleteBackward(blockID: caret.blockID, offset: 0))

        if case .paragraph(let runs) = previous.content {
            renderFromModel(caret: (previous.id, runs.reduce(0) { $0 + $1.text.count }))
        } else {
            renderFromModel(caret: (caret.blockID, 0))
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "i": toggleItalicAtSelection(); return
            default: break
            }
        }
        super.keyDown(with: event)   // routes typing to insertText/insertNewline/deleteBackward
    }

    // MARK: Commands

    /// Toggles italic over the current selection (Cmd-I, §8). A collapsed caret is
    /// a no-op — there is nothing to mark.
    func toggleItalicAtSelection() {
        guard let model = buffer else { return }
        let selection = selectedRange()
        guard let start = layout.modelPosition(forCharacterAt: selection.location),
              let end = layout.modelPosition(forCharacterAt: selection.location + selection.length),
              start.blockID == end.blockID, end.offset > start.offset else { return }

        model.apply(.toggleItalic(blockID: start.blockID, start: start.offset, end: end.offset))
        renderFromModel(selection: (start, end))
    }

    /// Converts the paragraph at the caret to/from a verse set-piece (§8).
    @objc func toggleVerse(_ sender: Any?) {
        guard let model = buffer, let caret = caretModelPosition() else { return }
        model.apply(.toggleSetPiece(blockID: caret.blockID, kind: .verse))
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

    private func caretModelPosition() -> (blockID: BlockID, offset: Int)? {
        layout.modelPosition(forCharacterAt: selectedRange().location)
    }

    /// Rebuilds the layout + attributed string from the model and pushes it into
    /// the TextKit 2 content storage. Does not touch the selection.
    private func applyRender() {
        guard let model = buffer else { return }
        let newLayout = EditorLayout.build(from: model.document)
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
