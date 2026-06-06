//
//  MetadataPanel.swift
//  Galley
//
//  Purpose: The submission-fields side panel — a form over the project's fixed
//  metadata (title-page and cover-letter data every submission needs). Edits bind
//  into `Document.meta` through the current `WorkspaceDocument` buffer and persist
//  on save.
//  Public interface: `MetadataPanel`.
//  Owner context: Galley — the macOS shell's SwiftUI view layer.
//

import SwiftUI
import GalleyCore
import GalleyShell

/// The submission-fields editor: a grouped form bound to the document metadata.
struct MetadataPanel: View {

    @Bindable var buffer: WorkspaceDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Submission Fields")
                .font(.headline)
                .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    group("Title Page") {
                        field("Title", \.title)
                        field("Byline (pen name)", \.author)
                        field("Legal name", \.legalName)
                        field("Word count", \.wordCount)
                    }
                    group("Submission") {
                        field("Genre / category", \.genre)
                        field("Logline", \.logline)
                        field("Bio", \.bio, multiline: true)
                        field("Agent", \.agent)
                    }
                    group("Contact") {
                        field("Email", \.email)
                        field("Phone", \.phone)
                        field("Address", \.address, multiline: true)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// A titled group of fields.
    @ViewBuilder
    private func group(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            content()
        }
    }

    /// A labeled text field bound to a metadata key path; `multiline` grows to a
    /// few lines for bios and addresses.
    @ViewBuilder
    private func field(_ label: String, _ keyPath: WritableKeyPath<Metadata, String>, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if multiline {
                TextField(label, text: buffer.metaBinding(keyPath), axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            } else {
                TextField(label, text: buffer.metaBinding(keyPath))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
        }
    }
}

/// SwiftUI bridge for editing a buffer's metadata fields.
///
/// `WorkspaceDocument` is headless (no SwiftUI), so the two-way `Binding` the form
/// needs is built here in the executable: reads come straight off the document,
/// writes route through the buffer's controlled `setMetadata` mutator.
extension WorkspaceDocument {

    /// A two-way binding to a single string metadata field.
    /// - Parameter keyPath: the metadata field to bind.
    /// - Returns: a `Binding` whose setter persists into `document.meta`.
    func metaBinding(_ keyPath: WritableKeyPath<Metadata, String>) -> Binding<String> {
        Binding(
            get: { self.document.meta[keyPath: keyPath] },
            set: { self.setMetadata(keyPath, to: $0) }
        )
    }
}
