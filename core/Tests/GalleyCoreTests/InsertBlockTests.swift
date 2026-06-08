//
//  InsertBlockTests.swift
//  GalleyCoreTests
//
//  Behavioral tests for the `insertBlock` reducer arm (BP2), derived from its
//  Behavior Statement. Each asserts on the resulting block stream — position,
//  content, overrides, the freshly minted identity — or on the no-op for a stale
//  anchor, never on return shape alone. A sidecar round-trip confirms a
//  palette-inserted block (including the new `blockQuote` override) persists.
//

import Testing
@testable import GalleyCore

/// A two-paragraph document whose block IDs are known, for anchoring inserts.
private func twoParagraphs() -> Document {
    Document(
        blocks: [
            Block(id: 0, content: .paragraph(runs: [Run(text: "First.")])),
            Block(id: 1, content: .paragraph(runs: [Run(text: "Second.")])),
        ],
        nextBlockID: 2
    )
}

@Suite("insertBlock reducer arm")
struct InsertBlockTests {

    // MARK: DOES

    @Test func insertsAfterTheAnchorWithContentOverridesAndAFreshID() {
        let doc = twoParagraphs()
        let result = applyInput(
            .insertBlock(content: .paragraph(runs: [Run(text: "Epigraph.")]),
                         overrides: [.alignment(.center), .smallCaps],
                         afterBlockID: 0),
            to: doc
        )
        #expect(result.blocks.count == 3)
        #expect(result.blocks.map(\.id) == [0, 2, 1])            // new block (id 2) sits between
        #expect(result.blocks[1].overrides == [.alignment(.center), .smallCaps])
        if case .paragraph(let runs) = result.blocks[1].content {
            #expect(runs == [Run(text: "Epigraph.")])
        } else {
            Issue.record("expected a paragraph")
        }
    }

    @Test func advancesNextBlockIDSoTheMintedIDNeverCollides() {
        let doc = twoParagraphs()
        let result = applyInput(
            .insertBlock(content: .paragraph(runs: [Run(text: "x")]), overrides: [], afterBlockID: 1),
            to: doc
        )
        #expect(result.nextBlockID == 3)
        #expect(result.blocks.map(\.id) == [0, 1, 2])            // appended after the last block
    }

    @Test func insertsABlockQuoteOverrideBlock() {
        let doc = twoParagraphs()
        let result = applyInput(
            .insertBlock(content: .paragraph(runs: [Run(text: "Set off.")]),
                         overrides: [.blockQuote], afterBlockID: 0),
            to: doc
        )
        #expect(result.blocks[1].overrides == [.blockQuote])
    }

    @Test func leavesCutsOnOtherBlocksUntouched() {
        var doc = twoParagraphs()
        doc.cuts = [ChapterCut(blockID: 1, title: "Two")]
        let result = applyInput(
            .insertBlock(content: .sceneBreak, overrides: [], afterBlockID: 0),
            to: doc
        )
        #expect(result.cuts == [ChapterCut(blockID: 1, title: "Two")])   // anchor unmoved
    }

    // MARK: Clear overrides (LT3)

    @Test func clearOverridesReturnsABlockToPlainProse() {
        var doc = twoParagraphs()
        doc.blocks[0].overrides = [.alignment(.center), .smallCaps]
        let result = applyInput(.clearOverrides(blockID: 0), to: doc)
        #expect(result.blocks[0].overrides.isEmpty)
    }

    @Test func clearOverridesOnUnknownBlockIsANoOp() {
        let doc = twoParagraphs()
        let result = applyInput(.clearOverrides(blockID: 99), to: doc)
        #expect(result == doc)
    }

    // MARK: REJECTS WHEN

    @Test func unknownAnchorIsANoOpLeavingTheDocumentAndCounterUnchanged() {
        let doc = twoParagraphs()
        let result = applyInput(
            .insertBlock(content: .paragraph(runs: [Run(text: "x")]), overrides: [], afterBlockID: 99),
            to: doc
        )
        #expect(result == doc)                                   // unchanged
        #expect(result.nextBlockID == 2)                         // counter not advanced
    }

    // MARK: Persistence

    @Test func aPaletteInsertedBlockSurvivesTheSidecarRoundTrip() throws {
        let doc = twoParagraphs()
        let inserted = applyInput(
            .insertBlock(content: .paragraph(runs: [Run(text: "Here lie the keepers.")]),
                         overrides: [.blockQuote], afterBlockID: 0),
            to: doc
        )
        let (prose, sidecar) = serialize(inserted)
        let restored = try parse(proseText: prose, sidecar: sidecar)
        #expect(restored == inserted)
        #expect(restored.blocks[1].overrides == [.blockQuote])
    }
}
