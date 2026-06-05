//
//  DocumentBundleTests.swift
//  UntitledShellTests
//
//  Real-path tests for the on-disk file layer (Integration Reality rule 13a):
//  every test writes to and reads from an actual temporary directory — no stub
//  of the file system stands in for `DocumentBundle`. Derived from the Behavior
//  Statements for `DocumentBundle.write(_:to:)` and `DocumentBundle.read(from:)`.
//

import Foundation
import Testing
import UntitledCore
@testable import UntitledShell

@Suite("DocumentBundle on-disk round-trip")
struct DocumentBundleTests {

    /// A document exercising every block kind, an inline italic run, and a
    /// chapter cut — enough variety that a lossy write/read would fail equality.
    private func makeSampleDocument() -> Document {
        let para = Block(
            id: 0,
            content: .paragraph(runs: [
                Run(text: "She left before the "),
                Run(text: "storm", italic: true),
                Run(text: " broke."),
            ])
        )
        let scene = Block(id: 1, content: .sceneBreak)
        let verse = Block(
            id: 2,
            content: .setPiece(kind: .verse, lines: [
                [Run(text: "Roses are red,")],
                [Run(text: "violets are blue.")],
            ])
        )
        return Document(
            blocks: [para, scene, verse],
            cuts: [ChapterCut(blockID: 2, offsetInBlock: nil, title: "Two")],
            nextBlockID: 3
        )
    }

    /// A fresh, unique bundle URL under the temp directory (not yet created).
    private func makeTempBundleURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("untitled-test-\(UUID().uuidString).untitled")
    }

    // MARK: write DOES / read DOES — lossless round-trip

    /// write then read reconstructs an equal Document (the core promise of both
    /// operations). Asserts on the reloaded model, read back from disk.
    @Test func writeThenReadReconstructsEqualDocument() throws {
        let doc = makeSampleDocument()
        let url = makeTempBundleURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try DocumentBundle.write(doc, to: url)
        let reloaded = try DocumentBundle.read(from: url)

        #expect(reloaded == doc)
    }

    /// write DOES persist two named files on disk. Asserts the actual files exist.
    @Test func writePersistsProseAndSidecarFiles() throws {
        let doc = makeSampleDocument()
        let url = makeTempBundleURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try DocumentBundle.write(doc, to: url)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: url.appendingPathComponent(DocumentBundle.proseFileName).path))
        #expect(fm.fileExists(atPath: url.appendingPathComponent(DocumentBundle.sidecarFileName).path))
    }

    /// write DOES create the bundle directory even when it does not yet exist.
    @Test func writeCreatesBundleDirectoryWhenAbsent() throws {
        let doc = makeSampleDocument()
        let url = makeTempBundleURL()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(!FileManager.default.fileExists(atPath: url.path))
        try DocumentBundle.write(doc, to: url)

        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    // MARK: read REJECTS WHEN

    /// read REJECTS WHEN the prose file is absent — throws `missingProse`, not a
    /// generic error.
    @Test func readRejectsBundleMissingProse() throws {
        let url = makeTempBundleURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Intentionally no prose.txt written.

        let expectedProseURL = url.appendingPathComponent(DocumentBundle.proseFileName)
        #expect(throws: DocumentBundle.BundleError.missingProse(expectedProseURL)) {
            _ = try DocumentBundle.read(from: url)
        }
    }
}
