//
//  ChapterNumberingTests.swift
//  GalleyCoreTests
//
//  Behavioral tests for role-aware chapter numbering and the `#a`/`#r` title-macro
//  resolution (ADR-0026, LT3). Numbering counts only `.chapter`-role boundary cuts
//  in document order; prologues/epilogues/dedications are skipped. The stored title
//  keeps the macro; resolution is a render-time transform.
//

import Testing
@testable import GalleyCore

/// Three blocks so cuts can be anchored at distinct positions.
private func threeBlocks() -> Document {
    Document(
        blocks: [
            Block(id: 0, content: .paragraph(runs: [Run(text: "A.")])),
            Block(id: 1, content: .paragraph(runs: [Run(text: "B.")])),
            Block(id: 2, content: .paragraph(runs: [Run(text: "C.")])),
        ],
        nextBlockID: 3
    )
}

@Suite("chapter numbering + title macros")
struct ChapterNumberingTests {

    @Test func arabicMacroResolvesToTheChapterNumber() {
        var doc = threeBlocks()
        doc.cuts = [
            ChapterCut(blockID: 0, title: "Chapter #a", role: .chapter),
            ChapterCut(blockID: 1, title: "Chapter #a", role: .chapter),
        ]
        #expect(doc.resolvedTitle(forCutAt: 0) == "Chapter 1")
        #expect(doc.resolvedTitle(forCutAt: 1) == "Chapter 2")
    }

    @Test func romanMacroResolvesToUppercaseRoman() {
        var doc = threeBlocks()
        doc.cuts = [
            ChapterCut(blockID: 0, title: "Part #r", role: .chapter),
            ChapterCut(blockID: 1, title: "Part #r", role: .chapter),
            ChapterCut(blockID: 2, title: "Part #r", role: .chapter),
        ]
        #expect(doc.resolvedTitle(forCutAt: 0) == "Part I")
        #expect(doc.resolvedTitle(forCutAt: 1) == "Part II")
        #expect(doc.resolvedTitle(forCutAt: 2) == "Part III")
    }

    @Test func prologueIsNotCountedSoChaptersStillNumberFromOne() {
        var doc = threeBlocks()
        doc.cuts = [
            ChapterCut(blockID: 0, title: "Prologue", role: .prologue),
            ChapterCut(blockID: 1, title: "Chapter #a", role: .chapter),
            ChapterCut(blockID: 2, title: "Chapter #a", role: .chapter),
        ]
        #expect(doc.resolvedTitle(forCutAt: 0) == "Prologue")    // no macro, unchanged
        #expect(doc.resolvedTitle(forCutAt: 1) == "Chapter 1")   // first chapter despite the prologue
        #expect(doc.resolvedTitle(forCutAt: 2) == "Chapter 2")
    }

    @Test func insertingAPrologueBeforeChaptersRenumbersForFree() {
        // Only the overlay changes; titles keep their macro, so numbers re-resolve.
        var doc = threeBlocks()
        doc.cuts = [
            ChapterCut(blockID: 1, title: "Chapter #a", role: .chapter),
            ChapterCut(blockID: 2, title: "Chapter #a", role: .chapter),
        ]
        #expect(doc.resolvedTitle(forCutAt: 1) == "Chapter 1")
        doc.cuts.insert(ChapterCut(blockID: 0, title: "Prologue", role: .prologue), at: 0)
        #expect(doc.resolvedTitle(forCutAt: 1) == "Chapter 1")   // prologue does not bump the number
        #expect(doc.resolvedTitle(forCutAt: 2) == "Chapter 2")
    }

    @Test func macroInACustomTitleResolvesInPlace() {
        var doc = threeBlocks()
        doc.cuts = [ChapterCut(blockID: 0, title: "#a. The Arrival", role: .chapter)]
        #expect(doc.resolvedTitle(forCutAt: 0) == "1. The Arrival")
    }

    @Test func defaultTitlesAreTheRoleNameOrTheArabicChapterMacro() {
        #expect(SectionRole.chapter.defaultTitle == "Chapter #a")
        #expect(SectionRole.prologue.defaultTitle == "Prologue")
        #expect(SectionRole.epilogue.defaultTitle == "Epilogue")
        #expect(SectionRole.dedication.defaultTitle == "Dedication")
    }

    @Test func romanNumeralCoversCarryDigits() {
        #expect(romanNumeral(4) == "IV")
        #expect(romanNumeral(9) == "IX")
        #expect(romanNumeral(14) == "XIV")
        #expect(romanNumeral(40) == "XL")
        #expect(romanNumeral(1984) == "MCMLXXXIV")
        #expect(romanNumeral(0) == "")
    }
}
