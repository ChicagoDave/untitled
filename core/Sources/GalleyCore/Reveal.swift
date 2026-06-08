//
//  Reveal.swift
//  GalleyCore
//
//  Purpose: `revealProjection` — the pure render of a `Document` into the flat
//  reveal stream (§5, ADR-0006). The reveal pane doubles as the chapter-slicing
//  surface, so chapter cuts surface here as addressable `[Chapter]` chips.
//  Public interface: `revealProjection(_:)`.
//  Owner context: GalleyCore — UI-free Swift, the model-as-truth (ADR-0004).
//

extension Document {

    /// Projects the document into the flat reveal token stream (§5).
    ///
    /// Walks the block stream in order, interleaving chapter-cut chips at their
    /// anchors: a cut with no in-block offset (or anchored to a non-paragraph
    /// block) emits a `[Chapter]` chip immediately before the block; a cut with
    /// an offset inside a paragraph splits the paragraph text at that offset.
    ///
    /// - Returns: the ordered `RevealToken`s the reveal pane would render. Pure;
    ///   never mutates and never fails.
    public func revealProjection() -> [RevealToken] {
        var tokens: [RevealToken] = []

        for block in blocks {
            let blockCuts = cuts.filter { $0.blockID == block.id }

            switch block.content {
            case .paragraph(let runs):
                // Cuts without an offset anchor at the block start; offset cuts
                // split the prose text at the cut position.
                for cut in blockCuts where cut.offsetInBlock == nil {
                    tokens.append(.code(label: sectionLabel(cut.role), id: .chapter(block.id, nil)))
                    // The chapter-opener spacing between the heading and the body (ADR-0035).
                    tokens.append(.code(label: "sp", id: .sectionSpace(block.id)))
                }
                emitOverrides(block.overrides, blockID: block.id, into: &tokens)
                tokens.append(contentsOf: paragraphTokens(runs, blockID: block.id, cuts: blockCuts))
                // The paragraph's hard return — a visible block boundary (ADR-0035).
                tokens.append(.code(label: "p", id: .paragraph(block.id)))

            case .sceneBreak:
                emitStartCuts(blockCuts, blockID: block.id, into: &tokens)
                tokens.append(.code(label: "SceneBreak", id: .sceneBreak(block.id)))

            case .setPiece(let kind, let lines):
                emitStartCuts(blockCuts, blockID: block.id, into: &tokens)
                emitOverrides(block.overrides, blockID: block.id, into: &tokens)
                let label = setPieceLabel(kind)
                tokens.append(.code(label: label, id: .setPieceOpen(block.id)))
                var span = 0
                for (index, line) in lines.enumerated() {
                    let (lineTokens, nextSpan) = runTokens(line, blockID: block.id, spanStart: span)
                    tokens.append(contentsOf: lineTokens)
                    span = nextSpan
                    tokens.append(.code(label: "line", id: .line(block.id, index)))
                }
                tokens.append(.code(label: "/" + label, id: .setPieceClose(block.id)))

            case .figure(let imageRef, _):
                // A figure is a boundary block (like a scene break): cuts surface
                // before it, then the single addressable `[figure: <ref>]` chip (LT4).
                emitStartCuts(blockCuts, blockID: block.id, into: &tokens)
                tokens.append(.code(label: "figure: \(imageRef)", id: .figure(block.id)))
            }
        }

        return tokens
    }

    /// Emits a `[Chapter]` chip for every cut anchored to a non-paragraph block.
    ///
    /// In-block offsets are undefined for scene breaks and set-pieces in v1, so
    /// all such cuts surface at the block boundary, before the block's content.
    private func emitStartCuts(_ blockCuts: [ChapterCut], blockID: BlockID, into tokens: inout [RevealToken]) {
        for cut in blockCuts {
            tokens.append(.code(label: sectionLabel(cut.role), id: .chapter(blockID, cut.offsetInBlock)))
        }
    }

