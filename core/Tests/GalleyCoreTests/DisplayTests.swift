//
//  DisplayTests.swift
//  GalleyCoreTests
//
//  Behavioral tests for `Document.displayProjection()` (§5, ADR-0006), derived
//  from its Behavior Statement: one token per block in reading order, spans
//  carrying explicit italic, and `chapterStart` boundaries spliced at cuts —
//  before the block for boundary/non-paragraph cuts, splitting a paragraph at a
//  mid-block offset. Assertions pin the exact token sequence.
//

import Testing
@testable import GalleyCore

@Suite("displayProjection")
struct DisplayTests {

    // MARK: Block kinds

    @Test func paragraphProjectsRunsAsSpans() {
        let doc = Document(
            blocks: [Block(id: 0, content: .paragraph(runs: [
                Run(text: "She left before the "),
                Run(text: "storm", italic: true),
                Run(text: " broke."),
            ]))],
            nextBlockID: 1
        )

        #expect(doc.displayProjection() == [
            .paragraph(spans: [
                DisplaySpan(text: "She left before the "),
                DisplaySpan(text: "storm", italic: true),
                DisplaySpan(text: " broke."),
            ], overrides: []),
        ])
    }

    @Test func emptyRunsAreDroppedFromSpans() {
        let doc = Document(
            blocks: [Block(id: 0, content: .paragraph(runs: [
                Run(text: ""),
                Run(text: "Only this."),
                Run(text: "", italic: true),
            ]))],
            nextBlockID: 1
        )

        #expect(doc.displayProjection() == [
            .paragraph(spans: [DisplaySpan(text: "Only this.")], overrides: []),
        ])
    }

    @Test func sceneBreakProjectsToSceneBreakToken() {
        let doc = Document(blocks: [Block(id: 0, content: .sceneBreak)], nextBlockID: 1)
        #expect(doc.displayProjection() == [.sceneBreak])
    }

    @Test func setPieceProjectsOneTokenPerLineCarryingKind() {
        let doc = Document(
            blocks: [Block(id: 0, content: .setPiece(kind: .verse, lines: [
                [Run(text: "Roses are red,")],
                [Run(text: "violets are "), Run(text: "blue", italic: true)],
            ]))],
            nextBlockID: 1
        )

        #expect(doc.displayProjection() == [
            .setPieceLine(kind: .verse, spans: [DisplaySpan(text: "Roses are red,")], overrides: []),
            .setPieceLine(kind: .verse, spans: [
                DisplaySpan(text: "violets are "),
                DisplaySpan(text: "blue", italic: true),
            ], overrides: []),
        ])
    }

    @Test func paragraphCarriesBlockOverrides() {
        let doc = Document(
            blocks: [Block(
                id: 0,
                content: .paragraph(runs: [Run(text: "Centered.")]),
                overrides: [.alignment(.center)]
            )],
            nextBlockID: 1
        )

        #expect(doc.displayProjection() == [
            .paragraph(spans: [DisplaySpan(text: "Centered.")], overrides: [.alignment(.center)]),
        ])
    }

    // MARK: Chapter splicing

    @Test func boundaryCutOpensChapterBeforeParagraph() {
        let doc = Document(
            blocks: [Block(id: 0, content: .paragraph(runs: [Run(text: "Chapter body.")]))],
            cuts: [ChapterCut(blockID: 0, offsetInBlock: nil, title: "One")],
            nextBlockID: 1
        )

        #expect(doc.displayProjection() == [
            .chapterStart(role: .chapter, title: "One"),
            .paragraph(spans: [DisplaySpan(text: "Chapter body.")], overrides: []),
        ])
    }

    @Test func boundaryCutOpensChapterBeforeSceneBreak() {
        let doc = Document(
            blocks: [Block(id: 0, content: .sceneBreak)],
            cuts: [ChapterCut(blockID: 0, offsetInBlock: nil, title: "Break Chapter")],
            nextBlockID: 1
        )

        #expect(doc.displayProjection() == [
            .chapterStart(role: .chapter, title: "Break Chapter"),
            .sceneBreak,
        ])
    }

    @Test func midParagraphCutSplitsParagraphAtOffset() {
        let doc = Document(
            blocks: [Block(id: 0, content: .paragraph(runs: [Run(text: "Before. After.")]))],
            cuts: [ChapterCut(blockID: 0, offsetInBlock: 8, title: "Two")],
            nextBlockID: 1
        )

        #expect(doc.displayProjection() == [
            .paragraph(spans: [DisplaySpan(text: "Before. ")], overrides: []),
            .chapterStart(role: .chapter, title: "Two"),
            .paragraph(spans: [DisplaySpan(text: "After.")], overrides: []),
        ])
    }

    @Test func midParagraphCutSplitsInsideAnItalicSpanPreservingItalic() {
        // "plain " (6) + "italic" (italic) ; cut at offset 9 lands inside "ita|lic".
        let doc = Document(
            blocks: [Block(id: 0, content: .paragraph(runs: [
                Run(text: "plain "),
                Run(text: "italic", italic: true),
            ]))],
            cuts: [ChapterCut(blockID: 0, offsetInBlock: 9, title: "Mid")],
            nextBlockID: 1
        )

        #expect(doc.displayProjection() == [
            .paragraph(spans: [
                DisplaySpan(text: "plain "),
                DisplaySpan(text: "ita", italic: true),
            ], overrides: []),
            .chapterStart(role: .chapter, title: "Mid"),
            .paragraph(spans: [DisplaySpan(text: "lic", italic: true)], overrides: []),
        ])
    }

    @Test func cutAtOffsetZeroYieldsOnlyChapterStartNoBlankParagraph() {
        let doc = Document(
            blocks: [Block(id: 0, content: .paragraph(runs: [Run(text: "Body.")]))],
            cuts: [ChapterCut(blockID: 0, offsetInBlock: 0, title: "Start")],
            nextBlockID: 1
        )

        #expect(doc.displayProjection() == [
            .chapterStart(role: .chapter, title: "Start"),
            .paragraph(spans: [DisplaySpan(text: "Body.")], overrides: []),
        ])
    }

    @Test func boundaryCutCarriesItsRoleSoAProloguePrintsAsAPrologue() {
        let doc = Document(
            blocks: [Block(id: 0, content: .paragraph(runs: [Run(text: "Before it all.")]))],
            cuts: [ChapterCut(blockID: 0, role: .prologue)],
            nextBlockID: 1
        )

        #expect(doc.displayProjection() == [
            .chapterStart(role: .prologue, title: nil),
            .paragraph(spans: [DisplaySpan(text: "Before it all.")], overrides: []),
        ])
    }

    @Test func emptyDocumentProjectsToNoTokens() {
        #expect(Document().displayProjection() == [])
    }
}
