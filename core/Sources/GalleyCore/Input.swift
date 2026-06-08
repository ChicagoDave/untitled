//
//  Input.swift
//  GalleyCore
//
//  Purpose: `applyInput` — the pure editing reducer (§8, ADR-0004). Turns one
//  model-coordinate `InputEvent` into a new `Document`, delegating structural
//  edits to the block-lifecycle operations (ADR-0010) so cut anchoring is always
//  preserved. Pure and total: an event naming an unknown or wrong-kind block
//  returns the document unchanged rather than throwing, since the shell derives
//  events from a live caret and a stale event must not crash editing.
//  Public interface: `applyInput(_:to:)`.
//  Owner context: GalleyCore — UI-free Swift, the model-as-truth (ADR-0004).
//

/// Applies one editing intent to a document, returning the result (§8).
///
/// - Parameters:
///   - event: the model-coordinate editing intent.
///   - doc: the document to edit.
/// - Returns: a new document with the edit applied, or `doc` unchanged if the
///   event does not apply (unknown block, wrong block kind, empty range).
public func applyInput(_ event: InputEvent, to doc: Document) -> Document {
    var doc = doc
    switch event {
    case let .insertText(text, blockID, offset):
        insertText(text, blockID: blockID, offset: offset, in: &doc)
    case let .splitParagraph(blockID, offset):
        try? doc.splitBlock(id: blockID, atOffset: offset)
    case let .breakSetPieceLine(blockID, lineIndex, offset):
        breakSetPieceLine(blockID: blockID, lineIndex: lineIndex, offset: offset, in: &doc)
    case let .deleteBackward(blockID, offset):
        deleteBackward(blockID: blockID, offset: offset, in: &doc)
    case let .toggleItalic(blockID, start, end):
        toggleItalic(blockID: blockID, start: start, end: end, in: &doc)
    case let .makeSceneBreak(blockID):
        makeSceneBreak(blockID: blockID, in: &doc)
    case let .toggleSetPiece(blockID, kind):
        toggleSetPiece(blockID: blockID, kind: kind, in: &doc)
    case let .insertBlock(content, overrides, afterBlockID):
        insertBlock(content: content, overrides: overrides, afterBlockID: afterBlockID, in: &doc)
    case let .insertSection(role, afterBlockID):
        insertSection(role: role, afterBlockID: afterBlockID, in: &doc)
    case let .clearOverrides(blockID):
        clearOverrides(blockID: blockID, in: &doc)
    case let .setFigureCaption(blockID, caption):
        setFigureCaption(blockID: blockID, caption: caption, in: &doc)
    case let .deleteBlock(blockID):
        deleteBlock(blockID: blockID, in: &doc)
    case let .clearOverride(blockID, index):
        clearOverride(blockID: blockID, index: index, in: &doc)
    }
    return doc
}

// MARK: - Insert

/// Inserts text into a paragraph at an offset, applying smart typography and
/// inheriting the caret's italic, then shifts anchored cuts.
private func insertText(_ raw: String, blockID: BlockID, offset: Int, in doc: inout Document) {
    guard let i = doc.blocks.firstIndex(where: { $0.id == blockID }),
          case .paragraph(let runs) = doc.blocks[i].content else { return }

    let length = runsTextLength(runs)
    let caret = min(max(offset, 0), length)
    let full = runs.map(\.text).joined()
    let edit = smartTypography(inserting: raw, precededBy: precedingTwo(full, before: caret))

    let removeFrom = max(0, caret - edit.deletePreceding)
    let italic = italicAtCaret(runs, offset: caret)

    let (head, _) = splitRuns(runs, at: removeFrom)
    let (_, tail) = splitRuns(runs, at: caret)
    let inserted = edit.text.isEmpty ? [] : [Run(text: edit.text, italic: italic)]
    doc.blocks[i].content = .paragraph(runs: coalesceRuns(head + inserted + tail))

    let delta = edit.text.count - edit.deletePreceding
    if delta != 0 {
        doc.adjustCutOffset(blockID: blockID, at: removeFrom, delta: delta)
    }
}

// MARK: - Insert block (Block Palette, BP2)

/// Inserts a pre-composed block immediately after `afterBlockID`, minting a fresh
/// identity (ADR-0010). A no-op if `afterBlockID` names no block, so a stale
/// palette event can never crash editing (the reducer's total contract). Cuts are
/// untouched — the new block carries a never-before-seen ID that no cut anchors to,
/// and inserting after an existing anchor never shifts another block's offsets.
private func insertBlock(content: BlockContent, overrides: [PresentationOverride], afterBlockID: BlockID, in doc: inout Document) {
    guard let i = doc.blocks.firstIndex(where: { $0.id == afterBlockID }) else { return }
    let newID = doc.mintBlockID()
    doc.blocks.insert(Block(id: newID, content: content, overrides: overrides), at: i + 1)
}

