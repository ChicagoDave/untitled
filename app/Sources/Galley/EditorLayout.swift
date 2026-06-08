//
//  EditorLayout.swift
//  Galley
//
//  Purpose: The caret ↔ model bridge for the editable surface. Walks the block
//  stream and builds the `NSAttributedString` (via `Attribution`) while recording,
//  per piece, which `BlockID` it came from and the text-view character range it
//  occupies — so the input layer can map a caret to a model `(blockID, offset)`
//  and back after a re-render (§8, ADR-0003).
//  Public interface: `EditorLayout.build(from:)`, `modelPosition(forCharacterAt:)`,
//  `characterPosition(forBlock:offset:)`, `firstEditablePosition()`.
//  Owner context: Galley — the macOS shell's editing layer.
//
//  Note: offsets are converted between the model's Character counts and the text
//  view's UTF-16 positions via the live string, so multi-unit characters map
//  correctly. Set-pieces render but are not inline-editable in Phase 3 (toggle a
//  paragraph to verse to create one; toggle back to edit it).
//

import AppKit
import GalleyCore

struct EditorLayout {

    /// One contiguous run of the rendered string and what it maps to.
    struct Segment {
        /// Range in the attributed string. For an editable segment this excludes
        /// the trailing paragraph newline, so the caret at the range's end is the
        /// end of the block.
        let utf16Range: NSRange
        /// The block this segment renders, or `nil` for pure decoration
        /// (chapter headings).
        let blockID: BlockID?
        /// Whether the caret may sit in this segment and edits apply to its block.
        let editable: Bool
        /// The block's plain text (or, for a title segment, the raw title text), for
        /// Character ↔ UTF-16 offset conversion. Empty for non-editable segments.
        let text: String
        /// When this segment is an editable chapter *title*, the anchor block of the
        /// cut it titles; `nil` for prose segments and non-edited headings (LT3).
        let titleCutBlockID: BlockID?
        /// When this segment belongs to a *figure* (LT4-2) — its non-editable box or
        /// its editable caption — the figure block's ID; `nil` for everything else.
        /// Distinguishes a figure's box (non-editable + this set) from a scene break
        /// (non-editable + this `nil`), and routes caption edits to the figure block.
        let figureBlockID: BlockID?
    }

    let attributedString: NSAttributedString
    let segments: [Segment]

