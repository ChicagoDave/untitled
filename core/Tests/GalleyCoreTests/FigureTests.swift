//
//  FigureTests.swift
//  GalleyCoreTests
//
//  Behavioral tests for the `figure` block (LT4, ADR-0027): the prose-marker
//  serialize/parse round-trip (including empty fields and delimiter escaping) and
//  the reveal/display projections. A figure stores intent only — an image reference
//  + caption; rendering belongs to the typesetter (ADR-0024).
//

import Testing
@testable import GalleyCore

@Suite("figure block: codec + projections")
struct FigureTests {

    /// A document with a figure between two paragraphs.
    private func docWithFigure(ref: String, caption: String) -> Document {
        Document(
            blocks: [
                Block(id: 0, content: .paragraph(runs: [Run(text: "Before.")])),
                Block(id: 1, content: .figure(imageRef: ref, caption: caption)),
                Block(id: 2, content: .paragraph(runs: [Run(text: "After.")])),
            ],
            nextBlockID: 3
        )
    }

    // MARK: Serialize / parse round-trip

    @Test func figureWithRefAndCaptionRoundTrips() throws {
        let doc = docWithFigure(ref: "harbor.jpg", caption: "Dawn over the harbor.")
        let (prose, sidecar) = serialize(doc)
        #expect(prose.contains("[figure: harbor.jpg | Dawn over the harbor.]"))
        let restored = try parse(proseText: prose, sidecar: sidecar)
        #expect(restored == doc)
    }

    @Test func figureWithEmptyCaptionOmitsTheSeparator() throws {
        let doc = docWithFigure(ref: "cover.jpg", caption: "")
        let (prose, sidecar) = serialize(doc)
        #expect(prose.contains("[figure: cover.jpg]"))
        let restored = try parse(proseText: prose, sidecar: sidecar)
        #expect(restored == doc)
    }

    @Test func figureWithEmptyRefIsAValidPlaceholder() throws {
        let doc = docWithFigure(ref: "", caption: "")
        let (prose, sidecar) = serialize(doc)
        let restored = try parse(proseText: prose, sidecar: sidecar)
        #expect(restored == doc)
        if case .figure(let ref, let caption) = restored.blocks[1].content {
            #expect(ref.isEmpty)
            #expect(caption.isEmpty)
        } else {
            Issue.record("expected a figure block")
        }
    }

    @Test func figureFieldsWithDelimiterCharactersRoundTripViaEscaping() throws {
        // A caption containing the marker delimiters (`]`, `|`, `\`) must survive.
        let doc = docWithFigure(ref: "a|b].png", caption: "See fig. [2] | or \\ later")
        let (prose, sidecar) = serialize(doc)
        let restored = try parse(proseText: prose, sidecar: sidecar)
        #expect(restored == doc)
    }

    @Test func aParagraphThatLooksLikeAFigureMarkerStaysAParagraph() throws {
        let doc = Document(
            blocks: [Block(id: 0, content: .paragraph(runs: [Run(text: "[figure: not really]")]))],
            nextBlockID: 1
        )
        let (prose, sidecar) = serialize(doc)
        let restored = try parse(proseText: prose, sidecar: sidecar)
        #expect(restored == doc)                          // escaped on write, parses back as prose
        if case .paragraph = restored.blocks[0].content {} else { Issue.record("expected a paragraph") }
    }

    // MARK: Projections

    @Test func revealEmitsAFigureChipWithTheRef() {
        let doc = docWithFigure(ref: "harbor.jpg", caption: "ignored in reveal")
        let tokens = doc.revealProjection()
        #expect(tokens.contains(.code(label: "figure: harbor.jpg", id: .figure(1))))
    }

    @Test func displayEmitsAFigureTokenWithRefAndCaption() {
        let doc = docWithFigure(ref: "harbor.jpg", caption: "Dawn.")
        let tokens = doc.displayProjection()
        #expect(tokens.contains(.figure(imageRef: "harbor.jpg", caption: "Dawn.")))
    }

    @Test func aFigureLeavesSurroundingParagraphsUnaffected() {
        let doc = docWithFigure(ref: "x.png", caption: "c")
        let display = doc.displayProjection()
        #expect(display.first == .paragraph(spans: [DisplaySpan(text: "Before.")], overrides: []))
        #expect(display.last == .paragraph(spans: [DisplaySpan(text: "After.")], overrides: []))
    }

    @Test func aCutAnchoredToAFigureSurfacesBeforeItsChip() {
        var doc = docWithFigure(ref: "x.png", caption: "")
        doc.cuts = [ChapterCut(blockID: 1, role: .chapter)]
        let tokens = doc.revealProjection()
        // The chapter chip precedes the figure chip at the figure's position.
        let chapterAt = tokens.firstIndex(of: .code(label: "Chapter", id: .chapter(1, nil)))
        let figureAt = tokens.firstIndex(of: .code(label: "figure: x.png", id: .figure(1)))
        #expect(chapterAt != nil && figureAt != nil && chapterAt! < figureAt!)
    }

    // MARK: setFigureCaption reducer (LT4-2, ADR-0028 Option A)

    @Test func setFigureCaptionReplacesTheCaptionAndKeepsTheRef() {
        let doc = docWithFigure(ref: "harbor.jpg", caption: "old caption")
        let result = applyInput(.setFigureCaption(blockID: 1, caption: "Dawn over the harbor."), to: doc)
        #expect(result.blocks[1].content == .figure(imageRef: "harbor.jpg", caption: "Dawn over the harbor."))
        // Surrounding blocks are untouched.
        #expect(result.blocks[0] == doc.blocks[0])
        #expect(result.blocks[2] == doc.blocks[2])
    }

    @Test func setFigureCaptionAcceptsAnEmptyCaption() {
        let doc = docWithFigure(ref: "harbor.jpg", caption: "had one")
        let result = applyInput(.setFigureCaption(blockID: 1, caption: ""), to: doc)
        #expect(result.blocks[1].content == .figure(imageRef: "harbor.jpg", caption: ""))
    }

    @Test func setFigureCaptionOnAnUnknownBlockIsANoOp() {
        let doc = docWithFigure(ref: "harbor.jpg", caption: "keep me")
        let result = applyInput(.setFigureCaption(blockID: 99, caption: "ignored"), to: doc)
        #expect(result == doc)
    }

    @Test func setFigureCaptionOnANonFigureBlockIsANoOp() {
        let doc = docWithFigure(ref: "harbor.jpg", caption: "keep me")
        // Block 0 is a paragraph, not a figure.
        let result = applyInput(.setFigureCaption(blockID: 0, caption: "ignored"), to: doc)
        #expect(result == doc)
    }
}
