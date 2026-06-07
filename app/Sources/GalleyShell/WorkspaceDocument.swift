//
//  WorkspaceDocument.swift
//  GalleyShell
//
//  Purpose: One open document buffer's headless state — the live `Document`
//  (model-as-truth, ADR-0004), the `.galley` bundle URL it loads from / saves to,
//  a human-readable status line, and the load / persist / edit operations over it.
//  This is the per-buffer unit the workspace (`WorkspaceModel`) holds. It carries
//  no AppKit or SwiftUI, so it is unit-testable headlessly (ADR-0011); the file
//  panels that choose URLs live in the `Galley` executable, never here.
//  Public interface: `WorkspaceDocument`, its observable `document` / `fileURL` /
//  `status` state, `hasContent`, `load(from:)`, `persist(to:)`, `apply(_:)`,
//  `setMetadata(_:to:)`, and the chapter-overlay editing methods.
//  Owner context: GalleyShell — app-layer document state. Depends on GalleyCore
//  (the model-as-truth) plus Foundation and Observation only; no AppKit/SwiftUI.
//

import Foundation
import Observation
import GalleyCore

/// Observable state for a single open document buffer.
///
/// Owns the live `Document` and the bundle URL it is associated with. Load and
/// save delegate the on-disk format to `DocumentBundle`; this type mediates the
/// buffer's state and surfaces a human-readable `status`. A reference type so the
/// owning `WorkspaceModel` and the SwiftUI view tree observe and mutate one shared
/// instance per buffer.
@MainActor
@Observable
public final class WorkspaceDocument {

    /// The live document (the model-as-truth). Mutated only through `load`,
    /// `apply`, `setMetadata`, and the chapter-overlay methods below.
    public private(set) var document: Document

    /// The bundle directory this buffer was last opened from or saved to, if any.
    /// `nil` for a brand-new buffer that has never been saved.
    public private(set) var fileURL: URL?

    /// A short human-readable description of the last open/save outcome.
    public private(set) var status: String

    /// The reference bible for this buffer (§9), fuzzy-indexed from the package's
    /// `bible/` directory — read in the bible side panel. Empty for a never-saved
    /// buffer (no package on disk yet).
    public private(set) var bibleIndex = BibleIndex()

    /// The reusable text snippets for this buffer (§9), indexed from the package's
    /// `snippets/` directory — the source for `@`-completion. Empty until saved.
    public private(set) var snippetIndex = SnippetIndex()

    /// The reusable block templates for this buffer (BP1), indexed from the
    /// package's `templates/` directory — the source for the Block Palette (BP2).
    /// Empty for a never-saved buffer (no package on disk yet).
    public private(set) var templateIndex = TemplateIndex()

    /// Creates a buffer. Defaults to a fresh blank document with no associated file.
    ///
    /// - Parameters:
    ///   - document: the initial document; defaults to a single empty paragraph.
    ///   - fileURL: the associated bundle URL; defaults to none (unsaved buffer).
    ///   - status: the initial status line.
    public init(
        document: Document = WorkspaceDocument.blankDocument,
        fileURL: URL? = nil,
        status: String = "New document."
    ) {
        self.document = document
        self.fileURL = fileURL
        self.status = status
        // A fresh buffer still gets the built-in (and user-level) template toolkit,
        // so the Block Palette is never empty in a new project (LT1, ADR-0025).
        reloadIndexes()
    }

    /// A document with a single empty paragraph — the editable starting point, so
    /// the editor always has a block to place the caret in.
    public static var blankDocument: Document {
        Document(blocks: [Block(id: 0, content: .paragraph(runs: []))], nextBlockID: 1)
    }

    /// Whether any run in any block carries non-empty text.
    ///
    /// The signal that a blank buffer has actually been written into — it drives the
    /// save-or-discard prompt on close (ADR-0015). A lone scene break (no text of
    /// its own) does not count as content.
    public var hasContent: Bool {
        document.blocks.contains { block in
            switch block.content {
            case .paragraph(let runs):
                return runs.contains { !$0.text.isEmpty }
            case .setPiece(_, let lines):
                return lines.contains { line in line.contains { !$0.text.isEmpty } }
            case .sceneBreak:
                return false
            }
        }
    }

