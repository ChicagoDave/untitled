//
//  RevealTests.swift
//  UntitledCoreTests
//
//  Behavioral tests for `revealProjection` (Phase 4, §5/ADR-0006). Each test
//  asserts on the exact `[RevealToken]` sequence the reveal pane would render —
//  the projected state — for a given document.
//

import Testing
@testable import UntitledCore

@Test("reveal: an explicit italic run brackets its text with [i]/[/i] chips")
func revealParagraphItalic() {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .paragraph(runs: [
        Run(text: "Call me "), Run(text: "Ishmael", italic: true), Run(text: "."),
    ]))]
    #expect(doc.revealProjection() == [
        .text("Call me "),
        .code(label: "i", id: .italicOpen(id, 0)),
        .text("Ishmael"),
        .code(label: "/i", id: .italicClose(id, 0)),
        .text("."),
    ])
}

@Test("reveal: a plain paragraph projects to a single literal text token")
func revealPlainParagraph() {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .paragraph(runs: [Run(text: "No marks here.")]))]
    #expect(doc.revealProjection() == [.text("No marks here.")])
}

@Test("reveal: two italic spans in a block get distinct span indices")
func revealMultipleItalicSpans() {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .paragraph(runs: [
        Run(text: "a", italic: true), Run(text: " b "), Run(text: "c", italic: true),
    ]))]
    #expect(doc.revealProjection() == [
        .code(label: "i", id: .italicOpen(id, 0)),
        .text("a"),
        .code(label: "/i", id: .italicClose(id, 0)),
        .text(" b "),
        .code(label: "i", id: .italicOpen(id, 1)),
        .text("c"),
        .code(label: "/i", id: .italicClose(id, 1)),
    ])
}

@Test("reveal: a chapter cut inside an italic span splits the run cleanly")
func revealChapterCutInsideItalic() {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .paragraph(runs: [
        Run(text: "abc"), Run(text: "def", italic: true), Run(text: "ghi"),
    ]))]
    doc.cuts = [ChapterCut(blockID: id, offsetInBlock: 4)]   // inside "def"
    #expect(doc.revealProjection() == [
        .text("abc"),
        .code(label: "i", id: .italicOpen(id, 0)),
        .text("d"),
        .code(label: "Chapter", id: .chapter(id, 4)),
        .text("ef"),
        .code(label: "/i", id: .italicClose(id, 0)),
        .text("ghi"),
    ])
}

@Test("reveal: a set-piece's derived italic produces no [i] chips, but an explicit run does")
func revealSetPieceExplicitItalic() {
    var doc = Document()
    let plain = doc.mintBlockID()
    let marked = doc.mintBlockID()
    doc.blocks = [
        // Derived-italic verse line: no run marks → no [i] chips.
        Block(id: plain, content: .setPiece(kind: .verse, lines: [[Run(text: "derived")]])),
        // An explicit italic run inside a set-piece line → [i]/[/i].
        Block(id: marked, content: .setPiece(kind: .letter, lines: [
            [Run(text: "Dear "), Run(text: "Reader", italic: true)],
        ])),
    ]
    let tokens = doc.revealProjection()
    #expect(tokens == [
        .code(label: "Verse", id: .setPieceOpen(plain)),
        .text("derived"),
        .code(label: "line", id: .line(plain, 0)),
        .code(label: "/Verse", id: .setPieceClose(plain)),
        .code(label: "Letter", id: .setPieceOpen(marked)),
        .text("Dear "),
        .code(label: "i", id: .italicOpen(marked, 0)),
        .text("Reader"),
        .code(label: "/i", id: .italicClose(marked, 0)),
        .code(label: "line", id: .line(marked, 0)),
        .code(label: "/Letter", id: .setPieceClose(marked)),
    ])
}

@Test("reveal: a scene break projects to a single [SceneBreak] code")
func revealSceneBreak() {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .sceneBreak)]
    #expect(doc.revealProjection() == [.code(label: "SceneBreak", id: .sceneBreak(id))])
}

@Test("reveal: a verse set-piece brackets its lines with [Verse]/[line]/[/Verse]")
func revealVerse() {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .setPiece(kind: .verse, lines: [
        [Run(text: "Half a league, half a league,")],
        [Run(text: "Half a league onward,")],
    ]))]
    #expect(doc.revealProjection() == [
        .code(label: "Verse", id: .setPieceOpen(id)),
        .text("Half a league, half a league,"),
        .code(label: "line", id: .line(id, 0)),
        .text("Half a league onward,"),
        .code(label: "line", id: .line(id, 1)),
        .code(label: "/Verse", id: .setPieceClose(id)),
    ])
}

@Test("reveal: epigraph and letter set-pieces carry their own labels")
func revealSetPieceLabels() {
    var doc = Document()
    let e = doc.mintBlockID()
    let l = doc.mintBlockID()
    doc.blocks = [
        Block(id: e, content: .setPiece(kind: .epigraph, lines: [[Run(text: "x")]])),
        Block(id: l, content: .setPiece(kind: .letter, lines: [[Run(text: "y")]])),
    ]
    let tokens = doc.revealProjection()
    #expect(tokens.first == .code(label: "Epigraph", id: .setPieceOpen(e)))
    #expect(tokens.contains(.code(label: "/Epigraph", id: .setPieceClose(e))))
    #expect(tokens.contains(.code(label: "Letter", id: .setPieceOpen(l))))
    #expect(tokens.contains(.code(label: "/Letter", id: .setPieceClose(l))))
}

@Test("reveal: a blank set-piece line emits its [line] code but no text token")
func revealBlankVerseLine() {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .setPiece(kind: .verse, lines: [[], [Run(text: "after")]]))]
    #expect(doc.revealProjection() == [
        .code(label: "Verse", id: .setPieceOpen(id)),
        .code(label: "line", id: .line(id, 0)),
        .text("after"),
        .code(label: "line", id: .line(id, 1)),
        .code(label: "/Verse", id: .setPieceClose(id)),
    ])
}

@Test("reveal: a block-boundary chapter cut emits [Chapter] before the block")
func revealBoundaryChapterCut() {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .paragraph(runs: [Run(text: "Chapter two opens.")]))]
    doc.cuts = [ChapterCut(blockID: id, offsetInBlock: nil)]
    #expect(doc.revealProjection() == [
        .code(label: "Chapter", id: .chapter(id, nil)),
        .text("Chapter two opens."),
    ])
}

@Test("reveal: a mid-paragraph chapter cut splits the text around the [Chapter] code")
func revealMidParagraphChapterCut() {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .paragraph(runs: [Run(text: "abcdef")]))]
    doc.cuts = [ChapterCut(blockID: id, offsetInBlock: 3)]
    #expect(doc.revealProjection() == [
        .text("abc"),
        .code(label: "Chapter", id: .chapter(id, 3)),
        .text("def"),
    ])
}

@Test("reveal: a chapter cut anchored to a set-piece surfaces before the block")
func revealChapterCutOnSetPiece() {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .setPiece(kind: .verse, lines: [[Run(text: "v")]]))]
    doc.cuts = [ChapterCut(blockID: id, offsetInBlock: nil, title: "Two")]
    let tokens = doc.revealProjection()
    #expect(tokens.first == .code(label: "Chapter", id: .chapter(id, nil)))
    #expect(tokens[1] == .code(label: "Verse", id: .setPieceOpen(id)))
}

@Test("reveal: an empty document projects to no tokens")
func revealEmptyDocument() {
    #expect(Document().revealProjection() == [])
}
