//
//  RevealOrientation.swift
//  GalleyShell
//
//  Purpose: The workspace-level placement of the reveal pane relative to the prose
//  editor — left, right, or below (LT5-3). A closed, three-case vocabulary whose
//  raw value is the persistence key written to `UserDefaults` via `WorkspaceSession`.
//  Public interface: `RevealOrientation`, its `label`, and `next` (cycle order).
//  Owner context: GalleyShell — app-layer view preference. Foundation only; no
//  AppKit/SwiftUI, so the value stays headlessly testable.
//

import Foundation

/// Where the reveal pane sits relative to the prose editor.
///
/// A workspace-global preference (not per-document): all open buffers share one
/// orientation. The `rawValue` ("left"/"right"/"below") is the stable persistence
/// key — do not rename without a migration. Default placement is `.right`.
public enum RevealOrientation: String, CaseIterable, Sendable {

    /// Reveal pane to the left of the prose editor.
    case left

    /// Reveal pane to the right of the prose editor — the default placement.
    case right

    /// Reveal pane below the prose editor.
    case below

    /// A human-readable label for the orientation selector.
    public var label: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .below: return "Below"
        }
    }

    /// The next orientation in `allCases` order, wrapping around — drives the
    /// keyboard cycle shortcut so the writer can rotate placement without a mouse.
    public var next: RevealOrientation {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}
