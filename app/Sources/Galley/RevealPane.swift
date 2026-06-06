//
//  RevealPane.swift
//  Galley
//
//  Purpose: The reveal pane (§5, ADR-0006) — the truth view that renders the
//  `revealProjection` token stream as prose segments and addressable code chips,
//  and doubles as the chapter-slicing surface (ADR-0005). In chapter-edit mode it
//  exposes the chapter anchors so the writer can place, retitle, and remove
//  boundary cuts; the edits flow through `WorkspaceDocument` into the buffer.
//  Public interface: `RevealPane`.
//  Owner context: Galley — the macOS shell's SwiftUI view layer.
//

import SwiftUI
import GalleyCore
import GalleyShell

/// The reveal pane: a token-stream truth view plus a chapter-slicing editor.
struct RevealPane: View {

    @Bindable var buffer: WorkspaceDocument
    @State private var chapterEditMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reveal").font(.headline)
                Spacer()
                Button(chapterEditMode ? "Done" : "Edit Chapters") { chapterEditMode.toggle() }
                    .controlSize(.small)
            }

            Divider()

            ScrollView {
                FlowLayout {
                    ForEach(revealItems(from: buffer.document.revealProjection())) { item in
                        RevealItemView(item: item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if chapterEditMode {
                Divider()
                ChapterEditor(buffer: buffer)
            }
        }
        .padding(12)
        .frame(minWidth: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// One reveal item: prose text, or a colored code chip.
private struct RevealItemView: View {

    let item: RevealItem

    var body: some View {
        switch item.kind {
        case .text(let string):
            Text(string).font(.system(.body, design: .serif))
        case .chip(let label, let code):
            Text(label)
                .font(.caption2.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(color(for: code)))
                .foregroundStyle(.white)
        }
    }

    /// Chapter chips read as the structural surface; other codes are muted.
    private func color(for code: CodeID) -> Color {
        switch code {
        case .chapter: return .accentColor
        case .sceneBreak: return .orange
        case .setPieceOpen, .setPieceClose: return .purple
        case .line: return .gray
        case .italicOpen, .italicClose: return .secondary
        }
    }
}

/// The chapter-slicing editor: one row per block, with a toggle to place/remove a
/// boundary cut and a field to title it (§6).
private struct ChapterEditor: View {

    @Bindable var buffer: WorkspaceDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chapters").font(.subheadline.bold())
            Text("Toggle a block to begin a chapter there.")
                .font(.caption).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(chapterAnchors(of: buffer.document)) { anchor in
                        ChapterAnchorRow(buffer: buffer, anchor: anchor)
                    }
                }
            }
            .frame(maxHeight: 180)
        }
    }
}

/// A single chapter-anchor row: cut toggle, optional title field, block preview.
private struct ChapterAnchorRow: View {

    @Bindable var buffer: WorkspaceDocument
    let anchor: ChapterAnchor

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { anchor.hasCut },
                set: { isOn in
                    if isOn { buffer.placeCut(atBlock: anchor.id) }
                    else { buffer.removeCut(atBlock: anchor.id) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            if anchor.hasCut {
                TextField("title", text: Binding(
                    get: { anchor.title ?? "" },
                    set: { buffer.setCutTitle(atBlock: anchor.id, to: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
            }

            Text(anchor.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }
}
