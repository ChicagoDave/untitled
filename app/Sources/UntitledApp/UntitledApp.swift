//
//  UntitledApp.swift
//  UntitledApp
//
//  Purpose: The macOS app entry point (ADR-0001 native, ADR-0003 AppKit-hosted)
//  — a single-window SwiftUI shell over UntitledCore. Phase 1 is a scaffold: it
//  opens and saves the `.untitled` bundle pair and reports status; the editing
//  surface arrives in later phases.
//  Public interface: `UntitledApp` (`@main`).
//  Owner context: UntitledApp — the macOS shell. AppKit/SwiftUI live here only.
//

import AppKit
import SwiftUI

/// The application entry point: one window group over a single `DocumentModel`,
/// with Open/Save wired into the standard menu commands.
@main
struct UntitledApp: App {

    /// Forces foreground-app behaviour when launched via `swift run` (see
    /// `AppDelegate`).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The window's document state.
    @State private var model = DocumentModel()

    var body: some Scene {
        WindowGroup("Untitled") {
            ContentView(model: model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.open() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save…") { model.save() }
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
