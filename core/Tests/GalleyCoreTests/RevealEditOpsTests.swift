//
//  RevealEditOpsTests.swift
//  GalleyCoreTests
//
//  Behavioral tests for the two reducer ops the Reveal Codes surface adds (LT5-2,
//  ADR-0034): `deleteBlock` (deleting a [SceneBreak]/[figure] chip) and
//  `clearOverride` (deleting one override chip). Derived from their Behavior
//  Statements — each DOES line is a functional test, each REJECTS WHEN a no-op test;
//  every assertion checks the resulting `Document` state, not a return value.
//

import Testing
import GalleyCore

@Suite("Reveal edit ops (ADR-0034)")
struct RevealEditOpsTests {

    private func doc(_ blocks: [Block]) -> Document {
        Document(blocks: blocks, nextBlockID: (blocks.map(\.id).max() ?? -1) + 1)
    }

    // MARK: deleteBlock

    @Test func deleteBlockRemovesTheNamedBlock() {
        let d = doc([
            Block(id: 0, content: .paragraph(runs: [Run(text: "before")])),
            Block(id: 1, content: .sceneBreak),
            Block(id: 2, content: .paragraph(runs: [Run(text: "after")])),
        ])
        let out = applyInput(.deleteBlock(blockID: 1), to: d)
        #expect(out.blocks.map(\.id) == [0, 2])
        #expect(!out.blocks.contains { $0.content == .sceneBreak })
    }

    @Test func deleteBlockRelocatesAnAnchoredCut() {
        var d = doc([
            Block(id: 0, content: .paragraph(runs: [Run(text: "one")])),
            Block(id: 1, content: .figure(imageRef: "x.png", caption: "")),
            Block(id: 2, content: .paragraph(runs: [Run(text: "two")])),
        ])
        d.placeChapterCut(atBlock: 1)             // a cut anchored to the figure block
        let out = applyInput(.deleteBlock(blockID: 1), to: d)
        #expect(out.blocks.map(\.id) == [0, 2])
        // The cut relocates to the block that took the deleted slot (ADR-0010), never dangles.
        #expect(out.cuts.first?.blockID == 2)
        #expect(out.cuts.allSatisfy { c in out.blocks.contains { $0.id == c.blockID } })
    }

    @Test func deleteBlockIsNoOpForUnknownBlock() {
        let d = doc([
            Block(id: 0, content: .paragraph(runs: [Run(text: "a")])),
            Block(id: 1, content: .sceneBreak),
        ])
        let out = applyInput(.deleteBlock(blockID: 99), to: d)
        #expect(out.blocks.map(\.id) == [0, 1])
    }

    @Test func deleteBlockIsNoOpWhenItIsTheOnlyBlock() {
        // Deleting the last block would leave no caret home — rejected (ADR-0034).
        let d = doc([Block(id: 0, content: .sceneBreak)])
        let out = applyInput(.deleteBlock(blockID: 0), to: d)
        #expect(out.blocks.map(\.id) == [0])
    }

    // MARK: clearOverride

    @Test func clearOverrideRemovesOnlyTheIndexedOverride() {
        let d = doc([
            Block(id: 0, content: .paragraph(runs: [Run(text: "x")]), overrides: [.alignment(.center), .smallCaps, .blockQuote])
        ])
        let out = applyInput(.clearOverride(blockID: 0, index: 1), to: d)   // drop .smallCaps
        #expect(out.blocks[0].overrides == [.alignment(.center), .blockQuote])
    }

    @Test func clearOverrideIsNoOpForOutOfRangeIndex() {
        let d = doc([
            Block(id: 0, content: .paragraph(runs: [Run(text: "x")]), overrides: [.smallCaps])
        ])
        let out = applyInput(.clearOverride(blockID: 0, index: 5), to: d)
        #expect(out.blocks[0].overrides == [.smallCaps])
    }

    @Test func clearOverrideIsNoOpForUnknownBlock() {
        let d = doc([
            Block(id: 0, content: .paragraph(runs: [Run(text: "x")]), overrides: [.smallCaps])
        ])
        let out = applyInput(.clearOverride(blockID: 7, index: 0), to: d)
        #expect(out.blocks[0].overrides == [.smallCaps])
    }
}
