//
//  FigureImageTests.swift
//  GalleyShellTests
//
//  Real-path behavioral tests for the figure `images/` wiring on `WorkspaceDocument`
//  (LT4-2, ADR-0027/ADR-0024). The validation and directory-creation paths run
//  against a real temporary `.galley` bundle on disk — no stub stands in for the
//  filesystem (Integration Reality, rule 13a). A figure records intent only; a
//  missing image is a non-blocking warning, never a load failure.
//

import Foundation
import Testing
import GalleyCore
@testable import GalleyShell

@MainActor
@Suite("figure images: validation + directory wiring")
struct FigureImageTests {

    /// A fresh, unique bundle URL under the temp directory (not yet created).
    private func makeTempBundleURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("galley-fig-\(UUID().uuidString).galley")
    }

    /// A document with one figure between two paragraphs.
    private func docWithFigure(ref: String, caption: String = "") -> Document {
        Document(
            blocks: [
                Block(id: 0, content: .paragraph(runs: [Run(text: "Before.")])),
                Block(id: 1, content: .figure(imageRef: ref, caption: caption)),
                Block(id: 2, content: .paragraph(runs: [Run(text: "After.")])),
            ],
            nextBlockID: 3
        )
    }

    /// Creates `images/<name>` inside a bundle with placeholder bytes.
    private func placeImage(_ name: String, in bundle: URL) throws {
        let images = bundle.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data([0xFF, 0xD8]).write(to: images.appendingPathComponent(name))
    }

    // MARK: Validation on load

    @Test func loadingAFigureWhoseImageExistsReportsNoMissingRefs() throws {
        let url = makeTempBundleURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try DocumentBundle.write(docWithFigure(ref: "harbor.jpg"), to: url)
        try placeImage("harbor.jpg", in: url)

        let buffer = WorkspaceDocument()
        try buffer.load(from: url)

        #expect(buffer.missingImageRefs.isEmpty)
    }

    @Test func loadingAFigureWhoseImageIsAbsentReportsTheMissingRef() throws {
        let url = makeTempBundleURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try DocumentBundle.write(docWithFigure(ref: "harbor.jpg"), to: url)
        // No images/ directory, no file.

        let buffer = WorkspaceDocument()
        try buffer.load(from: url)

        #expect(buffer.missingImageRefs == ["harbor.jpg"])
    }

    @Test func anEmptyFigureRefIsNeverReportedMissing() throws {
        let url = makeTempBundleURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try DocumentBundle.write(docWithFigure(ref: ""), to: url)

        let buffer = WorkspaceDocument()
        try buffer.load(from: url)

        #expect(buffer.missingImageRefs.isEmpty)   // a placeholder ref points at no file
    }

    // MARK: Directory creation on save

    @Test func savingADocumentWithAFigureRefCreatesTheImagesDirectory() throws {
        let url = makeTempBundleURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let buffer = WorkspaceDocument(document: docWithFigure(ref: "harbor.jpg"))
        #expect(buffer.persist(to: url) == true)

        let images = url.appendingPathComponent("images", isDirectory: true)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: images.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
        // The just-saved ref has no file yet, so it is flagged for the writer.
        #expect(buffer.missingImageRefs == ["harbor.jpg"])
    }

    @Test func savingADocumentWithNoFigureRefsCreatesNoImagesDirectory() throws {
        let url = makeTempBundleURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let buffer = WorkspaceDocument(document: docWithFigure(ref: ""))
        #expect(buffer.persist(to: url) == true)

        let images = url.appendingPathComponent("images", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: images.path))
        #expect(buffer.missingImageRefs.isEmpty)
    }

    // MARK: Shipped example (real-path)

    @Test func theShippedGrayHarborFigureResolvesItsImage() throws {
        let bundle = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GalleyShellTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // app
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("examples/GrayHarbor.galley", isDirectory: true)

        let buffer = WorkspaceDocument()
        try buffer.load(from: bundle)

        let hasFigure = buffer.document.blocks.contains { if case .figure = $0.content { return true } else { return false } }
        #expect(hasFigure)                       // the example exercises a real figure block
        #expect(buffer.missingImageRefs.isEmpty) // images/lighthouse.jpg ships alongside it
    }

    // MARK: setFigureCaption mutator

    @Test func setFigureCaptionUpdatesTheDocumentAndIsUndoable() {
        let buffer = WorkspaceDocument(document: docWithFigure(ref: "harbor.jpg", caption: "old"))
        buffer.setFigureCaption(atBlock: 1, to: "Dawn over the harbor.")

        #expect(buffer.document.blocks[1].content == .figure(imageRef: "harbor.jpg", caption: "Dawn over the harbor."))
        #expect(buffer.canUndo)                      // the edit checkpointed the prior state
        buffer.undo()
        #expect(buffer.document.blocks[1].content == .figure(imageRef: "harbor.jpg", caption: "old"))
        buffer.redo()                                // the undone caption re-applies
        #expect(buffer.document.blocks[1].content == .figure(imageRef: "harbor.jpg", caption: "Dawn over the harbor."))
    }
}
