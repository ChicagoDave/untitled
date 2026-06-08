//
//  InputController+Palette.swift
//  Galley
//
//  Purpose: The Cmd-; Block Palette behaviour for the editor (BP2). Summons the
//  palette at the caret, drives its list from the buffer's headless `TemplateIndex`
//  (plus the Scene Break built-in), and on selection inserts the chosen block
//  through the pure reducer's `insertBlock` op (model-as-truth, ADR-0004), moving
//  the caret into the new editable block. Structure is created entirely from the
//  keyboard — the writer never leaves it (memory: keyboard-first-writing-ux). The
//  palette vocabulary and matching live in `BlockPalette`/GalleyShell; this is the
//  AppKit driver.
//  Public interface: the `keyDown` hook in `InputController` calls into these.
//  Owner context: Galley — the macOS shell's editing layer.
//

import AppKit
import GalleyCore
import GalleyShell

extension InputController {

    // MARK: Palette lifecycle

    /// Opens the Block Palette at the caret, anchored to insert after the caret's
    /// block. A no-op when the caret is not in editable text (nowhere to anchor).
    func showBlockPalette() {
        guard let buffer, let caret = caretModelPosition() else { return }
        endCompletion()                       // never overlap with @-completion

        paletteAnchor = caret.blockID
        paletteItems = BlockPalette.items(templates: buffer.templateIndex)
        paletteSelection = 0
        // `items` always includes Scene Break, so the list is never empty.
        palettePopover.show(rows: paletteRows, selected: 0, caretRect: caretBoundingRect(), in: self)
    }

    /// The palette items as display rows (label + mnemonic key).
    private var paletteRows: [PaletteRow] {
        paletteItems.map { PaletteRow(label: $0.label, key: $0.key) }
    }

    /// Closes the palette session and clears its state.
    func endPalette() {
        guard paletteAnchor != nil || palettePopover.isShown else { return }
        paletteAnchor = nil
        paletteItems = []
        paletteSelection = 0
        palettePopover.hide()
    }

    /// Handles a key while the palette is visible. Returns `true` if the key was
    /// consumed (the caller then stops processing it).
    func handlePaletteKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126:   // up arrow
            paletteSelection = max(paletteSelection - 1, 0)
            palettePopover.update(rows: paletteRows, selected: paletteSelection)
            return true
        case 125:   // down arrow
            paletteSelection = min(paletteSelection + 1, paletteItems.count - 1)
            palettePopover.update(rows: paletteRows, selected: paletteSelection)
            return true
        case 36, 76, 48:   // return / keypad enter / tab — accept
            acceptPaletteSelection()
            return true
        case 53:   // esc — dismiss without inserting
            endPalette()
            return true
        default:
            // A mnemonic key (e.g. C → Chapter, P → Prologue) selects and inserts
            // its row directly (LT3).
            if let typed = event.charactersIgnoringModifiers?.uppercased(), typed.count == 1,
               let index = paletteItems.firstIndex(where: { $0.key == typed }) {
                paletteSelection = index
                acceptPaletteSelection()
                return true
            }
            return false
        }
    }

    /// Inserts the highlighted palette row after the anchor and moves the caret into
    /// the seeded block. Blocks and templates dispatch `insertBlock`; sections
    /// dispatch the atomic `insertSection` reducer arm (a roled cut + fresh prose).
    /// Sections are titled afterwards, in the truth view — tap the section's chip in
    /// the reveal pane (LT2) — not here, so the palette stays a pure insert surface.
    /// A non-editable Scene Break leaves the caret where it was.
    func acceptPaletteSelection() {
        guard let buffer,
              paletteItems.indices.contains(paletteSelection),
              let anchor = paletteAnchor else {
            endPalette()
            return
        }

        let action = paletteItems[paletteSelection].action
        applyEdit(event(for: action, after: anchor))
        endPalette()

        // The seeded block is the one now sitting immediately after the anchor.
        let doc = buffer.document
        let seeded = doc.blocks.firstIndex(where: { $0.id == anchor }).flatMap { i in
            i + 1 < doc.blocks.count ? doc.blocks[i + 1].id : nil
        }

        // A section drops straight into inline title editing (its seeded block is the
        // cut's anchor) so the writer names it immediately, keyboard-first (LT3); a
        // figure drops into its caption (the box is non-editable, so the caption is the
        // keyboard-reachable surface, LT4-2/ADR-0028); every other insert just places
        // the caret in the new editable block.
        if case .section = action, let seeded {
            beginTitleEditing(cut: seeded)
        } else if case .figure = action, let seeded {
            beginCaptionEditing(figure: seeded)
        } else if let seeded {
            renderFromModel(caret: (seeded, 0))
        } else {
            renderFromModel(caret: nil)
        }
    }

    /// The reducer event a palette action dispatches against the anchor.
    ///
    /// A template becomes a single editable paragraph seeded with its body; any stray
    /// newline is flattened to a space so the block stays one logical paragraph
    /// (multi-paragraph templates are a deferred v1 limit). A section seeds a fresh
    /// paragraph plus a roled chapter cut anchored to it (LT2). Scene Break inserts
    /// the ornament with no overrides.
    private func event(for action: BlockPaletteAction, after anchor: BlockID) -> InputEvent {
        switch action {
        case .sceneBreak:
            return .insertBlock(content: .sceneBreak, overrides: [], afterBlockID: anchor)
        case .figure:
            return .insertBlock(content: .figure(imageRef: "", caption: ""), overrides: [], afterBlockID: anchor)
        case .template(let template):
            let body = template.body.replacingOccurrences(of: "\n", with: " ")
            return .insertBlock(content: .paragraph(runs: [Run(text: body)]),
                                overrides: template.overrides, afterBlockID: anchor)
        case .section(let role):
            return .insertSection(role: role, afterBlockID: anchor)
        }
    }
}