// MARK: - Insert section (Block Palette, LT2)

/// Inserts a section: a fresh empty paragraph immediately after `afterBlockID`
/// (minting a fresh identity, ADR-0010) plus a boundary `ChapterCut` of `role`
/// anchored to that seeded block, so the role labels the new section, not the
/// prior block (ADR-0026). Atomic: the cut always anchors the block it seeds. A
/// no-op if `afterBlockID` names no block, so a stale palette event can never
/// crash editing (the reducer's total contract) and the counter is left untouched.
private func insertSection(role: SectionRole, afterBlockID: BlockID, in doc: inout Document) {
    guard let i = doc.blocks.firstIndex(where: { $0.id == afterBlockID }) else { return }
    let newID = doc.mintBlockID()
    doc.blocks.insert(Block(id: newID, content: .paragraph(runs: [])), at: i + 1)
    // Seed a non-empty default title (LT3): a section title is never blank, and a
    // chapter carries the `#a` macro so it auto-numbers immediately. The writer
    // edits this default in the heading.
    doc.cuts.append(ChapterCut(blockID: newID, title: role.defaultTitle, role: role))
}

// MARK: - Clear overrides (end a styled block, LT3)

/// Removes all presentation overrides from a block, returning it to plain prose. A
/// no-op if `blockID` names no block, so a stale event can never crash editing.
private func clearOverrides(blockID: BlockID, in doc: inout Document) {
    guard let i = doc.blocks.firstIndex(where: { $0.id == blockID }) else { return }
    doc.blocks[i].overrides = []
}

// MARK: - Figure caption (LT4-2, ADR-0028 Option A)

/// Replaces the caption of a figure block, preserving its `imageRef`. A no-op if
/// `blockID` names no block or the block is not a figure, so a stale or
/// mis-targeted caption event can never crash editing (the reducer's total
/// contract). An empty caption is valid (the writer cleared the field).
private func setFigureCaption(blockID: BlockID, caption: String, in doc: inout Document) {
    guard let i = doc.blocks.firstIndex(where: { $0.id == blockID }),
          case .figure(let imageRef, _) = doc.blocks[i].content else { return }
    doc.blocks[i].content = .figure(imageRef: imageRef, caption: caption)
}

// MARK: - Delete block / override (Reveal Codes surface, LT5-2, ADR-0034)

/// Deletes a whole block by ID — a reveal `[SceneBreak]`/`[figure]` chip deletion.
/// Delegates to `Document.deleteBlock` so any anchored cut relocates (ADR-0010). A
/// no-op on an unknown block, and a no-op when it is the only block, so the document
/// always keeps a block to place the caret in (the reducer's total contract).
private func deleteBlock(blockID: BlockID, in doc: inout Document) {
    guard doc.blocks.count > 1 else { return }
    try? doc.deleteBlock(id: blockID)
}

/// Removes the single presentation override at `index` on a block — a reveal override
/// chip deletion. A no-op on an unknown block or an out-of-range index, so a stale
/// chip event can never crash editing (the reducer's total contract).
private func clearOverride(blockID: BlockID, index: Int, in doc: inout Document) {
    guard let i = doc.blocks.firstIndex(where: { $0.id == blockID }),
          doc.blocks[i].overrides.indices.contains(index) else { return }
    doc.blocks[i].overrides.remove(at: index)
}

// MARK: - Delete

/// Backspace: delete the preceding character, or — at offset 0 — merge with the
/// previous paragraph, remove a preceding scene break/set-piece, or no-op at the
/// document start.
private func deleteBackward(blockID: BlockID, offset: Int, in doc: inout Document) {
    guard let i = doc.blocks.firstIndex(where: { $0.id == blockID }) else { return }

    guard case .paragraph(let runs) = doc.blocks[i].content else {
        // The caret is not in editable text (e.g. a scene break): remove the block.
        try? doc.deleteBlock(id: blockID)
        return
    }

    if offset > 0 {
        let length = runsTextLength(runs)
        let caret = min(offset, length)
        let (head, _) = splitRuns(runs, at: caret - 1)
        let (_, tail) = splitRuns(runs, at: caret)
        doc.blocks[i].content = .paragraph(runs: coalesceRuns(head + tail))
        doc.adjustCutOffset(blockID: blockID, at: caret - 1, delta: -1)
        return
    }

    // offset == 0: act on the boundary with the previous block.
    guard i > 0 else { return }                 // first block: nothing precedes it
    let previous = doc.blocks[i - 1]
    if case .paragraph = previous.content {
        try? doc.mergeBlocks(first: previous.id, second: blockID)
    } else {
        try? doc.deleteBlock(id: previous.id)   // remove the preceding ornament
    }
}

