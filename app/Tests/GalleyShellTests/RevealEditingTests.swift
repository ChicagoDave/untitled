//
//  RevealEditingTests.swift
//  GalleyShellTests
//
//  Behavioral tests for the reveal code→edit mapping (LT5-2, ADR-0034) — the pure
//  function `revealDeleteAction(for:in:)` that `RevealController` dispatches when a
//  code chip is deleted. Verifies every row of the ADR-0034 table: which `InputEvent`
//  (or cut removal) each `CodeID` deletion produces, that paired codes resolve to the
//  one span/kind event, and that deferred codes report `.deferred`.
//

import Testing
import GalleyCore
@testable import GalleyShell

@Suite("Reveal code→edit mapping (ADR-0034)")
struct RevealEditingTests {

    private func doc(_ blocks: [Block]) -> Document {
        Document(blocks: blocks, nextBlockID: (blocks.map(\.id).max() ?? -1) + 1)
    }

    @Test func sceneBreakAndFigureChipsMapToDeleteBlock() {
        let d = doc([
            Block(id: 0, content: .paragraph(runs: [Run(text: "x")])),
            Block(id: 1, content: .sceneBreak),
            Block(id: 2, content: .figure(imageRef: "a.png", caption: "")),
        ])
        #expect(revealDeleteAction(for: .sceneBreak(1), in: d) == .event(.deleteBlock(blockID: 1)))
        #expect(revealDeleteAction(for: .figure(2), in: d) == .event(.deleteBlock(blockID: 2)))
    }

    @Test func overrideChipMapsToClearOverrideAtIndex() {
        let d = doc([Block(id: 0, content: .paragraph(runs: [Run(text: "x")]), overrides: [.alignment(.center), .smallCaps])])
        #expect(revealDeleteAction(for: .override(0, 1), in: d) == .event(.clearOverride(blockID: 0, index: 1)))
    }

    @Test func bothItalicChipsMapToToggleOverTheSameSpan() {
        // "ab" + italic "cd" + "ef" → span 0 is offsets 2..<4; deleting either [i] or
        // [/i] toggles that one span (paired deletion).
        let d = doc([Block(id: 0, content: .paragraph(runs: [
            Run(text: "ab"), Run(text: "cd", italic: true), Run(text: "ef")
        ]))])
        let expected = RevealDeleteAction.event(.toggleItalic(blockID: 0, start: 2, end: 4))
        #expect(revealDeleteAction(for: .italicOpen(0, 0), in: d) == expected)
        #expect(revealDeleteAction(for: .italicClose(0, 0), in: d) == expected)
    }

    @Test func secondItalicSpanResolvesToItsOwnOffsets() {
        let d = doc([Block(id: 0, content: .paragraph(runs: [
            Run(text: "a", italic: true), Run(text: "bb"), Run(text: "c", italic: true)
        ]))])
        #expect(revealDeleteAction(for: .italicOpen(0, 1), in: d) == .event(.toggleItalic(blockID: 0, start: 3, end: 4)))
    }

    @Test func setPieceChipsMapToToggleSetPieceWithItsKind() {
        let d = doc([Block(id: 0, content: .setPiece(kind: .epigraph, lines: [[Run(text: "line")]]))])
        let expected = RevealDeleteAction.event(.toggleSetPiece(blockID: 0, kind: .epigraph))
        #expect(revealDeleteAction(for: .setPieceOpen(0), in: d) == expected)
        #expect(revealDeleteAction(for: .setPieceClose(0), in: d) == expected)
    }

    @Test func boundaryChapterChipMapsToRemoveCut() {
        var d = doc([Block(id: 0, content: .paragraph(runs: [Run(text: "x")]))])
        d.placeChapterCut(atBlock: 0)
        #expect(revealDeleteAction(for: .chapter(0, nil), in: d) == .removeCut(blockID: 0))
    }

    @Test func midBlockChapterAndSetPieceLineAreDeferred() {
        let d = doc([Block(id: 0, content: .setPiece(kind: .verse, lines: [[Run(text: "x")]]))])
        #expect(revealDeleteAction(for: .chapter(0, 3), in: d) == .deferred)
        #expect(revealDeleteAction(for: .line(0, 0), in: d) == .deferred)
    }

    @Test func paragraphHardReturnChipIsDeferred() {
        let d = doc([Block(id: 0, content: .paragraph(runs: [Run(text: "x")]))])
        // Deleting [p] is a paragraph merge — display-only in v1, so deferred (ADR-0035).
        #expect(revealDeleteAction(for: .paragraph(0), in: d) == .deferred)
    }

    @Test func sectionSpacingChipIsDeferred() {
        let d = doc([Block(id: 0, content: .paragraph(runs: [Run(text: "x")]))])
        // [sp] is derived from the break — display-only, so deletion is deferred (ADR-0035).
        #expect(revealDeleteAction(for: .sectionSpace(0), in: d) == .deferred)
    }

    @Test func italicSpanForNonParagraphIsNil() {
        let d = doc([Block(id: 0, content: .setPiece(kind: .verse, lines: [[Run(text: "x", italic: true)]]))])
        #expect(italicSpan(blockID: 0, spanIndex: 0, in: d) == nil)
        #expect(revealDeleteAction(for: .italicOpen(0, 0), in: d) == .deferred)   // no paragraph span → deferred
    }
}
