//
//  Galley.swift
//  Galley
//
//  Purpose: The macOS app entry point (ADR-0001 native, ADR-0003 AppKit-hosted)
//  — a single-window SwiftUI shell over GalleyCore. Phase 1 is a scaffold: it
//  opens and saves the `.galley` bundle pair and reports status; the editing
//  surface arrives in later phases.
//  Public interface: `Galley` (`@main`).
//  Owner context: Galley — the macOS shell. AppKit/SwiftUI live here only.
//

import AppKit
import SwiftUI
import GalleyShell

/// The application entry point: one window group over a single `WorkspaceModel`
/// (an ordered set of open document buffers), with New/Open/Save wired into the
/// standard menu commands.
@main
struct Galley: App {

    /// Forces foreground-app behaviour when launched via `swift run` (see
    /// `AppDelegate`).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The window's workspace — the open buffers and the current one.
    @State private var workspace = WorkspaceModel()

    var body: some Scene {
        WindowGroup("Galley") {
            ContentView(workspace: workspace)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { workspace.new() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open…") { workspace.openWithPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save…") { workspace.saveCurrentWithPanel() }
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}

/// Makes the SwiftPM-launched executable behave as a regular foreground app.
///
/// A bare SwiftPM executable launches without an activation policy, so its window
/// neither appears in the Dock nor comes to the front. Setting `.regular` and
/// activating on launch gives the expected app behaviour during `swift run`,
/// without needing an Xcode app bundle in Phase 1.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Promotes the process to a regular foreground app and brings it forward.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Quits when the last window closes — expected single-window behaviour.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        true
    }
}
