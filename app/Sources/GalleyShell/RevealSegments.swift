//
//  RevealSegments.swift
//  GalleyShell
//
//  Purpose: The model-annotated reveal projection (LT5, ADR-0032) — a pure walk of
//  a `Document` into a flat stream of `RevealSegment`s where every prose-text segment
//  carries its model coordinates (`BlockID` + in-block character offset) and every
//  code chip carries its `CodeID`. This is what the editable Reveal Codes surface
//  (`RevealController`/`RevealLayout`) renders and maps a caret through — the flat
//  `Document.revealProjection() -> [RevealToken]` in GalleyCore loses those
//  coordinates (a `.text` token has no block or offset), so it cannot back a caret.
//  The two projections are kept honest by `RevealSegmentDriftTests`, which asserts
//  the `CodeID` order here matches `revealProjection()`'s.
//  Public interface: `RevealSegment`, `revealSegments(of:)`.
//  Owner context: GalleyShell — the macOS shell's pure presentation layer. No AppKit,
//  so it is testable headless (ADR-0011); GalleyCore stays UI-free (ADR-0002).
//

import GalleyCore

/// One element of the model-annotated reveal stream (ADR-0032).
///
/// Either literal prose text (editable, with model coordinates) or an atomic code
/// chip (non-editable, the caret steps over it as one unit, ADR-0030). A section
/// title also surfaces as a non-editable text segment in LT5-1 (it becomes editable
/// in LT5-2) — annotated with its cut's anchor block so the title can later route to
/// `setCutTitle`.
public struct RevealSegment: Equatable, Sendable {

    public enum Kind: Equatable, Sendable {
        /// Literal prose (or a resolved section title) text.
        case text(String)
        /// A code chip with its display label and addressable identity.
        case code(label: String, id: CodeID)
    }

    public let kind: Kind

    /// The block this segment belongs to, where one applies; `nil` only where no block
    /// is meaningful (it currently always applies, but the field is optional to mirror
    /// `EditorLayout.Segment`).
    public let blockID: BlockID?

    /// For an editable prose segment, the in-block character offset of this segment's
    /// first character (so a caret at reveal-local index *i* maps to model offset
    /// `offset + i`). `nil` for code chips and non-editable text.
    public let offset: Int?

    /// Whether the caret may rest in this segment and edits apply to its block. Code
    /// chips and non-editable text (set-piece lines, section titles in LT5-1) are
    /// `false`; the caret steps over them.
    public let editable: Bool

    public init(kind: Kind, blockID: BlockID?, offset: Int?, editable: Bool) {
        self.kind = kind
        self.blockID = blockID
        self.offset = offset
        self.editable = editable
    }
}

/// Projects a document into the model-annotated reveal stream (ADR-0032).
///
/// Walks the block stream in the same order as `Document.revealProjection()` —
/// interleaving chapter-cut chips, override chips, and `[i]`/`[/i]` italic chips —
/// but annotates every prose-text segment with its `(blockID, offset)` so a reveal
/// caret can be mapped to the model and back. A `[Chapter]` chip is followed by the
/// cut's resolved title as a non-editable text segment (the title is read in LT5-1,
/// edited in LT5-2).
///
/// - Parameter doc: the document.
/// - Returns: the ordered annotated segments. Pure; never mutates, never fails.
public func revealSegments(of doc: Document) -> [RevealSegment] {
    var segments: [RevealSegment] = []

    func code(_ label: String, _ id: CodeID, block: BlockID) {
        segments.append(RevealSegment(kind: .code(label: label, id: id), blockID: block, offset: nil, editable: false))
    }

    func title(_ text: String, cut: BlockID) {
        guard !text.isEmpty else { return }
        segments.append(RevealSegment(kind: .text(text), blockID: cut, offset: nil, editable: false))
    }

    for block in doc.blocks {
        let blockCuts = doc.cuts.filter { $0.blockID == block.id }

        switch block.content {
        case .paragraph(let runs):
            for cut in blockCuts where cut.offsetInBlock == nil {
                code(sectionLabel(cut.role), .chapter(block.id, nil), block: block.id)
                title(doc.resolvedTitle(forCutAt: block.id), cut: block.id)
                // The chapter-opener spacing between the heading and the body (ADR-0035).
                code("sp", .sectionSpace(block.id), block: block.id)
            }
            for (index, override) in block.overrides.enumerated() {
                code(overrideLabel(override), .override(block.id, index), block: block.id)
            }
            segments.append(contentsOf: paragraphSegments(runs, blockID: block.id, cuts: blockCuts, doc: doc))
            // The paragraph's hard return — a visible block boundary (ADR-0035).
            code("p", .paragraph(block.id), block: block.id)

        case .sceneBreak:
            emitStartCuts(blockCuts, doc: doc, block: block.id, code: code, title: title)
            code("SceneBreak", .sceneBreak(block.id), block: block.id)

        case .setPiece(let kind, let lines):
            emitStartCuts(blockCuts, doc: doc, block: block.id, code: code, title: title)
            for (index, override) in block.overrides.enumerated() {
                code(overrideLabel(override), .override(block.id, index), block: block.id)
            }
            let label = setPieceLabel(kind)
            code(label, .setPieceOpen(block.id), block: block.id)
            var span = 0
            for (lineIndex, line) in lines.enumerated() {
                span = appendLineSegments(line, blockID: block.id, spanStart: span, into: &segments)
                code("line", .line(block.id, lineIndex), block: block.id)
            }
            code("/" + label, .setPieceClose(block.id), block: block.id)

        case .figure(let imageRef, _):
            emitStartCuts(blockCuts, doc: doc, block: block.id, code: code, title: title)
            code("figure: \(imageRef)", .figure(block.id), block: block.id)
        }
    }

    return segments
}