    /// Builds the editable layout for a document.
    ///
    /// - Parameters:
    ///   - doc: the document to render.
    ///   - editingTitleCut: the anchor block of the cut whose heading is currently
    ///     being edited, if any. That heading renders as an editable segment showing
    ///     the *raw* title (macros visible); every other heading is non-editable and
    ///     shows the *resolved* title (spreadsheet rule, ADR-0026/LT3).
    ///   - confirmingDeleteCut: the anchor block of the cut whose break is awaiting a
    ///     Y/N delete confirmation; that heading renders the confirm prompt (LT3).
    static func build(from doc: Document, editingTitleCut: BlockID? = nil, confirmingDeleteCut: BlockID? = nil) -> EditorLayout {
        let out = NSMutableAttributedString()
        var segments: [Segment] = []

        func append(_ piece: NSAttributedString, blockID: BlockID?, editable: Bool, text: String, titleCutBlockID: BlockID? = nil, figureBlockID: BlockID? = nil) {
            let start = out.length
            out.append(piece)
            // The piece ends with a paragraph newline; the editable region excludes it.
            let length = editable ? max(0, piece.length - 1) : piece.length
            segments.append(Segment(
                utf16Range: NSRange(location: start, length: length),
                blockID: blockID, editable: editable, text: text,
                titleCutBlockID: titleCutBlockID, figureBlockID: figureBlockID
            ))
        }

        func spans(_ runs: [Run]) -> [DisplaySpan] {
            runs.filter { !$0.text.isEmpty }.map { DisplaySpan(text: $0.text, italic: $0.italic) }
        }

        for block in doc.blocks {
            for cut in doc.cuts where cut.blockID == block.id && cut.offsetInBlock == nil {
                if cut.blockID == confirmingDeleteCut {
                    // Awaiting Y/N: the heading becomes the delete-confirmation prompt,
                    // non-editable (the caret stays in the prose below it) (LT3).
                    append(Attribution.deletePrompt(title: doc.resolvedTitle(forCutAt: cut.blockID)),
                           blockID: nil, editable: false, text: "")
                    continue
                }
                // Only the heading being edited (clicked into) is an editable segment,
                // showing the *raw* title (macros visible); every other heading is
                // non-editable and shows the *resolved* heading (numbering rendered) —
                // so arrow keys glide past breaks and the caret never rests in one
                // (LT3). All headings keep `titleCutBlockID` for click hit-testing and
                // arrow-skip.
                let isEditing = cut.blockID == editingTitleCut
                let display = isEditing ? (cut.title ?? "") : doc.resolvedTitle(forCutAt: cut.blockID)
                append(Attribution.attributedString(for: [.chapterStart(role: cut.role, title: display)]),
                       blockID: nil, editable: isEditing, text: isEditing ? display : "", titleCutBlockID: cut.blockID)
            }

            switch block.content {
            case .paragraph(let runs):
                let piece = Attribution.attributedString(for: [.paragraph(spans: spans(runs), overrides: block.overrides)])
                append(piece, blockID: block.id, editable: true, text: runs.map(\.text).joined())

            case .sceneBreak:
                append(Attribution.attributedString(for: [.sceneBreak]), blockID: block.id, editable: false, text: "")

            case .setPiece(let kind, let lines):
                for line in lines {
                    append(Attribution.attributedString(for: [.setPieceLine(kind: kind, spans: spans(line), overrides: block.overrides)]),
                           blockID: block.id, editable: false, text: "")
                }

            case .figure(let imageRef, let caption):
                // Two segments (LT4-2, ADR-0028 Option A): the placeholder box is a
                // non-editable boundary (the caret never rests in it, like a scene
                // break); the caption below is editable, routed to the figure block via
                // `figureBlockID` (mirrors how a title routes via `titleCutBlockID`).
                // Both carry `figureBlockID` so the box is distinguishable from a scene
                // break for arrow-glide.
                append(Attribution.figureBox(imageRef: imageRef),
                       blockID: block.id, editable: false, text: "", figureBlockID: block.id)
                append(Attribution.figureCaption(caption),
                       blockID: nil, editable: true, text: caption, figureBlockID: block.id)
            }
        }

        return EditorLayout(attributedString: out, segments: segments)
    }

    /// Maps a text-view character position to a model `(blockID, offset)`, or `nil`
    /// if it falls in non-editable decoration.
    ///
    /// A position past the end of all editable text — e.g. a click in the empty
    /// area below the last block — clamps to the end of the last editable block, so
    /// the caret always lands somewhere typeable rather than in dead space.
    func modelPosition(forCharacterAt position: Int) -> (blockID: BlockID, offset: Int)? {
        let nsString = attributedString.string as NSString
        for segment in segments where segment.editable {
            guard let id = segment.blockID else { continue }
            let lower = segment.utf16Range.location
            let upper = lower + segment.utf16Range.length
            if position >= lower && position <= upper {
                let prefix = nsString.substring(with: NSRange(location: lower, length: position - lower))
                return (id, prefix.count)
            }
        }

        // Past the end of the document text: clamp to the end of the last editable
        // block so a click below the last block is still typeable.
        if let last = segments.last(where: { $0.editable && $0.blockID != nil }),
           let id = last.blockID,
           position > last.utf16Range.location + last.utf16Range.length {
            return (id, last.text.count)
        }
        return nil
    }

    /// Whether `position` falls past the end of all editable text — i.e. a click in
    /// the empty area below the last block, rather than within or before the text.
    func isPastDocumentEnd(_ position: Int) -> Bool {
        guard let last = segments.last(where: { $0.editable && $0.blockID != nil }) else { return false }
        return position > last.utf16Range.location + last.utf16Range.length
    }

    /// Maps a model `(blockID, offset)` to a text-view character position, or `nil`
    /// if the block is not present as an editable segment.
    func characterPosition(forBlock blockID: BlockID, offset: Int) -> Int? {
        guard let segment = segments.first(where: { $0.editable && $0.blockID == blockID }) else { return nil }
        let characters = Array(segment.text)
        let clamped = min(max(offset, 0), characters.count)
        let prefix = String(characters[0..<clamped]) as NSString
        return segment.utf16Range.location + prefix.length
    }

    /// The caret position at the start of the first editable block, if any.
    func firstEditablePosition() -> (blockID: BlockID, offset: Int)? {
        guard let segment = segments.first(where: { $0.editable && $0.blockID != nil }), let id = segment.blockID else { return nil }
        return (id, 0)
    }

