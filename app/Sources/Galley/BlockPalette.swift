//
//  BlockPalette.swift
//  Galley
//
//  Purpose: The Block Palette (BP2) — the keyboard-first surface (Cmd-;) that
//  inserts structure without leaving the keyboard (memory: keyboard-first-writing-ux).
//  It lists the one complete built-in block (Scene Break) and the writer's own
//  block templates from the buffer's headless `TemplateIndex`, and turns the chosen
//  row into an `InputEvent.insertBlock` against the pure reducer (model-as-truth,
//  ADR-0004). Sibling to `SnippetCompletionPopover`: a non-focus-stealing list
//  popover the `InputController` drives by keyboard. Matching/templates are headless
//  (GalleyShell); this is the AppKit presentation + the item vocabulary.
//  Public interface: `BlockPaletteItem`, `BlockPalette.items(templates:)`,
//  `BlockPalettePopover`.
//  Owner context: Galley — the macOS shell's editing UI.
//
//  Scope (v1): the palette inserts editable blocks only. Set-piece kinds
//  (verse/epigraph/letter) are deferred from the palette because set-pieces are not
//  yet inline-editable (EditorLayout marks them non-editable, a Phase-3 limit) —
//  inserting one the caret cannot enter would break the "real, editable block"
//  promise. An `align:center` + `smallCaps` template serves the epigraph need today.
//

import AppKit
import SwiftUI
import GalleyCore
import GalleyShell

/// What inserting a palette row does, in model terms.
enum BlockPaletteAction: Equatable {

    /// Insert a scene-break ornament (the one complete built-in block).
    case sceneBreak

    /// Insert a figure placeholder — an empty image ref + caption the writer fills in
    /// (LT4-2). Galley records intent only; the typesetter places the image (ADR-0024).
    case figure

    /// Insert an editable paragraph seeded from a user template's body + overrides.
    case template(BlockTemplate)

    /// Insert a section — a fresh prose block plus a roled chapter cut (LT2). The
    /// `SectionRole` is typesetter intent (ADR-0024); all four roles insert the
    /// same way, differing only in the role the cut carries.
    case section(SectionRole)
}

/// One row of the Block Palette: its display label, an optional mnemonic key that
/// selects it directly (e.g. `C` → Chapter), and the insertion it performs.
struct BlockPaletteItem: Equatable {
    let label: String
    let key: String?
    let action: BlockPaletteAction
}

enum BlockPalette {

    /// The four section inserts, in the order the palette lists them (LT2). Each
    /// places a roled chapter cut + fresh prose; the role is typesetter intent
    /// (ADR-0024). The underlying op is identical for all four. Mnemonic keys are
    /// assigned by `assignKeys` (LT3).
    private static let sections: [(label: String, role: SectionRole)] = [
        ("Prologue", .prologue),
        ("Epilogue", .epilogue),
        ("Dedication", .dedication),
        ("Chapter", .chapter),
    ]

    /// The palette rows for a buffer, in three groups (LT2/LT4-2): (1) the Scene Break
    /// and Figure built-ins; (2) the writer's templates (3-layer merged index); (3) the
    /// four section inserts. A buffer with no templates still offers groups (1) and (3),
    /// so the palette is never empty. The fixed rows carry mnemonic keys (LT3);
    /// templates are chosen by arrow/Return.
    ///
    /// - Parameter templates: the buffer's loaded template index (may be empty).
    /// - Returns: the ordered palette rows.
    static func items(templates: TemplateIndex) -> [BlockPaletteItem] {
        let rows: [(label: String, action: BlockPaletteAction)] =
            [("Scene Break", .sceneBreak), ("Figure", .figure)]
            + templates.matches(for: "", limit: .max).map { ($0.name, .template($0)) }
            + sections.map { ($0.label, .section($0.role)) }

        let keys = assignKeys(rows.map(\.label))
        return zip(rows, keys).map { row, key in
            BlockPaletteItem(label: row.label, key: key, action: row.action)
        }
    }

    /// Mnemonic keys for the palette rows: a unique in-word letter per row (LT3),
    /// uppercased, shown so they are discoverable. A priority pass gives the common
    /// items their natural first letter (Chapter→C, Prologue→P, Scene Break→S, Figure→F,
    /// and the built-in templates Epigraph→E / Dateline→D / Block Quote→B); the remaining
    /// rows (Epilogue, Dedication, user templates) take their first still-free letter.
    private static func assignKeys(_ labels: [String]) -> [String?] {
        let preferred = ["Chapter", "Scene Break", "Prologue", "Figure", "Epigraph", "Dateline", "Block Quote"]
        let order = preferred.compactMap { labels.firstIndex(of: $0) }
            + labels.indices.filter { !preferred.contains(labels[$0]) }

        var used = Set<Character>()
        var keys = [String?](repeating: nil, count: labels.count)
        for index in order {
            for character in labels[index].uppercased() where character.isLetter && !used.contains(character) {
                used.insert(character)
                keys[index] = String(character)
                break
            }
        }
        return keys
    }
}

/// A non-focus-stealing popover listing the Block Palette rows at the caret.
///
/// The owning `InputController` owns the selection index and all key handling; this
/// controller just renders the list and keeps itself anchored to the caret. Mirrors
/// `SnippetCompletionPopover`: `.applicationDefined` so it never auto-dismisses on
/// the keystrokes that drive it.
@MainActor
final class BlockPalettePopover {

    private let popover = NSPopover()
    private let host = NSHostingController(rootView: PaletteList(rows: [], selected: 0))

    init() {
        popover.behavior = .applicationDefined
        popover.animates = false
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
    }

    /// Whether the palette is currently on screen.
    var isShown: Bool { popover.isShown }

    /// Shows or re-anchors the palette at the caret with the given rows/selection.
    func show(rows: [PaletteRow], selected: Int, caretRect: NSRect, in view: NSView) {
        host.rootView = PaletteList(rows: rows, selected: selected)
        if !popover.isShown {
            popover.show(relativeTo: caretRect, of: view, preferredEdge: .maxY)
        }
    }

    /// Updates the selection of an already-visible palette.
    func update(rows: [PaletteRow], selected: Int) {
        host.rootView = PaletteList(rows: rows, selected: selected)
    }

    /// Hides the palette if shown.
    func hide() {
        if popover.isShown { popover.performClose(nil) }
    }
}

/// A palette row for display: a label and its optional mnemonic key.
struct PaletteRow: Equatable {
    let label: String
    let key: String?
}

/// The Block Palette list. Highlights the selected row; non-interactive so it never
/// steals focus from the editor.
private struct PaletteList: View {
    let rows: [PaletteRow]
    let selected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 8) {
                    Text(row.label)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    if let key = row.key {
                        Text(key)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(index == selected ? Color.accentColor.opacity(0.22) : Color.clear)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 240, alignment: .leading)
    }
}
