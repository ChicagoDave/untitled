//
//  UntitledCoreTests.swift
//  UntitledCoreTests
//
//  Purpose: Phase-2 compile/assembly test — confirms every §4 domain type is
//  visible from the test target and assembles into a Document, and asserts on
//  the one stateful operation (mintBlockID). Behavioral suites for block
//  lifecycle and round-trip arrive in Phases 3-4.
//  Owner context: UntitledCoreTests.
//

import Testing
@testable import UntitledCore

@Test("§4 domain types assemble into a Document")
func domainTypesAssemble() {
    var doc = Document(meta: Metadata(title: "Untitled", author: "D"))

    // Every block kind is constructible.
    let pID = doc.mintBlockID()
    doc.blocks.append(Block(
        id: pID,
        content: .paragraph(runs: [Run(text: "Half a league, "), Run(text: "onward", italic: true)]),
        overrides: [.alignment(.center)]
    ))
    let sbID = doc.mintBlockID()
    doc.blocks.append(Block(id: sbID, content: .sceneBreak))
    let vID = doc.mintBlockID()
    doc.blocks.append(Block(id: vID, content: .setPiece(kind: .verse, lines: [[Run(text: "a line")]])))

    // A mid-block chapter cut anchored by BlockID, not index (ADR-0010).
    doc.cuts.append(ChapterCut(blockID: pID, offsetInBlock: 5, title: "One", opener: TemplateRef(id: "epigraph")))

    #expect(doc.blocks.count == 3)
    #expect(doc.cuts.first?.blockID == pID)
    #expect(doc.bible.entries.isEmpty)
    #expect(doc.meta.title == "Untitled")
}

// DOES: returns current nextBlockID and advances it by 1.
// REJECTS WHEN: never (total function).
@Test("mintBlockID returns the current id and advances the counter")
func mintBlockIDAdvancesCounter() {
    var doc = Document()                 // nextBlockID starts at 0
    #expect(doc.nextBlockID == 0)

    let first = doc.mintBlockID()
    #expect(first == 0)                  // returned the pre-increment value
    #expect(doc.nextBlockID == 1)        // ...and advanced the counter (mutation)

    let second = doc.mintBlockID()
    #expect(second == 1)
    #expect(second != first)             // never reused (ADR-0010)
    #expect(doc.nextBlockID == 2)
}
