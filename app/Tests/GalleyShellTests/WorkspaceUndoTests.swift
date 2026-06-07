//
//  WorkspaceUndoTests.swift
//  GalleyShellTests
//
//  Behavioral tests for `WorkspaceDocument` model-snapshot undo/redo (LT3, ADR-0031),
//  derived from its Behavior Statement. Each asserts on the restored `document` state
//  AND the restored caret — undo returns the caret as it was before the edit; redo
//  returns the caret as it was after it (the caret recorded at undo time). Covers the
//  checkpoint-before-edit, the redo-after-undo, the redo-cleared-by-new-edit fork,
//  selection round-trip, and the empty-stack no-ops. Tests run on the main actor
//  because `WorkspaceDocument` is `@MainActor`.
//

import Testing
import GalleyCore
@testable import GalleyShell

@MainActor
@Suite("WorkspaceDocument undo/redo")
struct WorkspaceUndoTests {

    /// A buffer seeded with one paragraph carrying `text`.
    private func buffer(text: String) -> WorkspaceDocument {
        WorkspaceDocument(document: Document(
            blocks: [Block(id: 0, content: .paragraph(runs: [Run(text: text)]))],
            nextBlockID: 1
        ))
    }

    @Test func undoRestoresThePreEditDocumentAndCaret() {
        let doc = buffer(text: "Hello")
        doc.apply(.insertText("!", blockID: 0, offset: 5), caret: Caret(blockID: 0, offset: 5))
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "Hello!")]))

        let restored = doc.undo(currentCaret: Caret(blockID: 0, offset: 6))
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "Hello")]))
        #expect(restored == Caret(blockID: 0, offset: 5))   // the caret as it was before the edit
    }

    @Test func redoReappliesTheUndoneEditAndItsPostEditCaret() {
        let doc = buffer(text: "Hello")
        doc.apply(.insertText("!", blockID: 0, offset: 5), caret: Caret(blockID: 0, offset: 5))
        doc.undo(currentCaret: Caret(blockID: 0, offset: 6))

        let redone = doc.redo(currentCaret: Caret(blockID: 0, offset: 5))
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "Hello!")]))
        #expect(redone == Caret(blockID: 0, offset: 6))   // the caret recorded at undo time (after the edit)
    }

    @Test func aNewEditAfterUndoClearsTheRedoTimeline() {
        let doc = buffer(text: "Hi")
        doc.apply(.insertText("!", blockID: 0, offset: 2), caret: Caret(blockID: 0, offset: 2))   // "Hi!"
        doc.undo()                                                                                // back to "Hi"
        doc.apply(.insertText("?", blockID: 0, offset: 2), caret: Caret(blockID: 0, offset: 2))   // "Hi?" — forks
        #expect(!doc.canRedo)                                                                     // the "!" future is gone
        #expect(doc.redo() == nil)                                                                // no-op
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "Hi?")]))
    }

    @Test func undoSpansSeveralEditsOneStepAtATime() {
        let doc = buffer(text: "")
        doc.apply(.insertText("a", blockID: 0, offset: 0), caret: Caret(blockID: 0, offset: 0))
        doc.apply(.insertText("b", blockID: 0, offset: 1), caret: Caret(blockID: 0, offset: 1))

        #expect(doc.undo(currentCaret: Caret(blockID: 0, offset: 2)) == Caret(blockID: 0, offset: 1))
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "a")]))
        #expect(doc.undo(currentCaret: Caret(blockID: 0, offset: 1)) == Caret(blockID: 0, offset: 0))
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "")]))
    }

    @Test func undoRestoresASelectionRange() {
        let doc = buffer(text: "Hello")
        let span = Caret(start: .init(blockID: 0, offset: 0), end: .init(blockID: 0, offset: 5))
        doc.apply(.toggleItalic(blockID: 0, start: 0, end: 5), caret: span)

        let restored = doc.undo()
        #expect(restored == span)
        #expect(restored?.isCollapsed == false)   // the marked range, not a collapsed caret
    }

    @Test func undoRestoresACutTitleEditAndItsCaret() {
        let doc = buffer(text: "Body")
        doc.placeCut(atBlock: 0)
        doc.setCutTitle(atBlock: 0, to: "Chapter #a")
        #expect(doc.document.cuts.first?.title == "Chapter #a")

        let afterTitle = doc.undo()                          // undo the title set
        #expect(doc.document.cuts.first?.title == nil)
        #expect(afterTitle == Caret(blockID: 0, offset: 0))  // a cut edit lands the caret at its block
        let afterPlace = doc.undo()                          // undo the cut placement
        #expect(doc.document.cuts.isEmpty)
        #expect(afterPlace == Caret(blockID: 0, offset: 0))
    }

    @Test func undoOnEmptyHistoryIsANoOp() {
        let doc = buffer(text: "Steady")
        #expect(!doc.canUndo)
        #expect(doc.undo() == nil)                            // must not crash; nothing to restore
        #expect(doc.document.blocks[0].content == .paragraph(runs: [Run(text: "Steady")]))
    }
}
