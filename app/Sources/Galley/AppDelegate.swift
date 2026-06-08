//
//  AppDelegate.swift
//  Galley
//
//  Purpose: The AppKit application delegate — the executable-side glue that
//  (1) promotes the SwiftPM-launched process to a regular foreground app, and
//  (2) receives Launch Services open-document events (Finder double-click, the
//  `open` CLI, drag-to-dock) and routes them into the workspace store. The
//  decision logic lives in `WorkspaceModel.open(url:)` (GalleyShell, headlessly
//  tested, ADR-0011); the delegate methods here are thin callers (ADR-0018).
//  Public interface: `AppDelegate` (via `@NSApplicationDelegateAdaptor`),
//  `AppWorkspace.shared` (the one workspace both this delegate and the SwiftUI
//  scene observe).
//  Owner context: Galley — the macOS shell. AppKit lives here only.
//

import AppKit
import GalleyShell

/// The single window's workspace, shared by the AppKit delegate and the SwiftUI
/// scene.
///
/// A Finder double-click can deliver an open-document event before the SwiftUI
/// scene's state is established, so the workspace cannot be owned by view state
/// alone. This app-side holder gives both sides one `WorkspaceModel` to read and
/// mutate (ADR-0018). It is executable glue, not domain state — `WorkspaceModel`
/// itself stays AppKit-free in GalleyShell (ADR-0011).
@MainActor
enum AppWorkspace {

    /// The process-wide workspace for this single-window app, backed by the session
    /// store so the last-open stories reopen on the next launch.
    static let shared = WorkspaceModel(session: WorkspaceSession())
}

/// Makes the SwiftPM-launched executable behave as a regular foreground app and
/// dispatches Launch Services open-document events into the workspace.
///
/// A bare SwiftPM executable launches without an activation policy, so its window
/// neither appears in the Dock nor comes to the front. Setting `.regular` and
/// activating on launch gives the expected app behaviour.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Promotes the process to a regular foreground app, brings it forward, and
    /// reopens the last session's stories — unless Launch Services already opened a
    /// document (e.g. a Finder double-click launch), which takes precedence.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if AppWorkspace.shared.openDocumentURLs.isEmpty {
            AppWorkspace.shared.restore()
        }
    }

    /// Records the open stories on quit so the next launch reopens them.
    func applicationWillTerminate(_ notification: Notification) {
        AppWorkspace.shared.saveSession()
    }

    /// Quits when the last window closes — expected single-window behaviour.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        true
    }

    /// Opens `.galley` packages handed over by Launch Services (Finder
    /// double-click, the `open` CLI, drag-to-dock).
    ///
    /// Each URL is routed into the shared workspace's tested open path; a failed
    /// read leaves the workspace unchanged (`WorkspaceModel.open(url:)`).
    ///
    /// - Parameters:
    ///   - application: the app receiving the event.
    ///   - urls: the document package URLs to open.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            AppWorkspace.shared.open(url: url)
        }
    }

    /// Legacy path-based open hook, still delivered on some launch paths.
    ///
    /// - Parameters:
    ///   - sender: the app receiving the event.
    ///   - filename: the document package path to open.
    /// - Returns: `true` if the bundle loaded into a new buffer; `false` if the
    ///   read failed (the workspace is unchanged).
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        AppWorkspace.shared.open(url: URL(fileURLWithPath: filename))
    }
}
