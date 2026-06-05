//
//  StorageTests.swift
//  UntitledCoreTests
//
//  Behavioral tests for the on-disk round-trip (Phase 4, ADR-0007): `serialize`
//  and `parse`. Each test asserts on the reconstructed `Document` state — the
//  lossless invariant `parse(serialize(doc)) == doc` — or on the specific
//  `ParseError` thrown, never on return shape alone.
//

import Testing
@testable import UntitledCore

/// Builds a small canonical document exercising every block kind, inline italic,
/// overrides, cuts, bible, and metadata — the round-trip workhorse.
private func sampleDocument() -> Document {
    var doc = Document()
    let p0 = doc.mintBlockID()
    let sb = doc.mintBlockID()
    let verse = doc.mintBlockID()
    let p1 = doc.mintBlockID()

    doc.blocks = [
        Block(id: p0, content: .paragraph(runs: [
            Run(text: "Call me "),
            Run(text: "Ishmael", italic: true),
            Run(text: "."),
        ])),
        Block(id: sb, content: .sceneBreak),
        Block(id: verse, content: .setPiece(kind: .verse, lines: [
            [Run(text: "Half a league, half a league,")],
            [Run(text: "Half a league "), Run(text: "onward", italic: true)],
        ]), overrides: [.alignment(.center), .smallCaps]),
        Block(id: p1, content: .paragraph(runs: [Run(text: "The end.")])),
    ]
    doc.cuts = [
        ChapterCut(blockID: verse, offsetInBlock: nil, title: "Two", opener: TemplateRef(id: "epigraph-dateline")),
        ChapterCut(blockID: p1, offsetInBlock: 3, title: "Three"),
    ]
    doc.bible = Bible(entries: [
        BibleEntry(name: "Ishmael", canonicalText: "Ishmael", notes: "the narrator\nof the tale"),
    ])
    doc.meta = Metadata(title: "Moby-Dick", author: "Herman Melville")
    return doc
}

// MARK: - Lossless round-trip (serialize → parse)

@Test("round-trip: a full document with every block kind survives serialize → parse")
func roundTripFullDocument() throws {
    let original = sampleDocument()
    let (prose, sidecar) = serialize(original)
    let restored = try parse(proseText: prose, sidecar: sidecar)
    #expect(restored == original)
}

@Test("round-trip: an empty document survives serialize → parse")
func roundTripEmptyDocument() throws {
    let original = Document()
    let (prose, sidecar) = serialize(original)
    let restored = try parse(proseText: prose, sidecar: sidecar)
    #expect(restored == original)
}

@Test("round-trip preserves the exact nextBlockID counter, not just live ids")
func roundTripPreservesNextBlockID() throws {
    var doc = Document()
    _ = doc.mintBlockID()                 // burn ids so nextBlockID outpaces live blocks
    _ = doc.mintBlockID()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .paragraph(runs: [Run(text: "lone")]))]

    let (prose, sidecar) = serialize(doc)
    let restored = try parse(proseText: prose, sidecar: sidecar)
    #expect(restored.nextBlockID == 3)
    #expect(restored == doc)
}

@Test("serialize emits italic as _…_, scene break as ***, and a fenced set-piece")
func serializeProseShape() {
    let doc = sampleDocument()
    let (prose, _) = serialize(doc)
    #expect(prose.contains("Call me _Ishmael_."))
    #expect(prose.contains("***"))
    #expect(prose.contains(":::verse"))
    #expect(prose.contains("Half a league _onward_"))
    #expect(prose.contains("\n:::"))
}

@Test("serialize keeps block content out of the sidecar but stores ids and cuts")
func serializeSidecarShape() {
    let doc = sampleDocument()
    let (_, sidecar) = serialize(doc)
    #expect(sidecar.contains("\"nextBlockID\""))
    #expect(sidecar.contains("Moby-Dick"))
    #expect(sidecar.contains("epigraph-dateline"))
    #expect(!sidecar.contains("Ishmael, half"))   // prose text must not leak into the sidecar
}

@Test("round-trip preserves a literal underscore in prose via escaping")
func roundTripEscapesUnderscore() throws {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .paragraph(runs: [Run(text: "snake_case_name")]))]
    let (prose, sidecar) = serialize(doc)
    let restored = try parse(proseText: prose, sidecar: sidecar)
    #expect(restored == doc)
    if case .paragraph(let runs) = restored.blocks[0].content {
        #expect(runs == [Run(text: "snake_case_name")])
    } else {
        Issue.record("expected a paragraph")
    }
}

