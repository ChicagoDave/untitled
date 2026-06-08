//
//  RevealRendering.swift
//  GalleyShell
//
//  Purpose: The pure view-model layer for the reveal pane (§5, ADR-0006) — maps
//  the core's `[RevealToken]` stream into identifiable items the SwiftUI flow
//  layout renders, and lists the chapter anchors (candidate cut points) the
//  chapter-slicing mode offers. No AppKit, so both are testable headless.
//  Public interface: `RevealItem`, `revealItems(from:)`, `ChapterAnchor`,
//  `chapterAnchors(of:)`.
//  Owner context: GalleyShell — the macOS shell's pure presentation layer.
//

import GalleyCore

/// One rendered element of the reveal stream, with a stable identity for SwiftUI.
public struct RevealItem: Identifiable, Equatable, Sendable {

    /// Stream position; stable for a given projection so `ForEach` can diff.
    public let id: Int

    /// Whether this item is literal prose or an addressable code chip.
    public let kind: Kind

    public enum Kind: Equatable, Sendable {
        /// Literal prose text.
        case text(String)
        /// A code chip with its display label and the model element it addresses.
        case chip(label: String, code: CodeID)
    }

    public init(id: Int, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

/// Maps a reveal token stream into identifiable items (§5).
///
/// - Parameter tokens: the stream from `Document.revealProjection()`.
/// - Returns: one `RevealItem` per token, indexed by position.
public func revealItems(from tokens: [RevealToken]) -> [RevealItem] {
    tokens.enumerated().map { index, token in
        switch token {
        case .text(let string):
            return RevealItem(id: index, kind: .text(string))
        case .code(let label, let id):
            return RevealItem(id: index, kind: .chip(label: label, code: id))
        }
    }
}

/// A candidate chapter-cut point: the start of a block, with a short preview and
/// whether a boundary cut currently sits there (§6).
public struct ChapterAnchor: Identifiable, Equatable, Sendable {

    /// The block this anchor begins at — also the identity.
    public let id: BlockID

    /// A short human-readable preview of the block, for the chapter-slicing UI.
    public let label: String

    /// Whether a boundary chapter cut is currently anchored here.
    public let hasCut: Bool

    /// The anchored cut's title, if it has one.
    public let title: String?

    public init(id: BlockID, label: String, hasCut: Bool, title: String?) {
        self.id = id
        self.label = label
        self.hasCut = hasCut
        self.title = title
    }
}

/// Lists the chapter anchors for a document — one per block, in stream order (§6).
///
/// - Parameter doc: the document.
/// - Returns: an anchor per block, marked with whether a boundary cut sits there.
public func chapterAnchors(of doc: Document) -> [ChapterAnchor] {
    doc.blocks.map { block in
        let cut = doc.cuts.first { $0.blockID == block.id && $0.offsetInBlock == nil }
        return ChapterAnchor(
            id: block.id,
            label: previewLabel(block.content),
            hasCut: cut != nil,
            title: cut?.title
        )
    }
}

/// A short preview of a block's content for the chapter-slicing list.
private func previewLabel(_ content: BlockContent) -> String {
    switch content {
    case .paragraph(let runs):
        let text = runs.map(\.text).joined()
        let trimmed = text.prefix(40)
        return trimmed.isEmpty ? "(empty paragraph)" : String(trimmed) + (text.count > 40 ? "…" : "")
    case .sceneBreak:
        return "* * *"
    case .setPiece(let kind, _):
        switch kind {
        case .verse: return "[Verse]"
        case .epigraph: return "[Epigraph]"
        case .letter: return "[Letter]"
        }
    case .figure(let imageRef, _):
        return imageRef.isEmpty ? "[figure]" : "[figure: \(imageRef)]"
    }
}
