//
//  SectionInsertTests.swift
//  GalleyCoreTests
//
//  Behavioral tests for the `insertSection` reducer arm (LT2), derived from its
//  Behavior Statement. Each asserts on the resulting block stream and cut overlay
//  — the seeded paragraph's position and emptiness, the roled cut anchored to that
//  seeded block, the freshly minted identity — or on the no-op for a stale anchor,
//  never on return shape alone.
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

@Suite("insertSection reducer arm")
struct SectionInsertTests {

    // MARK: DOES

    @Test func seedsAFreshEmptyParagraphAfterTheAnchorWithARoledCutAnchoredToIt() {
        let doc = twoParagraphs()
        let result = applyInput(.insertSection(role: .prologue, afterBlockID: 0), to: doc)

        #expect(result.blocks.count == 3)
        #expect(result.blocks.map(\.id) == [0, 2, 1])            // seeded block (id 2) sits between
        #expect(result.blocks[1].content == .paragraph(runs: [])) // fresh, empty, ready to type
        // cut anchors the seeded block, carrying the role's non-empty default title
        #expect(result.cuts == [ChapterCut(blockID: 2, title: "Prologue", role: .prologue)])
    }

    @Test func seedsAChapterWithTheArabicNumberingMacroSoItAutoNumbers() {
        let doc = twoParagraphs()
        let result = applyInput(.insertSection(role: .chapter, afterBlockID: 0), to: doc)
        #expect(result.cuts.first?.title == "Chapter #a")        // macro stored, not a digit
    }

    @Test func anchorsTheCutToTheSeededBlockNotThePriorBlock() {
        let doc = twoParagraphs()
        let result = applyInput(.insertSection(role: .chapter, afterBlockID: 0), to: doc)

        // The cut must label the NEW section's prose, not the anchor's prose.
        #expect(result.cuts.first?.blockID == result.blocks[1].id)
        #expect(result.cuts.first?.blockID != 0)
    }

    @Test func advancesNextBlockIDSoTheSeededIDNeverCollides() {
        let doc = twoParagraphs()
        let result = applyInput(.insertSection(role: .epilogue, afterBlockID: 1), to: doc)

        #expect(result.nextBlockID == 3)
        #expect(result.blocks.map(\.id) == [0, 1, 2])            // appended after the last block
        #expect(result.cuts == [ChapterCut(blockID: 2, title: "Epilogue", role: .epilogue)])
    }

    @Test func aDedicationInsertProducesACutWithTheDedicationRole() {
        let doc = twoParagraphs()
        let result = applyInput(.insertSection(role: .dedication, afterBlockID: 0), to: doc)

        #expect(result.cuts.first?.role == .dedication)
    }

    @Test func leavesExistingCutsUntouched() {
        var doc = twoParagraphs()
        doc.cuts = [ChapterCut(blockID: 1, title: "Two")]
        let result = applyInput(.insertSection(role: .prologue, afterBlockID: 0), to: doc)

        #expect(result.cuts.contains(ChapterCut(blockID: 1, title: "Two")))   // pre-existing cut intact
        #expect(result.cuts.count == 2)
    }

    // MARK: REJECTS WHEN

    @Test func unknownAnchorIsANoOpLeavingDocumentAndCounterUnchanged() {
        let doc = twoParagraphs()
        let result = applyInput(.insertSection(role: .prologue, afterBlockID: 99), to: doc)

        #expect(result == doc)                                    // no block, no cut
        #expect(result.nextBlockID == 2)                          // counter not advanced
    }
}
