//
//  WorkspaceModel.swift
//  GalleyShell
//
//  Purpose: The single-window workspace store — an ordered set of open document
//  buffers (`WorkspaceDocument`) plus the index of the current one. It is the
//  source of truth for which buffers are open and which is showing, and it owns the
//  New / Open / switch operations. AppKit file panels and SwiftUI menus live in the
//  `Galley` executable and call in with already-chosen URLs and indices, so the
//  store stays AppKit-free and headlessly testable (ADR-0011, fix (a)).
//  Public interface: `WorkspaceModel`, its observable `documents` / `currentIndex`
//  state, `current`, `new()`, `open(url:)`, `switchTo(index:)`.
//  Owner context: GalleyShell — app-layer window/navigation state. Foundation +
//  GalleyCore (transitively, via `WorkspaceDocument`) + Observation only; no
//  AppKit/SwiftUI.
//

import Foundation
import Observation

/// Observable state for one window's set of open document buffers.
///
/// Holds an ordered `[WorkspaceDocument]` and the `currentIndex` of the buffer on
/// screen. Switching away from a buffer auto-saves it when it has already been
/// saved once (`fileURL != nil`), so navigation is never destructive; an unsaved
/// blank buffer is left in memory untouched (ADR-0015).
///
/// Invariant: `documents` is never empty and `currentIndex` is always a valid index
/// into it, so `current` is always safe to read.
@MainActor
@Observable
public final class WorkspaceModel {

    /// The open buffers, in slot order (slot 1 is `documents[0]`).
    public private(set) var documents: [WorkspaceDocument]

    /// The index of the buffer currently shown in the window. Always in range.
    public private(set) var currentIndex: Int

    /// Creates a workspace with a single blank buffer — the launch state.
    public init() {
        self.documents = [WorkspaceDocument()]
        self.currentIndex = 0
    }

    /// The buffer currently shown in the window.
    ///
    /// Always valid by the type's invariant (at least one buffer; `currentIndex` in
    /// range).
    public var current: WorkspaceDocument { documents[currentIndex] }

    /// Appends a fresh blank buffer and switches to it.
    ///
    /// Auto-saves the outgoing buffer first if it has been saved before, so creating
    /// a new project never drops unsaved-to-disk work on a tracked file. Other
    /// buffers are untouched. Never rejects.
    public func new() {
        autosaveCurrentIfPersisted()
        documents.append(WorkspaceDocument())
        currentIndex = documents.count - 1
    }

    /// Loads the bundle at `url` into a new buffer and switches to it, leaving the
    /// existing buffers in place.
    ///
    /// Auto-saves the outgoing buffer (if persisted) only once the load has
    /// succeeded, so a failed open leaves the workspace entirely unchanged.
    ///
    /// - Parameter url: the bundle directory to open.
    /// - Returns: `true` if the bundle loaded and a buffer was appended; `false` if
    ///   the read failed — in which case the workspace is unchanged.
    @discardableResult
    public func open(url: URL) -> Bool {
        let buffer = WorkspaceDocument()
        do {
            try buffer.load(from: url)
        } catch {
            return false
        }
        autosaveCurrentIfPersisted()
        documents.append(buffer)
        currentIndex = documents.count - 1
        return true
    }

    /// Switches the window to the buffer at `index`, auto-saving the outgoing buffer
    /// first if it has ever been saved (ADR-0015).
    ///
    /// - Parameter index: the slot to show.
    /// - Note: an out-of-range `index` is a no-op — the workspace is unchanged.
    public func switchTo(index: Int) {
        guard documents.indices.contains(index) else { return }
        autosaveCurrentIfPersisted()
        currentIndex = index
    }

    /// Persists the current buffer if it is backed by a file, so switching away from
    /// it never loses on-disk-tracked edits. A never-saved buffer is left in memory.
    private func autosaveCurrentIfPersisted() {
        if let url = current.fileURL {
            current.persist(to: url)
        }
    }
}
