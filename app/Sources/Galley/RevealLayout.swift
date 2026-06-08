//
//  RevealLayout.swift
//  Galley
//
//  Purpose: The caret ↔ model bridge for the Reveal Codes surface (LT5, ADR-0032) —
//  the reveal analogue of `EditorLayout`. Renders the model-annotated reveal stream
//  (`revealSegments(of:)`) into an `NSAttributedString` where prose reads as prose and
//  every code surfaces as an atomic bracketed chip, while recording, per piece, the
//  model `(blockID, offset)` it came from and the character range it occupies — so the
//  shared caret (ADR-0033) can be rendered into reveal coordinates and a reveal caret
//  mapped back to the model.
//  Public interface: `RevealLayout.build(from:)`, `modelPosition(forCharacterAt:)`,
//  `characterRange(for:)`, `firstEditablePosition()`, `isCodeAt(_:)`.
//  Owner context: Galley — the macOS shell's editing layer (ADR-0003).
//

import AppKit
import GalleyCore
import GalleyShell

struct RevealLayout {

    /// One contiguous run of the rendered reveal string and what it maps to.
    struct Segment {
        /// Range in the attributed string.
        let utf16Range: NSRange
        /// The block this piece renders, or `nil` for pure decoration (separators).
        let blockID: BlockID?
        /// For an editable prose piece, the in-block character offset of its first
        /// character; `nil` for code chips, non-editable text, and separators.
        let modelOffset: Int?
        /// Whether the caret may rest in this piece (editable prose only). Code chips
        /// and non-editable text are `false` — the caret steps over them.
        let editable: Bool
        /// Whether this piece is an atomic code chip (for step-over navigation).
        let isCode: Bool
        /// The addressable identity of a code chip, for the code→event mapping
        /// (LT5-2, ADR-0034); `nil` for text pieces.
        let codeID: CodeID?
        /// The piece's text, for Character ↔ UTF-16 offset conversion.
        let text: String
    }

    let attributedString: NSAttributedString
    let segments: [Segment]

    /// Builds the reveal layout for a document.
    ///
    /// Inserts a newline between blocks (where consecutive segments' `blockID` differs)
    /// so the stream reads line-by-line; the separators are decoration, not segments,
    /// so they never map to a model position.
    static func build(from doc: Document) -> RevealLayout {
        let revealSegs = revealSegments(of: doc)
        let out = NSMutableAttributedString()
        var segments: [Segment] = []
        var previousBlock: BlockID??  = nil   // double-optional: "no previous" vs "previous was nil"

        for seg in revealSegs {
            if let prev = previousBlock, prev != seg.blockID {
                out.append(NSAttributedString(string: "\n", attributes: Self.proseAttributes))
            }
            previousBlock = seg.blockID

            let start = out.length
            switch seg.kind {
            case .text(let string):
                out.append(NSAttributedString(string: string, attributes: seg.editable ? Self.proseAttributes : Self.titleAttributes))
                segments.append(Segment(
                    utf16Range: NSRange(location: start, length: out.length - start),
                    blockID: seg.blockID, modelOffset: seg.offset, editable: seg.editable,
                    isCode: false, codeID: nil, text: string
                ))
            case .code(let label, let id):
                let chip = "[\(label)]"
                out.append(NSAttributedString(string: chip, attributes: Self.codeAttributes))
                segments.append(Segment(
                    utf16Range: NSRange(location: start, length: out.length - start),
                    blockID: seg.blockID, modelOffset: nil, editable: false,
                    isCode: true, codeID: id, text: chip
                ))
            }
        }

        return RevealLayout(attributedString: out, segments: segments)
    }

    // MARK: Attributes

    private static var proseAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
         .foregroundColor: NSColor.textColor]
    }

    private static var titleAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
         .foregroundColor: NSColor.secondaryLabelColor]
    }

    private static var codeAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
         .foregroundColor: NSColor.white,
         .backgroundColor: NSColor.systemTeal.withAlphaComponent(0.85)]
    }

    // MARK: Mapping

    /// Maps a reveal character position to a model `(blockID, offset)`, or `nil` if it
    /// falls in a code chip, non-editable text, or a separator.
    func modelPosition(forCharacterAt position: Int) -> (blockID: BlockID, offset: Int)? {
        let nsString = attributedString.string as NSString
        for segment in segments where segment.editable {
            guard let id = segment.blockID, let base = segment.modelOffset else { continue }
            let lower = segment.utf16Range.location
            let upper = lower + segment.utf16Range.length
            if position >= lower && position <= upper {
                let prefix = nsString.substring(with: NSRange(location: lower, length: position - lower))
                return (id, base + prefix.count)
            }
        }
        return nil
    }

    /// Maps the shared model `Caret` to a reveal character range (collapsed when the
    /// caret is), or `nil` if neither end maps to an editable reveal position.
    func characterRange(for caret: Caret) -> NSRange? {
        guard let lower = characterPosition(forBlock: caret.start.blockID, offset: caret.start.offset),
              let upper = characterPosition(forBlock: caret.end.blockID, offset: caret.end.offset) else { return nil }
        return NSRange(location: min(lower, upper), length: abs(upper - lower))
    }

    /// Maps a model `(blockID, offset)` to a reveal character position, or `nil` if the
    /// block has no editable reveal segment covering that offset.
    func characterPosition(forBlock blockID: BlockID, offset: Int) -> Int? {
        let candidates = segments.filter { $0.editable && $0.blockID == blockID && $0.modelOffset != nil }
        for segment in candidates {
            let base = segment.modelOffset!
            let end = base + segment.text.count
            if offset >= base && offset <= end {
                let local = offset - base
                let prefix = String(Array(segment.text)[0..<local]) as NSString
                return segment.utf16Range.location + prefix.length
            }
        }
        // Past every segment of the block: clamp to the end of its last editable piece.
        if let last = candidates.last {
            return last.utf16Range.location + last.utf16Range.length
        }
        return nil
    }

    /// The caret position at the start of the first editable reveal segment, if any.
    func firstEditablePosition() -> (blockID: BlockID, offset: Int)? {
        guard let segment = segments.first(where: { $0.editable && $0.blockID != nil && $0.modelOffset != nil }),
              let id = segment.blockID, let base = segment.modelOffset else { return nil }
        return (id, base)
    }

    /// The code-chip segment whose range covers `position`, if any — so the caret can
    /// be snapped off it (a code is stepped over as one unit, ADR-0030).
    func codeSegment(forCharacterAt position: Int) -> Segment? {
        segments.first { segment in
            guard segment.isCode else { return false }
            let lower = segment.utf16Range.location
            let upper = lower + segment.utf16Range.length
            return position > lower && position < upper   // strictly inside the chip
        }
    }

    /// The code chip immediately *before* `position` (its trailing edge is at
    /// `position`) — the chip a Backspace at `position` deletes (LT5-2, ADR-0034).
    func codeEndingAt(_ position: Int) -> Segment? {
        segments.first { $0.isCode && $0.utf16Range.location + $0.utf16Range.length == position }
    }

    /// The code chip immediately *after* `position` (its leading edge is at
    /// `position`) — the chip a forward Delete at `position` deletes (LT5-2).
    func codeStartingAt(_ position: Int) -> Segment? {
        segments.first { $0.isCode && $0.utf16Range.location == position }
    }
}