    /// Builds the token run for a paragraph, interleaving `[i]`/`[/i]` chips
    /// around explicit italic runs and `[Chapter]` chips at in-block cut offsets.
    ///
    /// Codes are positioned by character offset and merged in one pass, so a cut
    /// landing inside an italic span splits cleanly (`…[i] d [Chapter] ef [/i]…`).
    /// At a shared offset, an italic close precedes a chapter, which precedes an
    /// italic open.
    private func paragraphTokens(_ runs: [Run], blockID: BlockID, cuts: [ChapterCut]) -> [RevealToken] {
        let text = runs.map(\.text).joined()
        let length = text.count

        var markers: [(offset: Int, order: Int, token: RevealToken)] = []

        var position = 0
        var span = 0
        for run in runs where !run.text.isEmpty {
            let runLength = run.text.count
            if run.italic {
                markers.append((position, 2, .code(label: "i", id: .italicOpen(blockID, span))))
                markers.append((position + runLength, 0, .code(label: "/i", id: .italicClose(blockID, span))))
                span += 1
            }
            position += runLength
        }

        for cut in cuts where cut.offsetInBlock != nil {
            let clamped = min(max(cut.offsetInBlock ?? 0, 0), length)
            markers.append((clamped, 1, .code(label: sectionLabel(cut.role), id: .chapter(blockID, clamped))))
        }

        markers.sort { ($0.offset, $0.order) < ($1.offset, $1.order) }

        var tokens: [RevealToken] = []
        var cursor = 0
        for marker in markers {
            if marker.offset > cursor {
                tokens.append(.text(substring(text, from: cursor, to: marker.offset)))
                cursor = marker.offset
            }
            tokens.append(marker.token)
        }
        if cursor < length {
            tokens.append(.text(substring(text, from: cursor, to: length)))
        }
        return tokens
    }

    /// Renders a run sequence (a paragraph fragment or a set-piece line) to tokens,
    /// bracketing each explicit italic run in `[i]`/`[/i]`. `spanStart` is the next
    /// italic-span index for the block; the updated count is returned so a block's
    /// spans stay uniquely numbered across its lines.
    private func runTokens(_ runs: [Run], blockID: BlockID, spanStart: Int) -> ([RevealToken], Int) {
        var tokens: [RevealToken] = []
        var span = spanStart
        for run in runs where !run.text.isEmpty {
            if run.italic {
                tokens.append(.code(label: "i", id: .italicOpen(blockID, span)))
                tokens.append(.text(run.text))
                tokens.append(.code(label: "/i", id: .italicClose(blockID, span)))
                span += 1
            } else {
                tokens.append(.text(run.text))
            }
        }
        return (tokens, span)
    }

    /// Emits a chip for each presentation override on a block, surfacing the closed
    /// override vocabulary in the reveal so it is visible and deletable (ADR-0009).
    private func emitOverrides(_ overrides: [PresentationOverride], blockID: BlockID, into tokens: inout [RevealToken]) {
        for (index, override) in overrides.enumerated() {
            tokens.append(.code(label: overrideLabel(override), id: .override(blockID, index)))
        }
    }

    /// The reveal chip label for a presentation override (ADR-0009).
    private func overrideLabel(_ override: PresentationOverride) -> String {
        switch override {
        case .smallCaps: return "smallCaps"
        case .blockQuote: return "quote"
        case .alignment(.leading): return "left"
        case .alignment(.center): return "center"
        case .alignment(.trailing): return "right"
        }
    }

    /// The reveal chip label for a section cut, by its role (ADR-0026): `Chapter`,
    /// `Prologue`, `Epilogue`, or `Dedication`. The reveal surfaces the role so a
    /// prologue reads as a prologue, not an indistinct chapter.
    private func sectionLabel(_ role: SectionRole) -> String {
        switch role {
        case .chapter: return "Chapter"
        case .prologue: return "Prologue"
        case .epilogue: return "Epilogue"
        case .dedication: return "Dedication"
        }
    }

    /// The reveal label for a set-piece kind: `Verse`, `Epigraph`, or `Letter`.
    private func setPieceLabel(_ kind: SetPieceKind) -> String {
        switch kind {
        case .verse: return "Verse"
        case .epigraph: return "Epigraph"
        case .letter: return "Letter"
        }
    }
}

/// Character-indexed substring `[from, to)`; clamps to the string's bounds.
private func substring(_ text: String, from: Int, to: Int) -> String {
    let count = text.count
    let lower = min(max(from, 0), count)
    let upper = min(max(to, lower), count)
    let start = text.index(text.startIndex, offsetBy: lower)
    let end = text.index(text.startIndex, offsetBy: upper)
    return String(text[start..<end])
}
