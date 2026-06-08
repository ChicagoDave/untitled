//
//  DocumentTextView.swift
//  Galley
//
//  Purpose: The editing-surface host (ADR-0003) — a `NSViewRepresentable`
//  wrapping the `InputController` (a TextKit 2 `NSTextView` subclass) inside a
//  scroll view. The view renders from the current `WorkspaceDocument` buffer and
//  writes edits back through it, so SwiftUI never holds the text; the buffer does.
//  Public interface: `DocumentTextView`.
//  Owner context: Galley — the macOS shell's AppKit/SwiftUI bridge.
//

import AppKit
import SwiftUI
import GalleyShell

/// Hosts the editable TextKit 2 text view bound to a `WorkspaceDocument` buffer.
struct DocumentTextView: NSViewRepresentable {

    /// The document buffer the editor reads from and writes to.
    var buffer: WorkspaceDocument

    /// The shared caret, read here only so SwiftUI re-runs `updateNSView` when the
    /// reveal surface moves the caret — letting this pane reconcile (ADR-0033). The
    /// controller reads the live value from `buffer.currentCaret`.
    var caretToken: Caret?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]

        let contentSize = scrollView.contentSize

        // `usingTextLayoutManager: true` selects the TextKit 2 stack (ADR-0003);
        // the subclass inherits the initializer since all its stored properties
        // have defaults.
        let textView = InputController(usingTextLayoutManager: true)
        textView.buffer = buffer
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false      // undo flows through the model later, not TextKit
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 40, height: 32)

        textView.frame = NSRect(origin: .zero, size: contentSize)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView

        textView.renderFromModel(caret: EditorLayout.build(from: buffer.document).firstEditablePosition())

        // The view is not in a window yet; defer making it first responder so the
        // editor accepts typing on launch without a click.
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let controller = scrollView.documentView as? InputController else { return }

        // Switching buffers swaps the bound document on the one persistent text view
        // (keeping first-responder), and re-renders from the newly current buffer.
        // Same buffer, just edited → fall through to the no-op-if-unchanged sync.
        if controller.buffer !== buffer {
            controller.buffer = buffer
            controller.renderFromModel(caret: EditorLayout.build(from: buffer.document).firstEditablePosition())
        } else {
            controller.syncFromModelIfNeeded()
            controller.reconcileSharedCaret()   // follow a caret moved by the reveal surface (ADR-0033)
        }
    }
}
