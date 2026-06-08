//
//  BlockText.swift
//  GalleyCore
//
//  Purpose: Character-level helpers over runs and block content used by the
//  block-lifecycle operations (ADR-0010) — measuring length, splitting a run
//  sequence at a character offset, and canonicalising runs. Offsets are counted
//  in Characters, not UTF-8/UTF-16 units, so they match what a writer sees.
//  Public interface: internal helpers only; not part of the module's API.
//  Owner context: GalleyCore — UI-free Swift.
//

/// Total character length of a run sequence.
func runsTextLength(_ runs: [Run]) -> Int {
    runs.reduce(0) { $0 + $1.text.count }
}

/// Character length of a block's content, used for offset arithmetic.
///
/// Paragraphs measure their runs; scene breaks are zero; set-pieces sum their
/// lines (line breaks excluded — set-pieces are not split or merged here, so the
/// value is only ever used for the degenerate "deleted the last block" case).
func contentTextLength(_ content: BlockContent) -> Int {
    switch content {
    case .paragraph(let runs):
        return runsTextLength(runs)
    case .sceneBreak:
        return 0
    case .setPiece(_, let lines):
        return lines.reduce(0) { $0 + runsTextLength($1) }
    case .figure:
        return 0   // a figure carries no inline prose text (its caption is not run text)
    }
}

/// Splits a run sequence at a character `offset` into head `[0..<offset)` and
/// tail `[offset...)`, breaking the straddling run if the offset lands inside it.
///
/// Both halves are canonicalised (see `coalesceRuns`). `offset` is assumed in
/// range `0...runsTextLength(runs)`; callers validate before calling.
func splitRuns(_ runs: [Run], at offset: Int) -> (head: [Run], tail: [Run]) {
    var head: [Run] = []
    var tail: [Run] = []
    var remaining = offset

    for run in runs {
        let len = run.text.count
        if remaining >= len {
            head.append(run)
            remaining -= len
        } else if remaining <= 0 {
            tail.append(run)
        } else {
            let cut = run.text.index(run.text.startIndex, offsetBy: remaining)
            head.append(Run(text: String(run.text[..<cut]), italic: run.italic))
            tail.append(Run(text: String(run.text[cut...]), italic: run.italic))
            remaining = 0
        }
    }

    return (coalesceRuns(head), coalesceRuns(tail))
}

/// Canonicalises a run sequence: drops empty runs and merges adjacent runs that
/// share identical marks, so no two neighbouring runs differ only by boundary.
///
/// This keeps `mergeBlocks(splitBlock(...))` an identity at the text level and
/// gives the model a single canonical representation for any rendered text.
func coalesceRuns(_ runs: [Run]) -> [Run] {
    var result: [Run] = []
    for run in runs where !run.text.isEmpty {
        if let last = result.last, last.italic == run.italic {
            result[result.count - 1].text += run.text
        } else {
            result.append(run)
        }
    }
    return result
}
