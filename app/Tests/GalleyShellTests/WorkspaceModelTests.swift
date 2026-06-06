//
//  WorkspaceModelTests.swift
//  GalleyShellTests
//
//  Behavioral tests for the workspace store (`WorkspaceModel`) and the per-buffer
//  state (`WorkspaceDocument`), derived from their Behavior Statements. The
//  auto-save and load/persist paths run against a real temporary `.galley` bundle
//  on disk — no stub stands in for `DocumentBundle` (Integration Reality, rule
//  13a). Tests run on the main actor because the types are `@MainActor`.
//

import Foundation
import Testing
import GalleyCore
@testable import GalleyShell

@MainActor
@Suite("Workspace buffers and switching")
struct WorkspaceModelTests {

    // MARK: Fixtures

    /// A small document with one paragraph of real text, for round-trip assertions.
    private func makeDocument(text: String) -> Document {
        Document(
            blocks: [Block(id: 0, content: .paragraph(runs: [Run(text: text)]))],
            nextBlockID: 1
        )
    }

    /// A fresh, unique bundle URL under the temp directory (not yet created).
    private func makeTempBundleURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("galley-ws-\(UUID().uuidString).galley")
    }

    /// Writes a document to a fresh temp bundle and returns its URL.
    private func writeBundle(_ document: Document) throws -> URL {
        let url = makeTempBundleURL()
        try DocumentBundle.write(document, to: url)
        return url
    }

    // MARK: new() DOES

    /// new() DOES append a blank buffer and make it current, leaving the prior one.
    @Test func newAppendsBlankBufferAndSwitches() {
        let ws = WorkspaceModel()
        #expect(ws.documents.count == 1)

        ws.new()

        #expect(ws.documents.count == 2)
        #expect(ws.currentIndex == 1)
        #expect(ws.current.fileURL == nil)
        #expect(ws.current.hasContent == false)
    }

    // MARK: open(url:) DOES

    /// open(url:) DOES load the bundle into a new buffer, switch to it, and keep the
    /// existing buffers. Asserts the loaded document equals what was on disk.
    @Test func openLoadsBundleIntoNewBufferAndSwitches() throws {
        let doc = makeDocument(text: "Opened prose.")
        let url = try writeBundle(doc)
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = WorkspaceModel()
        let firstBuffer = ws.documents[0]

        let ok = ws.open(url: url)

        #expect(ok)
        #expect(ws.documents.count == 2)
        #expect(ws.currentIndex == 1)
        #expect(ws.current.document == doc)
        #expect(ws.current.fileURL == url)
        // The pre-existing buffer survives unchanged.
        #expect(ws.documents[0] === firstBuffer)
    }

    // MARK: open(url:) REJECTS WHEN

    /// open(url:) REJECTS WHEN the bundle cannot be read — no buffer is appended,
    /// the current index is unchanged, and it returns false.
    @Test func openRejectsUnreadableBundleAndLeavesWorkspaceUnchanged() {
        let ws = WorkspaceModel()
        let countBefore = ws.documents.count
        let indexBefore = ws.currentIndex

        // A path with no bundle on disk — read throws.
        let missing = makeTempBundleURL()
        let ok = ws.open(url: missing)

        #expect(ok == false)
        #expect(ws.documents.count == countBefore)
        #expect(ws.currentIndex == indexBefore)
    }

    // MARK: switchTo(index:) DOES

    /// switchTo(index:) DOES set the current index to a valid slot.
    @Test func switchToSetsCurrentIndex() {
        let ws = WorkspaceModel()
        ws.new()
        ws.new()   // three buffers, current == 2

        ws.switchTo(index: 0)

        #expect(ws.currentIndex == 0)
    }

    /// switchTo(index:) DOES auto-save the outgoing buffer when it is file-backed.
    /// Asserts on the persisted on-disk state, read back after the switch.
    @Test func switchToAutosavesOutgoingFileBackedBuffer() throws {
        let url = try writeBundle(makeDocument(text: "before"))
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = WorkspaceModel()
        #expect(ws.open(url: url))                 // current is now the file-backed buffer
        ws.current.apply(.insertText(" after", blockID: 0, offset: 6))

        ws.switchTo(index: 0)                       // switch away → outgoing auto-saves

        let onDisk = try DocumentBundle.read(from: url)
        #expect(onDisk == ws.documents[1].document) // edited buffer was persisted
        if case .paragraph(let runs) = onDisk.blocks[0].content {
            #expect(runs.map(\.text).joined() == "before after")
        } else {
            Issue.record("expected a paragraph block on disk")
        }
    }

    /// switchTo(index:) does NOT persist an unsaved buffer (no fileURL) and keeps its
    /// in-memory edits — switching never loses or spuriously files unsaved work.
    @Test func switchToLeavesUnsavedBufferInMemoryOnly() {
        let ws = WorkspaceModel()           // slot 0: a blank, unsaved buffer
        ws.current.apply(.insertText("draft", blockID: 0, offset: 0))
        ws.new()                            // switch away from the unsaved buffer

        let original = ws.documents[0]
        #expect(original.fileURL == nil)    // never auto-filed
        if case .paragraph(let runs) = original.document.blocks[0].content {
            #expect(runs.map(\.text).joined() == "draft")   // edit retained in memory
        } else {
            Issue.record("expected a paragraph block in memory")
        }
    }

    // MARK: switchTo(index:) REJECTS WHEN

    /// switchTo(index:) REJECTS an out-of-range index as a no-op (no crash, no move).
    @Test func switchToOutOfRangeIsNoOp() {
        let ws = WorkspaceModel()
        ws.new()                            // current == 1

        ws.switchTo(index: 99)

        #expect(ws.currentIndex == 1)
    }

    // MARK: WorkspaceDocument.hasContent

    /// hasContent is false for a pristine blank and true once a run carries text.
    @Test func hasContentTracksNonEmptyRunText() {
        let buffer = WorkspaceDocument()
        #expect(buffer.hasContent == false)

        buffer.apply(.insertText("x", blockID: 0, offset: 0))

        #expect(buffer.hasContent)
    }

    // MARK: WorkspaceDocument.apply DOES

    /// apply(_:) DOES replace the document with the reducer's result — asserts on
    /// the concrete mutated block content, not a derived flag.
    @Test func applyMutatesDocumentViaReducer() {
        let buffer = WorkspaceDocument()
        buffer.apply(.insertText("Hello", blockID: 0, offset: 0))

        #expect(buffer.document.blocks[0].content == .paragraph(runs: [Run(text: "Hello")]))
    }

    // MARK: WorkspaceDocument chapter overlay

    /// The chapter-overlay methods DO mutate the document's cuts: place adds a cut at
    /// the block, setCutTitle titles it, and remove takes it away. Asserts on
    /// `document.cuts` after each delegated call.
    @Test func chapterOverlayMethodsMutateCuts() {
        // Two blocks so a cut can anchor to the second.
        let buffer = WorkspaceDocument(document: Document(
            blocks: [
                Block(id: 0, content: .paragraph(runs: [Run(text: "one")])),
                Block(id: 1, content: .paragraph(runs: [Run(text: "two")])),
            ],
            nextBlockID: 2
        ))

        buffer.placeCut(atBlock: 1)
        #expect(buffer.document.cuts.contains { $0.blockID == 1 })

        buffer.setCutTitle(atBlock: 1, to: "Chapter Two")
        #expect(buffer.document.cuts.first { $0.blockID == 1 }?.title == "Chapter Two")

        buffer.removeCut(atBlock: 1)
        #expect(buffer.document.cuts.contains { $0.blockID == 1 } == false)
    }

    // MARK: WorkspaceDocument.load REJECTS WHEN

    /// load(from:) REJECTS a bundle missing its prose file — throws and leaves the
    /// buffer's document, fileURL, and status unchanged.
    @Test func loadRejectsMissingProseAndLeavesBufferUnchanged() throws {
        let url = makeTempBundleURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // No prose.txt written → read throws missingProse.

        let buffer = WorkspaceDocument()
        let before = buffer.document

        #expect(throws: (any Error).self) {
            try buffer.load(from: url)
        }
        #expect(buffer.document == before)
        #expect(buffer.fileURL == nil)
    }

    // MARK: WorkspaceDocument.persist DOES

    /// persist(to:) DOES write both bundle artifacts to disk and records the URL.
    /// Asserts the document can be read back equal from the real files.
    @Test func persistWritesBundleAndRecordsURL() throws {
        let url = makeTempBundleURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let buffer = WorkspaceDocument(document: makeDocument(text: "saved"))
        let ok = buffer.persist(to: url)

        #expect(ok)
        #expect(buffer.fileURL == url)
        let reloaded = try DocumentBundle.read(from: url)
        #expect(reloaded == buffer.document)
    }

    // MARK: WorkspaceDocument.setMetadata DOES

    /// setMetadata DOES write the named field into the document's metadata.
    @Test func setMetadataWritesField() {
        let buffer = WorkspaceDocument()
        buffer.setMetadata(\.title, to: "The Galley")

        #expect(buffer.document.meta.title == "The Galley")
    }
}
