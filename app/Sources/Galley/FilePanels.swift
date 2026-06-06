//
//  FilePanels.swift
//  Galley
//
//  Purpose: The thin AppKit panel-runner for the workspace — the only place
//  `NSOpenPanel`/`NSSavePanel` are presented. It chooses `.galley` bundle URLs and
//  hands them to the headless `WorkspaceModel`/`WorkspaceDocument`, keeping all
//  buffer state and file I/O on the testable GalleyShell side (ADR-0011, fix (a)).
//  Public interface: `FilePanels.chooseOpenURL()`, `FilePanels.chooseSaveURL(...)`,
//  and the `WorkspaceModel` panel-orchestration convenience methods.
//  Owner context: Galley — the macOS shell's AppKit glue. Window-server only.
//

import AppKit
import GalleyShell

/// Runs the document open/save panels and returns the chosen URLs.
///
/// This is the window-server boundary: it presents panels and reports a URL or
/// `nil` (cancelled). It never touches document state — the caller feeds the URL
/// into the headless workspace. `@MainActor` because the AppKit panels are.
@MainActor
enum FilePanels {

    /// Prompts for a `.galley` bundle directory to open.
    /// - Returns: the chosen directory, or `nil` if the user cancelled.
    static func chooseOpenURL() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a .galley document folder"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Prompts for a destination `.galley` bundle directory.
    /// - Parameter suggestedName: the default file name.
    /// - Returns: the chosen destination, or `nil` if the user cancelled.
    static func chooseSaveURL(suggestedName: String = "Untitled.galley") -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.message = "Save as a .galley document folder"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// AppKit panel orchestration for the headless workspace store.
///
/// These wrap the GalleyShell operations with the file-panel presentation that
/// must live in the executable, so the menu commands and toolbar buttons call one
/// method instead of duplicating the panel-then-store dance.
@MainActor
extension WorkspaceModel {

    /// Runs the open panel and, if confirmed, opens the chosen bundle as a new
    /// buffer. A cancelled panel is a no-op.
    func openWithPanel() {
        if let url = FilePanels.chooseOpenURL() {
            open(url: url)
        }
    }

    /// Saves the current buffer: straight to its existing URL, or via the save panel
    /// when the buffer has never been saved. A cancelled save panel is a no-op.
    func saveCurrentWithPanel() {
        let buffer = current
        if let url = buffer.fileURL {
            buffer.persist(to: url)
        } else if let url = FilePanels.chooseSaveURL() {
            buffer.persist(to: url)
        }
    }
}