// MARK: - Walk helpers (mirror GalleyCore/Reveal.swift; drift-guarded by tests)

/// Emits a `[Chapter]` chip (plus resolved title) for every cut on a non-paragraph
/// block — in-block offsets are undefined there, so the cut surfaces at the boundary.
private func emitStartCuts(
    _ blockCuts: [ChapterCut], doc: Document, block: BlockID,
    code: (String, CodeID, BlockID) -> Void, title: (String, BlockID) -> Void
) {
    for cut in blockCuts {
        code(sectionLabel(cut.role), .chapter(block, cut.offsetInBlock), block)
        title(doc.resolvedTitle(forCutAt: block), block)
    }
}

/// Builds annotated segments for a paragraph, interleaving `[i]`/`[/i]` chips around
/// explicit italic runs and `[Chapter]` chips at in-block cut offsets — the exact
/// marker ordering of `Reveal.swift`'s `paragraphTokens`, with each text run carrying
/// its in-block start offset.
private func paragraphSegments(_ runs: [Run], blockID: BlockID, cuts: [ChapterCut], doc: Document) -> [RevealSegment] {
    let text = runs.map(\.text).joined()
    let characters = Array(text)
    let length = characters.count

    var markers: [(offset: Int, order: Int, segment: RevealSegment)] = []

    var position = 0
    var span = 0
    for run in runs where !run.text.isEmpty {
        let runLength = run.text.count
        if run.italic {
            markers.append((position, 2, RevealSegment(kind: .code(label: "i", id: .italicOpen(blockID, span)), blockID: blockID, offset: nil, editable: false)))
            markers.append((position + runLength, 0, RevealSegment(kind: .code(label: "/i", id: .italicClose(blockID, span)), blockID: blockID, offset: nil, editable: false)))
            span += 1
        }
        position += runLength
    }

    for cut in cuts where cut.offsetInBlock != nil {
        let clamped = min(max(cut.offsetInBlock ?? 0, 0), length)
        markers.append((clamped, 1, RevealSegment(kind: .code(label: sectionLabel(cut.role), id: .chapter(blockID, clamped)), blockID: blockID, offset: nil, editable: false)))
    }

    markers.sort { ($0.offset, $0.order) < ($1.offset, $1.order) }

    var segments: [RevealSegment] = []
    var cursor = 0
    func emitText(from: Int, to: Int) {
        guard to > from else { return }
        let slice = String(characters[from..<to])
        segments.append(RevealSegment(kind: .text(slice), blockID: blockID, offset: from, editable: true))
    }
    for marker in markers {
        if marker.offset > cursor {
            emitText(from: cursor, to: marker.offset)
            cursor = marker.offset
        }
        segments.append(marker.segment)
    }
    if cursor < length {
        emitText(from: cursor, to: length)
    }
    // A wholly empty paragraph still needs an editable landing spot for the caret.
    if length == 0 {
        segments.append(RevealSegment(kind: .text(""), blockID: blockID, offset: 0, editable: true))
    }
    return segments
}

/// Appends a set-piece line's run text as non-editable text segments, bracketing each
/// explicit italic run in `[i]`/`[/i]`. Set-piece lines are not inline-editable in
/// LT5-1 (matching the prose editor); they render so the writer can read them. Returns
/// the next italic-span index so a block's spans stay uniquely numbered across lines.
private func appendLineSegments(_ runs: [Run], blockID: BlockID, spanStart: Int, into segments: inout [RevealSegment]) -> Int {
    var span = spanStart
    for run in runs where !run.text.isEmpty {
        if run.italic {
            segments.append(RevealSegment(kind: .code(label: "i", id: .italicOpen(blockID, span)), blockID: blockID, offset: nil, editable: false))
            segments.append(RevealSegment(kind: .text(run.text), blockID: blockID, offset: nil, editable: false))
            segments.append(RevealSegment(kind: .code(label: "/i", id: .italicClose(blockID, span)), blockID: blockID, offset: nil, editable: false))
            span += 1
        } else {
            segments.append(RevealSegment(kind: .text(run.text), blockID: blockID, offset: nil, editable: false))
        }
    }
    return span
}

/// The reveal chip label for a presentation override (mirrors `Reveal.swift`).
private func overrideLabel(_ override: PresentationOverride) -> String {
    switch override {
    case .smallCaps: return "smallCaps"
    case .blockQuote: return "quote"
    case .alignment(.leading): return "left"
    case .alignment(.center): return "center"
    case .alignment(.trailing): return "right"
    }
}

/// The reveal chip label for a section cut, by its role (mirrors `Reveal.swift`).
private func sectionLabel(_ role: SectionRole) -> String {
    switch role {
    case .chapter: return "Chapter"
    case .prologue: return "Prologue"
    case .epilogue: return "Epilogue"
    case .dedication: return "Dedication"
    }
}

/// The reveal label for a set-piece kind (mirrors `Reveal.swift`).
private func setPieceLabel(_ kind: SetPieceKind) -> String {
    switch kind {
    case .verse: return "Verse"
    case .epigraph: return "Epigraph"
    case .letter: return "Letter"
    }
}