    /// Loads a `.galley` bundle from disk into this buffer.
    ///
    /// On success replaces `document`, sets `fileURL`, and records a status. On
    /// failure throws and leaves `document`, `fileURL`, and `status` unchanged, so a
    /// failed open never corrupts the buffer the caller is about to discard.
    ///
    /// - Parameter url: the bundle directory URL.
    /// - Throws: `DocumentBundle.BundleError`, a `GalleyCore.ParseError`, or a
    ///   Foundation I/O error if the bundle cannot be read.
    public func load(from url: URL) throws {
        let loaded = try DocumentBundle.read(from: url)
        document = loaded
        fileURL = url
        reloadIndexes()
        status = "Opened \(url.lastPathComponent) — \(loaded.blocks.count) block(s)."
    }

    /// Rebuilds the reference indexes (§9, BP1, LT1).
    ///
    /// The **template index is layered** (ADR-0025): built-in templates + the
    /// user-level global directory are always merged in, plus the per-project
    /// `templates/` directory when this buffer is saved — so even a brand-new unsaved
    /// buffer offers the built-in (and user) toolkit. **Bible and snippets stay
    /// project-scoped** (this novel's data, ADR-0020): they load only from the
    /// package and are empty for a never-saved buffer.
    ///
    /// Called on init, load, and after save; safe to call any time the writer may
    /// have added or edited reference files.
    public func reloadIndexes() {
        templateIndex = TemplateIndex.merged(
            builtIns: BuiltInTemplates.all,
            userDirectory: TemplateIndex.userTemplateDirectory,
            storyDirectory: fileURL?.appendingPathComponent("templates", isDirectory: true)
        )

        guard let url = fileURL else {
            bibleIndex = BibleIndex()
            snippetIndex = SnippetIndex()
            return
        }
        bibleIndex = BibleIndex.load(directory: url.appendingPathComponent("bible", isDirectory: true))
        snippetIndex = SnippetIndex.load(directory: url.appendingPathComponent("snippets", isDirectory: true))
    }

    /// Writes this buffer to `url` via `DocumentBundle`, recording `fileURL` and
    /// status on success.
    ///
    /// - Parameter url: the destination bundle directory.
    /// - Returns: `true` on success, `false` if the write threw (status records why).
    @discardableResult
    public func persist(to url: URL) -> Bool {
        do {
            try DocumentBundle.write(document, to: url)
            fileURL = url
            reloadIndexes()
            status = "Saved \(url.lastPathComponent)."
            return true
        } catch {
            status = "Save failed: \(error)"
            return false
        }
    }

    /// Applies one editing intent to the document via the pure core reducer (§8),
    /// keeping the model the single source of truth (ADR-0004).
    ///
    /// - Parameter event: the model-coordinate editing intent from the input layer.
    public func apply(_ event: InputEvent) {
        document = applyInput(event, to: document)
    }

    /// Sets a single string metadata field on the document (submission fields).
    ///
    /// The controlled mutator behind the SwiftUI metadata bindings — the view layer
    /// cannot write `document` directly, so it routes field edits through here.
    ///
    /// - Parameters:
    ///   - keyPath: the metadata field to write.
    ///   - value: the new value.
    public func setMetadata(_ keyPath: WritableKeyPath<Metadata, String>, to value: String) {
        document.meta[keyPath: keyPath] = value
    }

    // MARK: Chapter overlay (reveal-pane chapter-slicing, §6)

    /// Places a boundary chapter cut at a block.
    public func placeCut(atBlock blockID: BlockID) { document.placeChapterCut(atBlock: blockID) }

    /// Removes the boundary chapter cut at a block.
    public func removeCut(atBlock blockID: BlockID) { document.removeChapterCut(atBlock: blockID) }

    /// Moves a boundary chapter cut from one block to another.
    public func moveCut(fromBlock source: BlockID, toBlock target: BlockID) {
        document.moveChapterCut(fromBlock: source, toBlock: target)
    }

    /// Sets (or clears) the title of the boundary chapter cut at a block.
    public func setCutTitle(atBlock blockID: BlockID, to title: String?) {
        document.setChapterCutTitle(atBlock: blockID, to: title)
    }
}