// MARK: - Italic

/// Toggles italic over `start..<end`: italicises the range unless it is already
/// wholly italic, in which case it clears it.
private func toggleItalic(blockID: BlockID, start: Int, end: Int, in doc: inout Document) {
    guard let i = doc.blocks.firstIndex(where: { $0.id == blockID }),
          case .paragraph(let runs) = doc.blocks[i].content else { return }

    let length = runsTextLength(runs)
    let lo = min(max(start, 0), length)
    let hi = min(max(end, lo), length)
    guard hi > lo else { return }

    let (head, rest) = splitRuns(runs, at: lo)
    let (mid, tail) = splitRuns(rest, at: hi - lo)
    let allItalic = mid.allSatisfy(\.italic)
    let flipped = mid.map { Run(text: $0.text, italic: !allItalic) }
    doc.blocks[i].content = .paragraph(runs: coalesceRuns(head + flipped + tail))
}

// MARK: - Scene break

/// Replaces a block with a scene-break ornament, clearing overrides and clamping
/// any cut on it to the block boundary (offsets are undefined on a scene break).
private func makeSceneBreak(blockID: BlockID, in doc: inout Document) {
    guard let i = doc.blocks.firstIndex(where: { $0.id == blockID }) else { return }
    doc.blocks[i].content = .sceneBreak
    doc.blocks[i].overrides = []
    for k in doc.cuts.indices where doc.cuts[k].blockID == blockID {
        doc.cuts[k].offsetInBlock = nil
    }
}

// MARK: - Set-piece

/// Toggles a paragraph into a single-line set-piece of `kind`, or a set-piece
/// back into a paragraph by concatenating its lines. Cuts on a block becoming a
/// set-piece clamp to the boundary (offsets are undefined there).
private func toggleSetPiece(blockID: BlockID, kind: SetPieceKind, in doc: inout Document) {
    guard let i = doc.blocks.firstIndex(where: { $0.id == blockID }) else { return }

    switch doc.blocks[i].content {
    case .paragraph(let runs):
        doc.blocks[i].content = .setPiece(kind: kind, lines: [coalesceRuns(runs)])
        for k in doc.cuts.indices where doc.cuts[k].blockID == blockID {
            doc.cuts[k].offsetInBlock = nil
        }
    case .setPiece(_, let lines):
        doc.blocks[i].content = .paragraph(runs: coalesceRuns(lines.flatMap { $0 }))
    case .sceneBreak, .figure:
        break   // a scene break or figure has no prose to toggle into a set-piece
    }
}

/// Breaks a set-piece line at an offset into two preserved lines (a `[line]`, §7).
private func breakSetPieceLine(blockID: BlockID, lineIndex: Int, offset: Int, in doc: inout Document) {
    guard let i = doc.blocks.firstIndex(where: { $0.id == blockID }),
          case .setPiece(let kind, var lines) = doc.blocks[i].content,
          lineIndex >= 0, lineIndex < lines.count else { return }

    let line = lines[lineIndex]
    let caret = min(max(offset, 0), runsTextLength(line))
    let (head, tail) = splitRuns(line, at: caret)
    lines.replaceSubrange(lineIndex...lineIndex, with: [head, tail])
    doc.blocks[i].content = .setPiece(kind: kind, lines: lines)
}

// MARK: - Caret helpers

/// The italic the caret inherits: the character before it, or — at the block
/// start — the character after it, defaulting to non-italic.
private func italicAtCaret(_ runs: [Run], offset: Int) -> Bool {
    italicOfCharacter(runs, at: offset > 0 ? offset - 1 : 0)
}

/// The italic of the character at `position`, or the last run's italic past the
/// end, or `false` for empty content.
private func italicOfCharacter(_ runs: [Run], at position: Int) -> Bool {
    var remaining = position
    for run in runs {
        let len = run.text.count
        if remaining < len { return run.italic }
        remaining -= len
    }
    return runs.last?.italic ?? false
}

/// The two characters before `offset` in `text`, oldest first.
private func precedingTwo(_ text: String, before offset: Int) -> (Character?, Character?) {
    let characters = Array(text)
    func at(_ index: Int) -> Character? {
        (index >= 0 && index < characters.count) ? characters[index] : nil
    }
    return (at(offset - 2), at(offset - 1))
}
