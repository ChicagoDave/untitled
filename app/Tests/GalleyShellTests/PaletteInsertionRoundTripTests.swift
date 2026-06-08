//
//  PaletteInsertionRoundTripTests.swift
//  GalleyShellTests
//
//  An end-to-end backstop for the Block Palette smoke check (BP2): it reproduces
//  exactly what `InputController.acceptPaletteSelection` does to the model — load
//  the real shipped "Epigraph" template, build the same `(content, overrides)` the
//  palette builds, apply the production `insertBlock` reducer op, then persist and
//  reload through the real `DocumentBundle` — and asserts the inserted block and its
//  overrides survive on disk. Everything but the AppKit keystroke/popover layer runs
//  here against real files; that GUI layer is the human eyes-on step.
//

import Foundation
import Testing
@testable import GalleyShell
import GalleyCore

@Suite("Block Palette insertion — end-to-end round trip")
struct PaletteInsertionRoundTripTests {

    /// Resolves the shipped `examples/GrayHarbor.galley` bundle relative to this file.
    private func grayHarbor() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GalleyShellTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // app
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("examples/GrayHarbor.galley", isDirectory: true)
    }

    @Test func insertingTheRealEpigraphTemplateSurvivesSaveAndReopen() throws {
        let bundle = grayHarbor()

        // 1. Open the real project (prose-only import; mints block IDs).
        let opened = try DocumentBundle.read(from: bundle)
        let anchorID = try #require(opened.blocks.first?.id)

        // 2. Load the real template and build the block the palette would build
        //    (single paragraph seeded from the body; overrides carried verbatim —
        //    mirrors InputController.blockContent(for: .template)).
        let templates = TemplateIndex.load(directory: bundle.appendingPathComponent("templates", isDirectory: true))
        let epigraph = try #require(templates.template(named: "Epigraph"))
        let body = epigraph.body.replacingOccurrences(of: "\n", with: " ")
        let content = BlockContent.paragraph(runs: [Run(text: body)])

        // 3. Apply the production reducer op — the exact event the palette dispatches.
        let edited = applyInput(
            .insertBlock(content: content, overrides: epigraph.overrides, afterBlockID: anchorID),
            to: opened
        )
        #expect(edited.blocks.count == opened.blocks.count + 1)

        // 4. Persist and reopen through the real bundle I/O (a temp copy — never the
        //    shipped example).
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".galley", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try DocumentBundle.write(edited, to: temp)
        let reloaded = try DocumentBundle.read(from: temp)

        // 5. The inserted block and its centered, small-caps presentation survive.
        #expect(reloaded == edited)
        let inserted = reloaded.blocks[1]
        #expect(inserted.overrides == [.alignment(.center), .smallCaps])
        if case .paragraph(let runs) = inserted.content {
            #expect(runs.map(\.text).joined() == body)
        } else {
            Issue.record("expected the inserted block to be a paragraph")
        }
    }

    @Test func insertingTheFigurePaletteRowSurvivesSaveAndReopen() throws {
        let bundle = grayHarbor()

        // 1. Open the real project (prose-only import; mints block IDs).
        let opened = try DocumentBundle.read(from: bundle)
        let anchorID = try #require(opened.blocks.first?.id)

        // 2. Apply the exact event the palette's Figure row dispatches (empty ref +
        //    caption — the writer fills them in), mirroring InputController.event(for:).
        let edited = applyInput(
            .insertBlock(content: .figure(imageRef: "", caption: ""), overrides: [], afterBlockID: anchorID),
            to: opened
        )
        #expect(edited.blocks.count == opened.blocks.count + 1)

        // 3. Persist and reopen through the real bundle I/O (a temp copy).
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".galley", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try DocumentBundle.write(edited, to: temp)
        let reloaded = try DocumentBundle.read(from: temp)

        // 4. The inserted figure (empty placeholder) survives the round-trip.
        #expect(reloaded == edited)
        #expect(reloaded.blocks[1].content == .figure(imageRef: "", caption: ""))
    }
}
