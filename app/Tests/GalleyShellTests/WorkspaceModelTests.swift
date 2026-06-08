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

    // MARK: Session restore (LT3)

    /// A session store over a private defaults suite, so tests never touch the real
    /// app domain.
    private func sessionStore() -> WorkspaceSession {
        WorkspaceSession(defaults: UserDefaults(suiteName: "galley.tests.\(UUID().uuidString)")!)
    }

    @Test func restoreReopensTheStoriesSavedToTheSession() throws {
        let first = try writeBundle(makeDocument(text: "First."))
        let second = try writeBundle(makeDocument(text: "Second."))
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        let session = sessionStore()
        session.save(urls: [first, second], currentIndex: 1)

        let workspace = WorkspaceModel(session: session)
        #expect(workspace.restore() == true)
        #expect(workspace.openDocumentURLs.map(\.path) == [first.path, second.path])
        #expect(workspace.currentIndex == 1)
    }

    @Test func restoreSkipsAStoryWhoseFileNoLongerExistsAndKeepsTheRest() throws {
        let present = try writeBundle(makeDocument(text: "Here."))
        defer { try? FileManager.default.removeItem(at: present) }
        let missing = makeTempBundleURL()                    // never written
        let session = sessionStore()
        session.save(urls: [missing, present], currentIndex: 0)

        let workspace = WorkspaceModel(session: session)
        #expect(workspace.restore() == true)
        #expect(workspace.openDocumentURLs.map(\.path) == [present.path])   // missing one dropped
    }

    @Test func restoreWithNoRecordLeavesTheLaunchBlankUntouched() {
        let workspace = WorkspaceModel(session: sessionStore())
        #expect(workspace.restore() == false)
        #expect(workspace.documents.count == 1)
        #expect(workspace.current.fileURL == nil)
    }

    @Test func openRecordsTheStoryToTheSessionForNextLaunch() throws {
        let url = try writeBundle(makeDocument(text: "Saved."))
        defer { try? FileManager.default.removeItem(at: url) }
        let session = sessionStore()

        let workspace = WorkspaceModel(session: session)
        #expect(workspace.open(url: url) == true)
        #expect(session.load().urls.map(\.path) == [url.path])   // open() persisted the session
    }

    // MARK: Reveal orientation persistence (LT5-3)

    @Test func loadOrientationDefaultsToRightWhenNoKeyExists() {
        let session = sessionStore()
        #expect(session.loadOrientation() == .right)
    }

    @Test func savingOrientationThenReadingBackYieldsTheStoredValue() {
        let session = sessionStore()
        session.save(orientation: .below)
        #expect(session.loadOrientation() == .below)
    }

    @Test func aWorkspaceInitializedFromASessionCarriesTheStoredOrientation() {
        let session = sessionStore()
        session.save(orientation: .left)

        let workspace = WorkspaceModel(session: session)
        #expect(workspace.revealOrientation == .left)
    }

    @Test func setRevealOrientationUpdatesTheModelAndPersistsToTheSession() {
        let session = sessionStore()
        let workspace = WorkspaceModel(session: session)
        #expect(workspace.revealOrientation == .right)   // default before any change

        workspace.setRevealOrientation(.below)

        #expect(workspace.revealOrientation == .below)         // model updated
        #expect(session.loadOrientation() == .below)           // persisted for next launch
    }

    @Test func workspaceWithNoSessionDefaultsToRightAndStillTracksChanges() {
        let workspace = WorkspaceModel()
        #expect(workspace.revealOrientation == .right)

        workspace.setRevealOrientation(.left)
        #expect(workspace.revealOrientation == .left)   // no-store path updates the property
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

    // MARK: open(url:) DOES — bible loading (real-path, §9)

    /// open(url:) DOES populate the buffer's bible index from the package's
    /// `bible/` directory. Runs against real `.md` files on disk — no stub stands
    /// in for the BibleIndex filesystem read (Integration Reality, ADR-0020).
    @Test func openLoadsBibleIndexFromPackageBibleDirectory() throws {
        let url = try writeBundle(makeDocument(text: "Prose."))
        defer { try? FileManager.default.removeItem(at: url) }

        let bibleDir = url.appendingPathComponent("bible", isDirectory: true)
        try FileManager.default.createDirectory(at: bibleDir, withIntermediateDirectories: true)
        try "# Aldous Finch\nGruff harbormaster.".write(
            to: bibleDir.appendingPathComponent("aldous-finch.md"), atomically: true, encoding: .utf8)

        let ws = WorkspaceModel()
        #expect(ws.open(url: url))

        #expect(ws.current.bibleIndex.entries.count == 1)
        #expect(ws.current.bibleIndex.entry(named: "Aldous Finch")?.notes == "Gruff harbormaster.")
    }

    /// open(url:) DOES leave the bible index empty when the package has no `bible/`
    /// directory — a project without a bible is normal (ADR-0008).
    @Test func openLeavesBibleIndexEmptyWhenNoBibleDirectory() throws {
        let url = try writeBundle(makeDocument(text: "Prose."))
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = WorkspaceModel()
        #expect(ws.open(url: url))

        #expect(ws.current.bibleIndex.entries.isEmpty)
    }

    /// open(url:) DOES populate the buffer's snippet index from the package's
    /// `snippets/` directory — the source for `@`-completion (real-path, ADR-0020).
    @Test func openLoadsSnippetIndexFromPackageSnippetsDirectory() throws {
        let url = try writeBundle(makeDocument(text: "Prose."))
        defer { try? FileManager.default.removeItem(at: url) }

        let snippetsDir = url.appendingPathComponent("snippets", isDirectory: true)
        try FileManager.default.createDirectory(at: snippetsDir, withIntermediateDirectories: true)
        try "LONDON —".write(
            to: snippetsDir.appendingPathComponent("dateline.txt"), atomically: true, encoding: .utf8)

        let ws = WorkspaceModel()
        #expect(ws.open(url: url))

        #expect(ws.current.snippetIndex.entries.count == 1)
        #expect(ws.current.snippetIndex.snippet(named: "Dateline")?.body == "LONDON —")
    }

    /// open(url:) DOES populate the buffer's template index from the package's
    /// `templates/` directory — the source for the Cmd-; Block Palette (BP2). This is
    /// the exact open→reloadIndexes→templateIndex chain the palette reads from.
    @Test func openLoadsTemplateIndexFromPackageTemplatesDirectory() throws {
        let url = try writeBundle(makeDocument(text: "Prose."))
        defer { try? FileManager.default.removeItem(at: url) }

        let templatesDir = url.appendingPathComponent("templates", isDirectory: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        // A uniquely-named story template, so it is unambiguously the story layer
        // (built-ins are also merged in — LT1, ADR-0025).
        try "override: smallCaps\n\nHARBOR DISPATCH —".write(
            to: templatesDir.appendingPathComponent("harbor-dispatch.galley-template"), atomically: true, encoding: .utf8)

        let ws = WorkspaceModel()
        #expect(ws.open(url: url))

        #expect(ws.current.templateIndex.template(named: "Harbor Dispatch")?.body == "HARBOR DISPATCH —")
        #expect(ws.current.templateIndex.template(named: "Epigraph") != nil)   // built-ins merged alongside
    }

    /// A package with no `templates/` directory still offers the built-in toolkit —
    /// the story layer is absent but built-ins are always merged in (LT1, ADR-0025).
    @Test func openWithoutTemplatesDirectoryStillOffersBuiltInTemplates() throws {
        let url = try writeBundle(makeDocument(text: "Prose."))
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = WorkspaceModel()
        #expect(ws.open(url: url))

        // Built-in names resolve regardless of any user-folder content on this machine
        // (a user override changes a template's overrides, never its presence).
        for builtin in BuiltInTemplates.all {
            #expect(ws.current.templateIndex.template(named: builtin.name) != nil)
        }
    }

    /// A brand-new, never-saved buffer (no fileURL) still has the built-in template
    /// toolkit — the fix for "a new project's palette is empty" (LT1, ADR-0025).
    @Test func newBufferHasBuiltInTemplatesWithoutAnyProjectOnDisk() {
        let ws = WorkspaceModel()   // starts with one blank, unsaved buffer

        #expect(ws.current.fileURL == nil)
        for builtin in BuiltInTemplates.all {
            #expect(ws.current.templateIndex.template(named: builtin.name) != nil)
        }
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

    // MARK: close(index:) DOES

    /// close DOES persist a file-backed buffer before removing it, and lands the
    /// current index on the previous neighbour. Asserts the edit reached disk.
    @Test func closePersistsAndRemovesFileBackedBuffer() throws {
        let url = try writeBundle(makeDocument(text: "kept"))
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = WorkspaceModel()           // slot 0: blank
        #expect(ws.open(url: url))          // slot 1: file-backed, current == 1
        ws.current.apply(.insertText("!", blockID: 0, offset: 4))

        let outcome = ws.close(index: 1)

        #expect(outcome == .closed)
        #expect(ws.documents.count == 1)
        #expect(ws.currentIndex == 0)
        let onDisk = try DocumentBundle.read(from: url)
        if case .paragraph(let runs) = onDisk.blocks[0].content {
            #expect(runs.map(\.text).joined() == "kept!")   // persisted on close
        } else {
            Issue.record("expected a paragraph block on disk")
        }
    }

    /// close DOES remove an unsaved but empty blank silently (no confirmation).
    @Test func closeRemovesEmptyBlankSilently() {
        let ws = WorkspaceModel()
        ws.new()                            // two blanks, current == 1

        let outcome = ws.close(index: 1)

        #expect(outcome == .closed)
        #expect(ws.documents.count == 1)
        #expect(ws.currentIndex == 0)
    }

    /// close of the current buffer in the middle lands on the previous neighbour.
    @Test func closeCurrentLandsOnPreviousNeighbour() {
        let ws = WorkspaceModel()
        ws.new()
        ws.new()                            // three blanks, current == 2
        ws.switchTo(index: 1)               // current == 1 (the middle)

        ws.close(index: 1)

        #expect(ws.documents.count == 2)
        #expect(ws.currentIndex == 0)       // index - 1
    }

    /// close of the current buffer at slot 0 clamps the neighbour index to 0 (the
    /// `max(index - 1, 0)` guard) rather than going negative.
    @Test func closeCurrentSlotZeroClampsToZero() {
        let ws = WorkspaceModel()
        ws.new()                            // current == 1
        ws.switchTo(index: 0)               // current == 0 (a blank slot)

        ws.close(index: 0)

        #expect(ws.documents.count == 1)
        #expect(ws.currentIndex == 0)       // clamped, not -1
    }

    /// close of a buffer before the current one shifts the current index left.
    @Test func closeEarlierBufferShiftsCurrentLeft() {
        let ws = WorkspaceModel()
        ws.new()
        ws.new()                            // current == 2

        ws.close(index: 0)                  // remove an earlier slot

        #expect(ws.documents.count == 2)
        #expect(ws.currentIndex == 1)       // 2 shifted down to 1
    }

    /// close of the LAST buffer replaces it with a fresh blank — the window is never
    /// left empty (ADR-0015).
    @Test func closeLastBufferReplacesWithBlank() throws {
        let url = try writeBundle(makeDocument(text: "only"))
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = WorkspaceModel()
        #expect(ws.open(url: url))
        ws.close(index: 0)                  // remove the original blank → file-backed is sole buffer
        #expect(ws.documents.count == 1)

        ws.close(index: 0)                  // now close the only (file-backed) buffer

        #expect(ws.documents.count == 1)    // replaced, not emptied
        #expect(ws.currentIndex == 0)
        #expect(ws.current.fileURL == nil)  // the replacement is a fresh blank
        #expect(ws.current.hasContent == false)
    }

    // MARK: close(index:) REJECTS WHEN

    /// close REJECTS an unsaved buffer that has content — returns needsConfirmation
    /// and leaves the workspace entirely unchanged.
    @Test func closeRejectsUnsavedBufferWithContent() {
        let ws = WorkspaceModel()
        ws.current.apply(.insertText("draft", blockID: 0, offset: 0))
        let countBefore = ws.documents.count

        let outcome = ws.close(index: 0)

        #expect(outcome == .needsConfirmation(index: 0))
        #expect(ws.documents.count == countBefore)   // nothing removed
        #expect(ws.current.hasContent)               // buffer still present and intact
    }

    /// close of an out-of-range index is a no-op returning .closed.
    @Test func closeOutOfRangeIsNoOp() {
        let ws = WorkspaceModel()
        let outcome = ws.close(index: 99)

        #expect(outcome == .closed)
        #expect(ws.documents.count == 1)
    }

    // MARK: discardAndClose(index:) DOES

    /// discardAndClose DOES remove an unsaved-with-content buffer (the Discard path),
    /// dropping its in-memory edits without persisting.
    @Test func discardAndCloseRemovesUnsavedBuffer() {
        let ws = WorkspaceModel()
        ws.new()                                 // slot 1 current
        ws.current.apply(.insertText("scratch", blockID: 0, offset: 0))
        #expect(ws.close(index: 1) == .needsConfirmation(index: 1))   // guard fires

        ws.discardAndClose(index: 1)             // user discards

        #expect(ws.documents.count == 1)
        #expect(ws.currentIndex == 0)
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