    // MARK: Chapter-title segments (LT3)

    /// Maps a text-view character position to a `(cutBlockID, offset)` inside an
    /// editable chapter-title segment, or `nil` if the position is not in one.
    func titlePosition(forCharacterAt position: Int) -> (cutBlockID: BlockID, offset: Int)? {
        let nsString = attributedString.string as NSString
        for segment in segments where segment.editable && segment.titleCutBlockID != nil {
            let lower = segment.utf16Range.location
            let upper = lower + segment.utf16Range.length
            if position >= lower && position <= upper {
                let prefix = nsString.substring(with: NSRange(location: lower, length: position - lower))
                return (segment.titleCutBlockID!, prefix.count)
            }
        }
        return nil
    }

    /// Maps a `(cutBlockID, offset)` in a chapter title to a text-view character
    /// position, or `nil` if that title is not present as an editable segment.
    func characterPosition(forTitleCut cutBlockID: BlockID, offset: Int) -> Int? {
        guard let segment = segments.first(where: { $0.editable && $0.titleCutBlockID == cutBlockID }) else { return nil }
        let characters = Array(segment.text)
        let clamped = min(max(offset, 0), characters.count)
        let prefix = String(characters[0..<clamped]) as NSString
        return segment.utf16Range.location + prefix.length
    }

    /// The end-of-title caret position for an editable title, for entering edit mode.
    func endOfTitle(cutBlockID: BlockID) -> Int? {
        guard let segment = segments.first(where: { $0.editable && $0.titleCutBlockID == cutBlockID }) else { return nil }
        return segment.utf16Range.location + segment.utf16Range.length
    }

    /// The cut whose heading segment (editable or not) covers `position`, for
    /// arrow-glide and exit hit-testing.
    ///
    /// A non-edited heading **releases its end boundary** to the prose that follows:
    /// the chapter's first prose character sits exactly at the heading segment's upper
    /// edge, and a click there must stay in the prose, not read as "on the heading"
    /// (which would glide the caret backward to the previous section). An *edited*
    /// title keeps its end caret inclusive, so editing at the end of the title works.
    func headingCut(forCharacterAt position: Int) -> BlockID? {
        for segment in segments where segment.titleCutBlockID != nil {
            let lower = segment.utf16Range.location
            let upper = lower + segment.utf16Range.length
            guard position >= lower else { continue }
            if position < upper || (segment.editable && position == upper) {
                return segment.titleCutBlockID
            }
        }
        return nil
    }

    // MARK: Figure caption segments (LT4-2)

    /// Maps a text-view character position to a `(figureBlockID, offset)` inside an
    /// editable figure-caption segment, or `nil` if the position is not in one.
    func captionPosition(forCharacterAt position: Int) -> (figureBlockID: BlockID, offset: Int)? {
        let nsString = attributedString.string as NSString
        for segment in segments where segment.editable && segment.figureBlockID != nil {
            let lower = segment.utf16Range.location
            let upper = lower + segment.utf16Range.length
            if position >= lower && position <= upper {
                let prefix = nsString.substring(with: NSRange(location: lower, length: position - lower))
                return (segment.figureBlockID!, prefix.count)
            }
        }
        return nil
    }

    /// Maps a `(figureBlockID, offset)` in a figure caption to a text-view character
    /// position, or `nil` if that caption is not present as an editable segment.
    func characterPosition(forCaptionBlock figureBlockID: BlockID, offset: Int) -> Int? {
        guard let segment = segments.first(where: { $0.editable && $0.figureBlockID == figureBlockID }) else { return nil }
        let characters = Array(segment.text)
        let clamped = min(max(offset, 0), characters.count)
        let prefix = String(characters[0..<clamped]) as NSString
        return segment.utf16Range.location + prefix.length
    }

    /// The figure block whose *non-editable box* segment covers `position`, or `nil`.
    /// Lets the input layer glide the caret off the box onto the editable caption
    /// (the box is identified by a set `figureBlockID` while being non-editable —
    /// a scene break has neither).
    func figureBoxBlockID(forCharacterAt position: Int) -> BlockID? {
        for segment in segments where !segment.editable && segment.figureBlockID != nil {
            let lower = segment.utf16Range.location
            let upper = lower + segment.utf16Range.length
            if position >= lower && position <= upper { return segment.figureBlockID }
        }
        return nil
    }
}
