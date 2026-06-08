//
//  RevealPane.swift
//  Galley
//
//  Purpose: The Reveal Codes pane host (§5, ADR-0030/ADR-0032) — a
//  `NSViewRepresentable` wrapping the `RevealController` (a TextKit 2 `NSTextView`
//  subclass) in a scroll view. Renders the model-annotated reveal stream with codes
//  as atomic chips and shares the one caret with the prose editor via
//  `WorkspaceDocument.currentCaret` (ADR-0033). This replaces the former SwiftUI
//  `FlowLayout` of chips and the "Edit Chapters" panel (retired by ADR-0030 —
//  chapter slicing/titling is done inline in the editing surfaces, LT2/LT3).
//  Public interface: `RevealPane`.
//  Owner context: Galley — the macOS shell's AppKit/SwiftUI bridge.
//

import AppKit
import SwiftUI
import GalleyShell

/// Hosts the read-from-model Reveal Codes text view bound to a `WorkspaceDocument`.
struct RevealPane: NSViewRepresentable {

    /// The document buffer the reveal surface reads from.
    var buffer: WorkspaceDocument

    /// The shared caret, read here only so SwiftUI re-runs `updateNSView` when the
    /// *other* surface moves the caret — letting this pane reconcile its selection
    /// (ADR-0033). The controller reads the live value from `buffer.currentCaret`.
    var caretToken: Caret?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]

        let contentSize = scrollView.contentSize

        let textView = RevealController(usingTextLayoutManager: true)
        textView.buffer = buffer
        textView.isEditable = true        // editable for a visible caret; model edits are intercepted (LT5-1)
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false       // undo flows through the shared model timeline, not TextKit
        textView.drawsBackground = true
        textView.backgroundColor = .windowBackgroundColor
        textView.textContainerInset = NSSize(width: 16, height: 16)

        textView.frame = NSRect(origin: .zero, size: contentSize)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        textView.render()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let controller = scrollView.documentView as? RevealController else { return }
        if controller.buffer !== buffer {
            controller.buffer = buffer
            controller.render()
        } else {
            controller.syncIfNeeded()        // re-render if the model changed (prose edit / undo)
            controller.reconcileSharedCaret() // follow a caret moved by the other surface
        }
    }
}
