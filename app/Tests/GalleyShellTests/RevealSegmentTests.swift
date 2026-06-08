//
//  RevealSegmentTests.swift
//  GalleyShellTests
//
//  Behavioral tests for `revealSegments(of:)` — the model-annotated reveal projection
//  (LT5, ADR-0032). Asserts that prose-text segments carry the right `(blockID,
//  offset)` so a reveal caret can map to the model, that codes surface as atomic
//  non-editable chips, and (the drift guard) that the `CodeID` order here matches
//  GalleyCore's flat `revealProjection()` so the two projections cannot diverge.
//

import Testing
import GalleyCore
@testable import GalleyShell

@Suite("Reveal annotated projection (ADR-0032)")
struct RevealSegmentTests {

    /// The code IDs of a segment stream, in order.
    private func codeIDs(_ segments: [RevealSegment]) -> [CodeID] {
        segments.compactMap { if case .code(_, let id) = $0.kind { return id } else { return nil } }
    }

    /// The editable text segments of a stream, as (text, blockID, offset) tuples.
    private func editableText(_ segments: [RevealSegment]) -> [(String, BlockID?, Int?)] {
        segments.compactMap { seg in
            guard seg.editable, case .text(let s) = seg.kind else { return nil }
            return (s, seg.blockID, seg.offset)
        }
    }

    @Test func paragraphTextSegmentsCarryInBlockOffsets() {
        // "Hello " + italic "brave" + " world" → text runs split by the [i]/[/i] chips,
        // each annotated with its in-block character start offset.
        let doc = Document(blocks: [
            Block(id: 0, content: .paragraph(runs: [
                Run(text: "Hello "), Run(text: "brave", italic: true), Run(text: " world")
            ]))
        ], nextBlockID: 1)

        let segments = revealSegments(of: doc)
        let text = editableText(segments)

        #expect(text.count == 3)
        #expect(text[0].0 == "Hello " && text[0].1 == 0 && text[0].2 == 0)
        #expect(text[1].0 == "brave"  && text[1].1 == 0 && text[1].2 == 6)
        #expect(text[2].0 == " world" && text[2].1 == 0 && text[2].2 == 11)
        // The italic span surfaces as a paired, non-editable code; the paragraph ends
        // with its [p] hard-return chip (ADR-0035).
        #expect(codeIDs(segments) == [.italicOpen(0, 0), .italicClose(0, 0), .paragraph(0)])
    }

    @Test func chapterCutEmitsCodeThenResolvedTitleAsNonEditableText() {
        var doc = Document(blocks: [
            Block(id: 0, content: .paragraph(runs: [Run(text: "Body")]))
        ], nextBlockID: 1)
        doc.placeChapterCut(atBlock: 0)
        doc.setChapterCutTitle(atBlock: 0, to: "Chapter One")

        let segments = revealSegments(of: doc)

        #expect(codeIDs(segments).first == .chapter(0, nil))
        // The title follows the chapter chip as a NON-editable text segment in LT5-1,
        // annotated to the cut's anchor block (it becomes editable in LT5-2).
        let titleSeg = segments.first { seg in
            if case .text(let s) = seg.kind, s == "Chapter One" { return true }
            return false
        }
        #expect(titleSeg != nil)
        #expect(titleSeg?.editable == false)
        #expect(titleSeg?.blockID == 0)
        // After the title comes the [sp] opener-spacing chip, then the body (ADR-0035):
        // the code order is [Chapter], [sp], [p] (the title is text, not a code).
        #expect(codeIDs(segments) == [.chapter(0, nil), .sectionSpace(0), .paragraph(0)])
        // The prose body is still editable.
        #expect(editableText(segments).contains { $0.0 == "Body" && $0.2 == 0 })
    }

    @Test func emptyParagraphStillOffersAnEditableLandingSegment() {
        let doc = Document(blocks: [Block(id: 0, content: .paragraph(runs: []))], nextBlockID: 1)
        let text = editableText(revealSegments(of: doc))
        #expect(text.count == 1)
        #expect(text[0].0 == "" && text[0].1 == 0 && text[0].2 == 0)
    }

    @Test func figureAndSceneBreakSurfaceAsAtomicNonEditableChips() {
        let doc = Document(blocks: [
            Block(id: 0, content: .paragraph(runs: [Run(text: "x")])),
            Block(id: 1, content: .sceneBreak),
            Block(id: 2, content: .figure(imageRef: "lighthouse.jpg", caption: "Dawn")),
        ], nextBlockID: 3)

        let segments = revealSegments(of: doc)
        // The paragraph's [p] hard return precedes the scene-break and figure chips.
        #expect(codeIDs(segments) == [.paragraph(0), .sceneBreak(1), .figure(2)])
        // Neither chip is editable; the caret steps over them.
        #expect(segments.allSatisfy { seg in
            if case .code = seg.kind { return seg.editable == false }
            return true
        })
    }

    @Test func setPieceEmitsOpenLinesAndClose() {
        let doc = Document(blocks: [
            Block(id: 0, content: .setPiece(kind: .verse, lines: [
                [Run(text: "Roses are red")],
                [Run(text: "Violets blue")],
            ]))
        ], nextBlockID: 1)

        let segments = revealSegments(of: doc)
        #expect(codeIDs(segments) == [
            .setPieceOpen(0), .line(0, 0), .line(0, 1), .setPieceClose(0)
        ])
        // Set-piece line text is shown but NOT editable in LT5-1.
        #expect(editableText(segments).isEmpty)
    }

    @Test func overrideChipsSurfaceBeforeProse() {
        let doc = Document(blocks: [
            Block(id: 0, content: .paragraph(runs: [Run(text: "Centered")]), overrides: [.alignment(.center), .smallCaps])
        ], nextBlockID: 1)

        let segments = revealSegments(of: doc)
        #expect(codeIDs(segments) == [.override(0, 0), .override(0, 1), .paragraph(0)])
    }

    /// The drift guard (ADR-0032): the annotated projection's code order must match the
    /// flat `revealProjection()` for the same document, so the two cannot diverge.
    @Test func codeOrderMatchesFlatRevealProjection() {
        var doc = Document(blocks: [
            Block(id: 0, content: .paragraph(runs: [Run(text: "Once "), Run(text: "upon", italic: true)]), overrides: [.alignment(.center)]),
            Block(id: 1, content: .sceneBreak),
            Block(id: 2, content: .setPiece(kind: .epigraph, lines: [[Run(text: "a line")]])),
            Block(id: 3, content: .figure(imageRef: "map.png", caption: "")),
            Block(id: 4, content: .paragraph(runs: [Run(text: "End")])),
        ], nextBlockID: 5)
        doc.placeChapterCut(atBlock: 4)
        doc.setChapterCutTitle(atBlock: 4, to: "Chapter #a")

        let annotated = codeIDs(revealSegments(of: doc))
        let flat: [CodeID] = doc.revealProjection().compactMap {
            if case .code(_, let id) = $0 { return id } else { return nil }
        }
        #expect(annotated == flat)
    }
}
