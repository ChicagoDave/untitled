//
//  StorageTests.swift
//  GalleyCoreTests
//
//  Behavioral tests for the on-disk round-trip (Phase 4, ADR-0007): `serialize`
//  and `parse`. Each test asserts on the reconstructed `Document` state — the
//  lossless invariant `parse(serialize(doc)) == doc` — or on the specific
//  `ParseError` thrown, never on return shape alone.
//

import Testing
@testable import GalleyCore

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

@Test("round-trip: all submission metadata fields survive serialize → parse")
func roundTripSubmissionMetadata() throws {
    let meta = Metadata(
        title: "The Fourth Morning",
        author: "M. Rowan",
        legalName: "Margaret Rowan",
        email: "m@example.com",
        phone: "+1 555 0100",
        address: "12 Harbor Rd\nPortland, ME",
        wordCount: "approx. 82,000",
        genre: "Literary fiction",
        logline: "A flooded town, a fourth morning.",
        bio: "M. Rowan's stories have appeared in…",
        agent: "The Vance Agency"
    )
    let original = Document(
        blocks: [Block(id: 0, content: .paragraph(runs: [Run(text: "Body.")]))],
        meta: meta,
        nextBlockID: 1
    )
    let (prose, sidecar) = serialize(original)
    let restored = try parse(proseText: prose, sidecar: sidecar)
    #expect(restored.meta == meta)
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

// MARK: - PresentationOverride wire codec (ADR-0009 amendment, BP1)

@Test("the override wire codec round-trips every case, including blockQuote")
func overrideTokenCodecIsExactInverse() {
    let all: [PresentationOverride] = [
        .alignment(.leading), .alignment(.center), .alignment(.trailing),
        .smallCaps, .blockQuote,
    ]
    for override in all {
        #expect(PresentationOverride(token: override.token) == override)
    }
    #expect(PresentationOverride(token: "blockQuote") == .blockQuote)
    #expect(PresentationOverride(token: "blink") == nil)   // unknown token → nil, never a guess
}

@Test("round-trip: a blockQuote override on a block survives serialize → parse")
func roundTripBlockQuoteOverride() throws {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(
        id: id,
        content: .paragraph(runs: [Run(text: "Here lie the keepers of the light.")]),
        overrides: [.blockQuote]
    )]
    let (prose, sidecar) = serialize(doc)
    #expect(sidecar.contains("blockQuote"))
    let restored = try parse(proseText: prose, sidecar: sidecar)
    #expect(restored == doc)
    #expect(restored.blocks[0].overrides == [.blockQuote])
}

// MARK: - Empty paragraphs round-trip (LT3 fix)

@Test("round-trip: an empty paragraph (e.g. a fresh section body) survives serialize → parse")
func roundTripEmptyParagraph() throws {
    var doc = Document()
    let heading = doc.mintBlockID()
    let body = doc.mintBlockID()
    doc.blocks = [
        Block(id: heading, content: .paragraph(runs: [Run(text: "Chapter one.")])),
        Block(id: body, content: .paragraph(runs: [])),          // empty section body
    ]
    doc.cuts = [ChapterCut(blockID: body, title: "Chapter #a", role: .chapter)]
    let (prose, sidecar) = serialize(doc)
    let restored = try parse(proseText: prose, sidecar: sidecar)
    #expect(restored == doc)
    #expect(restored.blocks.count == 2)                          // the empty body is preserved
    #expect(restored.cuts.first?.blockID == body)               // its cut still anchors
}

@Test("round-trip: a document of several empty paragraphs keeps them all")
func roundTripManyEmptyParagraphs() throws {
    var doc = Document()
    let ids = (0..<4).map { _ in doc.mintBlockID() }
    doc.blocks = ids.enumerated().map { index, id in
        Block(id: id, content: index == 1 ? .paragraph(runs: [Run(text: "Only this one.")]) : .paragraph(runs: []))
    }
    let (prose, sidecar) = serialize(doc)
    let restored = try parse(proseText: prose, sidecar: sidecar)
    #expect(restored == doc)
    #expect(restored.blocks.map(\.id) == ids)
}

@Test("parse recovers a legacy bundle whose blank blocks were lost (sidecar > prose)")
func parseRecoversLegacyMismatch() throws {
    // A pre-fix sidecar: 3 blocks, no `empty` flags; prose only carries 1 (the other
    // two were empty paragraphs the old serializer dropped). Parse pads the rest.
    let sidecar = """
    {"author":"","bible":[],"blocks":[{"id":0,"overrides":[]},{"id":1,"overrides":[]},{"id":2,"overrides":[]}],\
    "cuts":[{"blockID":2,"offset":null,"opener":null,"title":"Chapter #a"}],\
    "nextBlockID":3,"title":""}
    """
    let restored = try parse(proseText: "The only surviving line.", sidecar: sidecar)
    #expect(restored.blocks.count == 3)                          // opens instead of throwing
    #expect(restored.blocks.map(\.id) == [0, 1, 2])             // ids intact → the cut resolves
    #expect(restored.cuts.first?.blockID == 2)
}

// MARK: - SectionRole sidecar codec (ADR-0026, LT2)

@Test("round-trip: a roled cut (prologue) survives serialize → parse")
func roundTripRoledCut() throws {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .paragraph(runs: [Run(text: "Before it all began.")]))]
    doc.cuts = [ChapterCut(blockID: id, role: .prologue)]
    let (prose, sidecar) = serialize(doc)
    #expect(sidecar.contains("prologue"))
    let restored = try parse(proseText: prose, sidecar: sidecar)
    #expect(restored == doc)
    #expect(restored.cuts.first?.role == .prologue)
}

@Test("serialize omits the default chapter role so legacy sidecars stay byte-identical")
func serializeOmitsDefaultChapterRole() {
    var doc = Document()
    let id = doc.mintBlockID()
    doc.blocks = [Block(id: id, content: .paragraph(runs: [Run(text: "Chapter one.")]))]
    doc.cuts = [ChapterCut(blockID: id)]                     // default .chapter role
    let (_, sidecar) = serialize(doc)
    #expect(!sidecar.contains("\"role\""))                   // no role key written for a plain chapter
}

@Test("a legacy roleless sidecar cut decodes to .chapter")
func legacyRolelessCutDecodesToChapter() throws {
    let sidecar = """
    {"author":"","bible":[],"blocks":[{"id":0,"overrides":[]}],\
    "cuts":[{"blockID":0,"offset":null,"opener":null,"title":null}],\
    "nextBlockID":1,"title":""}
    """
    let restored = try parse(proseText: "Chapter one.", sidecar: sidecar)
    #expect(restored.cuts.first?.role == .chapter)
}

@Test("parse rejects an unknown section-role token")
func parseRejectsUnknownSectionRole() {
    let sidecar = """
    {"author":"","bible":[],"blocks":[{"id":0,"overrides":[]}],\
    "cuts":[{"blockID":0,"offset":null,"opener":null,"title":null,"role":"interlude"}],\
    "nextBlockID":1,"title":""}
    """
    #expect(throws: ParseError.unknownSectionRole("interlude")) {
        _ = try parse(proseText: "para", sidecar: sidecar)
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
