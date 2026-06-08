//
//  Display.swift
//  GalleyCore
//
//  Purpose: `displayProjection` — the pure render of a `Document` into the clean
//  reading stream (§5, ADR-0006), the companion to `revealProjection`. Walks the
//  block stream, splicing chapter cuts as reading-order `chapterStart` boundaries
//  (ADR-0005): a boundary cut opens a chapter before its block; a mid-paragraph
//  cut splits the paragraph at the cut offset.
//  Public interface: `displayProjection(_:)`.
//  Owner context: GalleyCore — UI-free Swift, the model-as-truth (ADR-0004).
//

extension Document {

    /// Projects the document into the clean display token stream (§5).
    ///
    /// Walks the blocks in order. Cuts anchored to a paragraph with an in-block
    /// offset split that paragraph: the text up to the offset closes the prior
    /// chapter, then a `chapterStart` opens the next. Cuts without an offset, or
    /// anchored to a non-paragraph block, open a chapter at the block boundary
    /// (in-block offsets are undefined for scene breaks and set-pieces in v1).
    ///
    /// - Returns: the ordered `DisplayToken`s the reading view would render. Pure;
    ///   never mutates and never fails. Empty paragraph segments are dropped, so a
    ///   cut at offset 0 yields only a `chapterStart`, not a blank paragraph.
    public func displayProjection() -> [DisplayToken] {
        var tokens: [DisplayToken] = []

        for block in blocks {
            let blockCuts = cuts.filter { $0.blockID == block.id }

            switch block.content {
            case .paragraph(let runs):
                appendParagraphTokens(runs, overrides: block.overrides, cuts: blockCuts, into: &tokens)

            case .sceneBreak:
                emitBoundaryChapters(blockCuts, into: &tokens)
                tokens.append(.sceneBreak)

            case .setPiece(let kind, let lines):
                emitBoundaryChapters(blockCuts, into: &tokens)
                for line in lines {
                    tokens.append(.setPieceLine(kind: kind, spans: spans(from: line), overrides: block.overrides))
                }

            case .figure(let imageRef, let caption):
                emitBoundaryChapters(blockCuts, into: &tokens)
                tokens.append(.figure(imageRef: imageRef, caption: caption))
            }
        }

        return tokens
    }

    /// Emits a `chapterStart` for every cut anchored to a non-paragraph block, at
    /// the block boundary (offsets are undefined there in v1).
    private func emitBoundaryChapters(_ blockCuts: [ChapterCut], into tokens: inout [DisplayToken]) {
        for cut in blockCuts {
            tokens.append(.chapterStart(role: cut.role, title: cut.title))
        }
    }

    /// Appends the display tokens for one paragraph, splicing chapter boundaries.
    ///
    /// Boundary cuts (no offset) open a chapter before the paragraph; offset cuts
    /// split the paragraph's spans at each offset, opening a chapter between the
    /// segments. Empty segments (e.g. an offset-0 cut) are dropped.
    private func appendParagraphTokens(
        _ runs: [Run],
        overrides: [PresentationOverride],
        cuts: [ChapterCut],
        into tokens: inout [DisplayToken]
    ) {
        for cut in cuts where cut.offsetInBlock == nil {
            tokens.append(.chapterStart(role: cut.role, title: cut.title))
        }

        let allSpans = spans(from: runs)
        let total = allSpans.reduce(0) { $0 + $1.text.count }

        let offsetCuts = cuts
            .compactMap { cut -> (offset: Int, role: SectionRole, title: String?)? in
                guard let offset = cut.offsetInBlock else { return nil }
                return (min(max(offset, 0), total), cut.role, cut.title)
            }
            .sorted { $0.offset < $1.offset }

        func appendParagraph(_ segment: [DisplaySpan]) {
            guard !segment.isEmpty else { return }
            tokens.append(.paragraph(spans: segment, overrides: overrides))
        }

        var remaining = allSpans
        var consumed = 0
        for cut in offsetCuts {
            let take = cut.offset - consumed
            let (head, tail) = splitSpans(remaining, at: take)
            appendParagraph(head)
            tokens.append(.chapterStart(role: cut.role, title: cut.title))
            remaining = tail
            consumed = cut.offset
        }
        appendParagraph(remaining)
    }

    /// Maps a run sequence to display spans, dropping empty runs.
    private func spans(from runs: [Run]) -> [DisplaySpan] {
        runs
            .filter { !$0.text.isEmpty }
            .map { DisplaySpan(text: $0.text, italic: $0.italic) }
    }

    /// Splits a span sequence at character offset `n` into `(head, tail)`.
    ///
    /// The span straddling the offset is divided, preserving its italic mark on
    /// both sides. `n <= 0` puts everything in `tail`; `n` beyond the total length
    /// puts everything in `head`.
    private func splitSpans(_ spans: [DisplaySpan], at n: Int) -> (head: [DisplaySpan], tail: [DisplaySpan]) {
        guard n > 0 else { return ([], spans) }

        var head: [DisplaySpan] = []
        var tail: [DisplaySpan] = []
        var remaining = n

        for span in spans {
            if remaining <= 0 {
                tail.append(span)
            } else if span.text.count <= remaining {
                head.append(span)
                remaining -= span.text.count
            } else {
                let cut = span.text.index(span.text.startIndex, offsetBy: remaining)
                head.append(DisplaySpan(text: String(span.text[..<cut]), italic: span.italic))
                tail.append(DisplaySpan(text: String(span.text[cut...]), italic: span.italic))
                remaining = 0
            }
        }

        return (head, tail)
    }
}
