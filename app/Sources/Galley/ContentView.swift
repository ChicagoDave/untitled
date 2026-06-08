//
//  ContentView.swift
//  Galley
//
//  Purpose: The window contents — the editable text surface (§8) beside an
//  optional reveal pane (§5, ADR-0006), with Open/Save controls and a status
//  line. The reveal pane toggles with Cmd-/ and carries the chapter-slicing mode.
//  Public interface: `ContentView`.
//  Owner context: Galley — the macOS shell's SwiftUI view layer.
//

import SwiftUI
import AppKit
import GalleyShell

/// The single-window editing surface, optionally split with the reveal pane.
///
/// Binds to a `WorkspaceModel` and renders its current buffer: the editable
/// `DocumentTextView` writes through that buffer, and the `RevealPane` reads its
/// projection and edits its chapter overlay. New/Open/Save act on the workspace.
struct ContentView: View {

    /// The workspace driving this window — the open buffers and the current one.
    @Bindable var workspace: WorkspaceModel

    /// Whether the reveal pane is shown (toggled with Cmd-/).
    @State private var showReveal = false

    /// Whether the submission-fields panel is shown (toggled with Cmd-Shift-I).
    @State private var showFields = false

    /// Whether the bible reference panel is shown (toggled with Cmd-Shift-B).
    @State private var showBible = false

    /// Whether the Command key is currently held — when so, the bottom-bar buttons
    /// reveal their keyboard shortcuts.
    @State private var commandHeld = false

    /// The local `flagsChanged` monitor tracking the Command key; removed on disappear.
    @State private var flagsMonitor: Any?

    /// A bar-button title that appends its shortcut hint only while Command is held.
    private func barLabel(_ title: String, _ shortcut: String) -> String {
        commandHeld ? "\(title)  \(shortcut)" : title
    }

    /// The buffer currently shown in the window.
    private var current: WorkspaceDocument { workspace.current }

    /// A two-way binding over the workspace orientation that routes writes through
    /// `setRevealOrientation` so the choice is persisted (the property is read-only to
    /// callers by design).
    private var orientationBinding: Binding<RevealOrientation> {
        Binding(
            get: { workspace.revealOrientation },
            set: { workspace.setRevealOrientation($0) }
        )
    }

    /// The app + project name for the window title bar: "Galley — <title>" when
    /// the document is titled, otherwise just "Galley".
    private var projectTitle: String {
        let title = current.document.meta.title
        return title.isEmpty ? "Galley" : "Galley — \(title)"
    }

    /// The reveal pane host (TextKit surface, ADR-0032).
    @ViewBuilder private var revealPane: some View {
        RevealPane(buffer: current, caretToken: current.currentCaret)
    }

    /// The horizontal band: the prose editor with its fixed side panels (fields,
    /// bible) and — for the `.left`/`.right` orientations — the reveal pane inline on
    /// the indicated side. Kept a flat `HStack` (not `HSplitView`): a split view
    /// re-parents the hosted `NSScrollView`, which broke the prose `NSTextView`'s
    /// click hit-testing. The reveal pane is a *co-equal* surface (ADR-0030), so it
    /// takes an equal share of the width — `maxWidth: .infinity` like the prose editor,
    /// giving a 50/50 split of the space left after the fixed side panels (a
    /// user-draggable divider is deferred — it needs an `NSSplitViewController` host
    /// that preserves text-view hit-testing).
    @ViewBuilder private var mainRow: some View {
        HStack(spacing: 0) {
            if showReveal, workspace.revealOrientation == .left {
                revealPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
            }

            if showFields {
                MetadataPanel(buffer: current)
                Divider()
            }

            DocumentTextView(buffer: current, caretToken: current.currentCaret)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showBible {
                Divider()
                BiblePane(buffer: current)
            }

            if showReveal, workspace.revealOrientation == .right {
                Divider()
                revealPane.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The editor surface placed per the workspace's `revealOrientation`. Left/right
    /// keep the reveal pane inline in `mainRow`; `below` stacks it under the row.
    @ViewBuilder private var arrangedSurface: some View {
        if showReveal, workspace.revealOrientation == .below {
            VStack(spacing: 0) {
                mainRow
                Divider()
                revealPane.frame(height: 240)
            }
        } else {
            mainRow
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            arrangedSurface

            Divider()

            HStack(spacing: 12) {
                Button(barLabel("Open…", "⌘O")) { workspace.openWithPanel() }
                Button(barLabel("Save…", "⌘S")) { workspace.saveCurrentWithPanel() }
                Button(barLabel(showFields ? "Hide Fields" : "Fields", "⌘⇧I")) { showFields.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button(barLabel(showReveal ? "Hide Reveal" : "Reveal", "⌘/")) { showReveal.toggle() }
                    .keyboardShortcut("/", modifiers: .command)
                if showReveal {
                    Picker("Reveal placement", selection: orientationBinding) {
                        ForEach(RevealOrientation.allCases, id: \.self) { orientation in
                            Text(orientation.label).tag(orientation)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    // Keyboard-first: ⌘⇧/ cycles placement without reaching for the mouse.
                    Button("Cycle Reveal Placement") {
                        workspace.setRevealOrientation(workspace.revealOrientation.next)
                    }
                    .keyboardShortcut("/", modifiers: [.command, .shift])
                    .hidden()
                    .frame(width: 0, height: 0)
                }
                Button(barLabel(showBible ? "Hide Bible" : "Bible", "⌘⇧B")) { showBible.toggle() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Spacer()
                Text("Project \(workspace.currentIndex + 1) of \(workspace.documents.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text(current.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 700, minHeight: 480)
        .navigationTitle(projectTitle)   // drives the window's title bar
        .alert(
            "Couldn’t open that document",
            isPresented: Binding(
                get: { workspace.openError != nil },
                set: { presented in if !presented { workspace.openError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { workspace.openError = nil }
        } message: {
            Text(workspace.openError ?? "")
        }
        .onAppear {
            // Track the Command key so the bottom-bar buttons can reveal their
            // shortcuts while it is held.
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                commandHeld = event.modifierFlags.contains(.command)
                return event
            }
        }
        .onDisappear {
            if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
            flagsMonitor = nil
        }
        .confirmationDialog(
            "Save changes before closing this project?",
            isPresented: Binding(
                get: { workspace.pendingCloseIndex != nil },
                set: { presented in if !presented { workspace.pendingCloseIndex = nil } }
            ),
            presenting: workspace.pendingCloseIndex
        ) { index in
            Button("Save…") {
                workspace.saveCurrentWithPanel()
                // Only close if the save actually landed a file (panel not cancelled).
                if workspace.documents.indices.contains(index),
                   workspace.documents[index].fileURL != nil {
                    workspace.close(index: index)
                }
                workspace.pendingCloseIndex = nil
            }
            Button("Discard", role: .destructive) {
                workspace.discardAndClose(index: index)
                workspace.pendingCloseIndex = nil
            }
            Button("Cancel", role: .cancel) {
                workspace.pendingCloseIndex = nil
            }
        }
    }
}
