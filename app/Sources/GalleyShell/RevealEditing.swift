//
//  RevealEditing.swift
//  GalleyShell
//
//  Purpose: The pure code→edit mapping for the Reveal Codes surface (LT5-2,
//  ADR-0034) — given a reveal `CodeID` and the document, what deletion that chip
//  performs. Kept here, free of AppKit, so the load-bearing reverse-mapping logic is
//  unit-testable without driving an `NSTextView`; `RevealController` is a thin caller
//  that dispatches the returned action and moves the shared caret.
//  Public interface: `RevealDeleteAction`, `revealDeleteAction(for:in:)`,
//  `italicSpan(blockID:spanIndex:in:)`, `setPieceKind(blockID:in:)`.
//  Owner context: GalleyShell — the macOS shell's pure presentation/editing layer.
//

import GalleyCore

/// What deleting a reveal code chip does, in model terms (ADR-0034). The surface
/// dispatches `.event` through the reducer, `.removeCut` through the cut mutator, and
/// ignores `.deferred` (mid-block cut / `[line]`, not handled in LT5-2).
public enum RevealDeleteAction: Equatable, Sendable {
    /// Apply this reducer event (e.g. `deleteBlock`, `toggleItalic`, `clearOverride`).
    case event(InputEvent)
    /// Remove the boundary chapter cut at this block (via the cut mutator).
    case removeCut(blockID: BlockID)
    /// No deletion in LT5-2 — a mid-block `[Chapter]` or a set-piece `[line]`.
    case deferred
}

/// Maps a reveal code chip to the deletion it performs (ADR-0034). Pure — derived
/// only from the code's identity and the document.
///
/// - Parameters:
///   - code: the `CodeID` of the chip being deleted.
///   - doc: the document, for span/kind lookups.
/// - Returns: the action to dispatch; `.deferred` for codes LT5-2 does not handle.
public func revealDeleteAction(for code: CodeID, in doc: Document) -> RevealDeleteAction {
    switch code {
    case .sceneBreak(let b), .figure(let b):
        return .event(.deleteBlock(blockID: b))
    case .override(let b, let i):
        return .event(.clearOverride(blockID: b, index: i))
    case .italicOpen(let b, let n), .italicClose(let b, let n):
        guard let span = italicSpan(blockID: b, spanIndex: n, in: doc) else { return .deferred }
        return .event(.toggleItalic(blockID: b, start: span.start, end: span.end))
    case .setPieceOpen(let b), .setPieceClose(let b):
        guard let kind = setPieceKind(blockID: b, in: doc) else { return .deferred }
        return .event(.toggleSetPiece(blockID: b, kind: kind))
    case .chapter(let b, nil):
        return .removeCut(blockID: b)
    case .chapter, .line, .paragraph, .sectionSpace:
        return .deferred   // mid-block cut, set-piece line, paragraph-merge & section-spacing deletion deferred (ADR-0034/0035)
    }
}

/// The `[start, end)` character offsets of the `spanIndex`-th explicit italic run in a
/// paragraph block — so deleting an `[i]`/`[/i]` chip toggles that exact span. `nil`
/// if the block is not a paragraph or the span index is absent. The span numbering
/// matches `revealSegments(of:)` / `revealProjection()` (italic runs in document order).
public func italicSpan(blockID: BlockID, spanIndex: Int, in doc: Document) -> (start: Int, end: Int)? {
    guard let block = doc.blocks.first(where: { $0.id == blockID }),
          case .paragraph(let runs) = block.content else { return nil }
    var offset = 0, span = 0
    for run in runs where !run.text.isEmpty {
        let len = run.text.count
        if run.italic {
            if span == spanIndex { return (offset, offset + len) }
            span += 1
        }
        offset += len
    }
    return nil
}

/// The kind of a set-piece block, for collapsing it back to a paragraph; `nil` if the
/// block is not a set-piece.
public func setPieceKind(blockID: BlockID, in doc: Document) -> SetPieceKind? {
    guard let block = doc.blocks.first(where: { $0.id == blockID }),
          case .setPiece(let kind, _) = block.content else { return nil }
    return kind
}