@Test("round-trip preserves a paragraph that reads like a scene break")
func roundTripEscapesMarkerCollision() throws {
    var doc = Document()
    let a = doc.mintBlockID()
    let b = doc.mintBlockID()
    doc.blocks = [
        Block(id: a, content: .paragraph(runs: [Run(text: "***")])),
        Block(id: b, content: .paragraph(runs: [Run(text: ":::not a fence")])),
    ]
    let (prose, sidecar) = serialize(doc)
    let restored = try parse(proseText: prose, sidecar: sidecar)
    #expect(restored == doc)            // both stay paragraphs, not a scene break / fence
}

@Test("round-trip preserves blank lines inside a set-piece")
func roundTripPreservesBlankVerseLine() throws {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .setPiece(kind: .epigraph, lines: [
        [Run(text: "first")],
        [],                              // a deliberately blank line within the fence
        [Run(text: "third")],
    ]))]
    let (prose, sidecar) = serialize(doc)
    let restored = try parse(proseText: prose, sidecar: sidecar)
    #expect(restored == doc)
}

// MARK: - Parse without a sidecar (fresh import)

@Test("parse with no sidecar mints ids 0..<n and sets nextBlockID to n")
func parseNoSidecarMintsIDs() throws {
    let prose = "First paragraph.\n\n***\n\nSecond paragraph."
    let doc = try parse(proseText: prose, sidecar: nil)
    #expect(doc.blocks.map(\.id) == [0, 1, 2])
    #expect(doc.nextBlockID == 3)
    #expect(doc.cuts.isEmpty)
    if case .sceneBreak = doc.blocks[1].content {} else { Issue.record("expected a scene break") }
}

@Test("parse normalizes a # scene break into a sceneBreak block")
func parseHashSceneBreak() throws {
    let doc = try parse(proseText: "A\n\n#\n\nB", sidecar: nil)
    if case .sceneBreak = doc.blocks[1].content {} else { Issue.record("expected a scene break") }
}

// MARK: - REJECTS WHEN

@Test("parse rejects an unterminated set-piece fence, leaving no document")
func parseRejectsUnterminatedFence() {
    #expect(throws: ParseError.unterminatedSetPiece) {
        _ = try parse(proseText: ":::verse\nlonely line", sidecar: nil)
    }
}

@Test("parse rejects an unknown set-piece kind")
func parseRejectsUnknownKind() {
    #expect(throws: ParseError.unknownSetPieceKind("sonnet")) {
        _ = try parse(proseText: ":::sonnet\nline\n:::", sidecar: nil)
    }
}

@Test("parse rejects a prose/sidecar block-count mismatch")
func parseRejectsBlockCountMismatch() {
    let onePara = sidecarJSON(blocks: [(0, [])], nextBlockID: 1)
    #expect(throws: ParseError.blockCountMismatch(prose: 2, sidecar: 1)) {
        _ = try parse(proseText: "one\n\ntwo", sidecar: onePara)
    }
}

@Test("parse rejects a cut anchored to an unknown block id")
func parseRejectsUnknownCutAnchor() {
    let sidecar = """
    {"author":"","bible":[],"blocks":[{"id":0,"overrides":[]}],\
    "cuts":[{"blockID":99,"offset":null,"opener":null,"title":null}],\
    "nextBlockID":1,"title":""}
    """
    #expect(throws: ParseError.unknownBlockID(99)) {
        _ = try parse(proseText: "only", sidecar: sidecar)
    }
}

@Test("parse rejects an unknown presentation-override token")
func parseRejectsUnknownOverride() {
    let sidecar = """
    {"author":"","bible":[],"blocks":[{"id":0,"overrides":["blink"]}],\
    "cuts":[],"nextBlockID":1,"title":""}
    """
    #expect(throws: ParseError.unknownOverrideToken("blink")) {
        _ = try parse(proseText: "para", sidecar: sidecar)
    }
}

@Test("parse rejects malformed sidecar JSON")
func parseRejectsMalformedSidecar() {
    #expect(throws: ParseError.self) {
        _ = try parse(proseText: "para", sidecar: "{not json")
    }
}

/// Builds a minimal valid sidecar JSON for the given blocks and counter.
private func sidecarJSON(blocks: [(Int, [String])], nextBlockID: Int) -> String {
    let blockEntries = blocks.map { id, overrides in
        let tokens = overrides.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"id\":\(id),\"overrides\":[\(tokens)]}"
    }.joined(separator: ",")
    return """
    {"author":"","bible":[],"blocks":[\(blockEntries)],\
    "cuts":[],"nextBlockID":\(nextBlockID),"title":""}
    """
}
