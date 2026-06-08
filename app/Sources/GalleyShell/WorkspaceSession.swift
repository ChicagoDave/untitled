//
//  WorkspaceSession.swift
//  GalleyShell
//
//  Purpose: Persists which stories were open so the workspace can reopen them on
//  the next launch (session restore). Stores the file-backed buffers' URLs and the
//  current one's index in `UserDefaults`; unsaved blank buffers have no URL and are
//  not restorable. It also persists the workspace-global reveal-pane orientation
//  (LT5-3). The `UserDefaults` instance is injectable so this stays headlessly
//  testable without touching the real app domain.
//  Public interface: `WorkspaceSession`, `save(urls:currentIndex:)`, `load()`,
//  `save(orientation:)`, `loadOrientation()`.
//  Owner context: GalleyShell — app-layer session state. Foundation only.
//

import Foundation

/// A `UserDefaults`-backed record of the open stories, for reopening on launch.
public struct WorkspaceSession {

    private let defaults: UserDefaults
    private static let urlsKey = "galley.session.openDocuments"
    private static let indexKey = "galley.session.currentIndex"
    private static let orientationKey = "galley.session.revealOrientation"

    /// Creates a session store over a `UserDefaults` (defaults to `.standard`; tests
    /// inject a private suite).
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records the open stories and which one is current.
    /// - Parameters:
    ///   - urls: the file-backed buffers' bundle URLs, in slot order.
    ///   - currentIndex: the index of the current story within `urls`.
    public func save(urls: [URL], currentIndex: Int) {
        defaults.set(urls.map(\.path), forKey: Self.urlsKey)
        defaults.set(currentIndex, forKey: Self.indexKey)
    }

    /// The previously recorded stories and current index (empty / 0 when none).
    public func load() -> (urls: [URL], currentIndex: Int) {
        let paths = defaults.stringArray(forKey: Self.urlsKey) ?? []
        return (paths.map { URL(fileURLWithPath: $0) }, defaults.integer(forKey: Self.indexKey))
    }

    /// Records the workspace-global reveal-pane orientation.
    /// - Parameter orientation: where the reveal pane sits relative to the editor.
    public func save(orientation: RevealOrientation) {
        defaults.set(orientation.rawValue, forKey: Self.orientationKey)
    }

    /// The previously recorded reveal-pane orientation, or `.right` when the key is
    /// absent (a session saved before LT5-3) or holds an unrecognized value.
    public func loadOrientation() -> RevealOrientation {
        guard let raw = defaults.string(forKey: Self.orientationKey),
              let orientation = RevealOrientation(rawValue: raw) else { return .right }
        return orientation
    }
}
