//
//  InputController+Snippets.swift
//  Galley
//
//  Purpose: The `@`-snippet completion behaviour for the editor (§9). Detects the
//  `@`-token at the caret, drives the completion list from the buffer's headless
//  `SnippetIndex`, and on selection replaces the token with the chosen snippet's
//  body through the pure reducer (model-as-truth, ADR-0004), splitting multi-line
//  snippets into paragraphs. All matching lives in GalleyShell; this is the AppKit
//  driver.
//  Public interface: the `keyDown`/edit hooks in `InputController` call into these.
//  Owner context: Galley — the macOS shell's editing layer.
//

import AppKit
import GalleyCore
import GalleyShell

extension InputController {

    // MARK: Completion lifecycle

    /// Re-evaluates the `@`-token at the caret and shows, updates, or hides the
    /// completion list accordingly. Called after every insert/delete.
    func refreshCompletion() {
        guard let buffer,
              let caret = caretModelPosition(),
              let token = mentionToken(at: caret, in: buffer.document) else {
            endCompletion()
            return
        }

        let matches = buffer.snippetIndex.matches(for: token.query)
        guard !matches.isEmpty else {
            endCompletion()
            return
        }

        completionSession = (anchorOffset: token.anchorOffset, blockID: caret.blockID)
        completionMatches = matches
        completionSelection = 0
        completionPopover.show(names: matches.map(\.name), selected: 0, caretRect: caretBoundingRect(), in: self)
    }

    /// Closes the completion session and clears its state.
    func endCompletion() {
        guard completionSession != nil || completionPopover.isShown else { return }
        completionSession = nil
        completionMatches = []
        completionSelection = 0
        completionPopover.hide()
    }

    /// Handles a key while the completion list is visible. Returns `true` if the key
    /// was consumed (the caller then stops processing it).
    func handleCompletionKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126:   // up arrow
            completionSelection = max(completionSelection - 1, 0)
            completionPopover.update(names: completionMatches.map(\.name), selected: completionSelection)
            return true
        case 125:   // down arrow
            completionSelection = min(completionSelection + 1, completionMatches.count - 1)
            completionPopover.update(names: completionMatches.map(\.name), selected: completionSelection)
            return true
        case 36, 76, 48:   // return / keypad enter / tab — accept
            acceptCompletion()
            return true
        case 53:   // esc — dismiss, leaving the literal "@query" text
            endCompletion()
            return true
        default:
            return false
        }
    }

    /// Replaces the `@`-token with the highlighted snippet's body.
    ///
    /// The token is removed through the pure reducer and the snippet body inserted in
    /// its place, so the model stays the single source of truth (ADR-0004). A body
    /// containing newlines is split into successive paragraphs.
    func acceptCompletion() {
        guard let buffer,
              let session = completionSession,
              completionMatches.indices.contains(completionSelection),
              let caret = caretModelPosition(),
              caret.blockID == session.blockID,
              caret.offset > session.anchorOffset else {
            endCompletion()
            return
        }

        let snippet = completionMatches[completionSelection]
        let tokenLength = caret.offset - session.anchorOffset

        // Remove the "@query" token.
        var offset = caret.offset
        for _ in 0..<tokenLength {
            applyEdit(.deleteBackward(blockID: session.blockID, offset: offset))
            offset -= 1
        }

        // Insert the snippet body, splitting on newlines into successive paragraphs.
        let lines = snippet.body.components(separatedBy: "\n")
        var currentBlock = session.blockID
        var currentOffset = session.anchorOffset
        applyEdit(.insertText(lines[0], blockID: currentBlock, offset: currentOffset))
        currentOffset += lines[0].count

        for line in lines.dropFirst() {
            applyEdit(.splitParagraph(blockID: currentBlock, offset: currentOffset))
            let doc = buffer.document
            guard let index = doc.blocks.firstIndex(where: { $0.id == currentBlock }),
                  index + 1 < doc.blocks.count else { break }
            currentBlock = doc.blocks[index + 1].id
            applyEdit(.insertText(line, blockID: currentBlock, offset: 0))
            currentOffset = line.count
        }

        endCompletion()
        renderFromModel(caret: (currentBlock, currentOffset))
    }

    // MARK: Geometry & token scanning

    /// The `@`-token immediately preceding the caret, or `nil` if the caret is not in
    /// one.
    ///
    /// A token is an `@` — at block start or after whitespace, so `email@host` does
    /// not trigger — followed by word characters (letters, digits, `-`, `_`) up to
    /// the caret. The returned `query` excludes the `@`; `anchorOffset` is the `@`'s
    /// in-block character offset.
    func mentionToken(at caret: (blockID: BlockID, offset: Int), in doc: Document) -> (anchorOffset: Int, query: String)? {
        guard let block = doc.blocks.first(where: { $0.id == caret.blockID }),
              case .paragraph(let runs) = block.content else { return nil }

        let chars = Array(runs.map(\.text).joined())
        guard caret.offset >= 1, caret.offset <= chars.count else { return nil }

        var index = caret.offset - 1
        var collected: [Character] = []
        while index >= 0 {
            let ch = chars[index]
            if ch == "@" {
                let precededOK = index == 0 || chars[index - 1].isWhitespace
                return precededOK ? (index, String(collected.reversed())) : nil
            }
            guard ch.isLetter || ch.isNumber || ch == "-" || ch == "_" else { return nil }
            collected.append(ch)
            index -= 1
        }
        return nil
    }

    /// The caret's bounding rectangle in this view's coordinates, for anchoring the
    /// completion list.
    ///
    /// Computed from the TextKit 2 layout's selection segment rather than
    /// `firstRect(forCharacterRange:)`, which returns `.zero` for a caret (empty)
    /// range under TextKit 2 and would anchor the popover to the wrong place. Falls
    /// back to the text inset corner if the layout geometry is unavailable.
    func caretBoundingRect() -> NSRect {
        let fallback = NSRect(x: textContainerInset.width, y: textContainerInset.height, width: 1, height: 16)
        guard let textLayoutManager,
              let textRange = textLayoutManager.textSelections.first?.textRanges.first else {
            return fallback
        }

        var segmentFrame: NSRect?
        textLayoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            segmentFrame = frame
            return false
        }

        guard var frame = segmentFrame else { return fallback }
        if frame.width < 1 { frame.size.width = 1 }                 // caret has zero width
        let origin = textContainerOrigin
        return frame.offsetBy(dx: origin.x, dy: origin.y)
    }
}
