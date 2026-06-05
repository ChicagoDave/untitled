//
//  ContentView.swift
//  UntitledApp
//
//  Purpose: The Phase 2 window contents — the read-display editing surface. Hosts
//  the TextKit 2 text view, rendering the document's `displayProjection` through
//  `Attribution`, with Open/Save controls and a status line beneath it. Editing
//  input arrives in Phase 3; for now the surface is read-only.
//  Public interface: `ContentView`.
//  Owner context: UntitledApp — the macOS shell's SwiftUI view layer.
//

import SwiftUI
import UntitledCore

/// The single-window editing surface.
///
/// Binds to a `DocumentModel`, renders its document via `displayProjection` +
/// `Attribution` into a `DocumentTextView`, and exposes Open/Save plus a status
/// line. Read-only in Phase 2.
struct ContentView: View {

    /// The document model driving this window.
    @Bindable var model: DocumentModel

    var body: some View {
        VStack(spacing: 0) {
            DocumentTextView(attributedString: renderedDocument)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 12) {
                Button("Open…") { model.open() }
                Button("Save…") { model.save() }
                Spacer()
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 600, minHeight: 480)
    }

    /// The attributed rendering of the current document — recomputed whenever the
    /// observed `document` changes.
    private var renderedDocument: NSAttributedString {
        Attribution.attributedString(for: model.document.displayProjection())
    }
}
