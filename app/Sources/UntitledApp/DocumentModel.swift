//
//  DocumentModel.swift
//  UntitledApp
//
//  Purpose: The window's observable document state — holds the in-memory
//  `Document` (the model-as-truth, ADR-0004) and the bundle URL it loaded from,
//  and drives open/save through `NSOpenPanel`/`NSSavePanel` and `DocumentBundle`.
//  Phase 1 is a scaffold: it round-trips the file pair and reports status; there
//  is no editing surface or projection yet.
//  Public interface: `DocumentModel`, its observable `document`/`fileURL`/`status`
//  state, and `open()` / `save()` / `saveAs()`.
//  Owner context: UntitledApp — the macOS shell's view-state. AppKit/SwiftUI live
//  here; never in UntitledCore.
//

import AppKit
import Observation
import UntitledCore
import UntitledShell

/// Observable view-state for a single document window.
///
/// Owns the live `Document` and the bundle URL it is associated with. The open
/// and save commands delegate the format to `DocumentBundle`; this type only
/// mediates the file panels and surfaces a human-readable `status`.
@MainActor
@Observable
public final class DocumentModel {

    /// The live document (the model-as-truth). Mutated only through load/save here
    /// in Phase 1; editing arrives in Phase 3.
    public private(set) var document: Document

    /// The bundle directory this document was last opened from or saved to, if any.
    public private(set) var fileURL: URL?

    /// A short human-readable description of the last open/save outcome.
    public private(set) var status: String

    /// Creates a model holding a fresh, empty document.
    public init() {
        self.document = Document()
        self.fileURL = nil
        self.status = "No document open."
    }

    /// Prompts for an `.untitled` bundle directory and loads it into `document`.
    ///
    /// On success, replaces `document` and sets `fileURL`. On failure, leaves both
    /// unchanged and records the reason in `status`. A cancelled panel is a no-op.
    public func open() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an .untitled document folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(from: url)
    }

    /// Loads a bundle from a known URL without prompting (used by `open()` and the
    /// `UNTITLED_OPEN` launch hook).
    ///
    /// On success replaces `document` and sets `fileURL`; on failure leaves both
    /// unchanged and records the reason in `status`.
    func load(from url: URL) {
        do {
            document = try DocumentBundle.read(from: url)
            fileURL = url
            status = "Opened \(url.lastPathComponent) — \(document.blocks.count) block(s)."
        } catch {
            status = "Open failed: \(error)"
        }
    }

    /// Saves to the current `fileURL`, or prompts for a location if there is none.
    public func save() {
        if let url = fileURL {
            persist(to: url)
        } else {
            saveAs()
        }
    }

    /// Prompts for a destination `.untitled` bundle and saves the document there.
    ///
    /// On success, records the new `fileURL`. A cancelled panel is a no-op.
    public func saveAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Untitled.untitled"
        panel.message = "Save as an .untitled document folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if persist(to: url) {
            fileURL = url
        }
    }

    /// Writes `document` to `url` via `DocumentBundle`, updating `status`.
    ///
    /// - Returns: `true` on success, `false` if the write threw.
    @discardableResult
    private func persist(to url: URL) -> Bool {
        do {
            try DocumentBundle.write(document, to: url)
            status = "Saved \(url.lastPathComponent)."
            return true
        } catch {
            status = "Save failed: \(error)"
            return false
        }
    }
}
