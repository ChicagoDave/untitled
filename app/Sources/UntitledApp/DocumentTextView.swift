//
//  DocumentTextView.swift
//  UntitledApp
//
//  Purpose: The TextKit 2 editing surface host (ADR-0003) — a `NSViewRepresentable`
//  wrapping a `NSTextView` (created with a `NSTextLayoutManager`, i.e. TextKit 2)
//  inside a scroll view. Phase 2 is read-display only: the view shows the
//  attributed string produced by `Attribution`; editing input is wired in Phase 3.
//  Public interface: `DocumentTextView`.
//  Owner context: UntitledApp — the macOS shell's AppKit/SwiftUI bridge.
//

import AppKit
import SwiftUI

/// Hosts a read-only TextKit 2 `NSTextView` that renders a document's display
/// projection. The bound `attributedString` is pushed into the view on update.
struct DocumentTextView: NSViewRepresentable {

    /// The styled text to display, derived from `displayProjection` + `Attribution`.
    var attributedString: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]

        // Size the text view to the scroll view's content area up front: a
        // zero-width text container lays out nothing, which reads as a blank page.
        let contentSize = scrollView.contentSize

        // `usingTextLayoutManager: true` selects the TextKit 2 stack (ADR-0003).
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.isEditable = false          // read-display only in Phase 2
        textView.isSelectable = true
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

        apply(attributedString, to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        apply(attributedString, to: textView)
    }

    /// Replaces the view's content with `string`, preferring the TextKit 2
    /// content storage and falling back to the compatibility text storage.
    private func apply(_ string: NSAttributedString, to textView: NSTextView) {
        if let contentStorage = textView.textContentStorage {
            // TextKit 2: edit the content storage's backing text storage inside a
            // transaction so the layout manager is notified and re-lays out.
            // Assigning `contentStorage.attributedString` directly does not render.
            if let backing = contentStorage.textStorage {
                contentStorage.performEditingTransaction {
                    backing.setAttributedString(string)
                }
            } else {
                contentStorage.attributedString = string
            }
        } else {
            textView.textStorage?.setAttributedString(string)
        }
    }
}
