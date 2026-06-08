//
//  ChapterNumbering.swift
//  GalleyCore
//
//  Purpose: Role-aware chapter numbering and section-title macro resolution
//  (ADR-0026, LT3). A section title may embed a numbering macro — `#a` (arabic) or
//  `#r` (roman) — that resolves to the chapter's number, counting only
//  `.chapter`-role boundary cuts in document order (prologues / epilogues /
//  dedications are not numbered). The stored title always keeps the macro — the
//  intent the typesetter consumes (ADR-0024); resolution is a pure render-time
//  transform, so inserting a prologue or reordering renumbers everything for free.
//  Public interface: `SectionRole.defaultTitle`, `Document.chapterOrdinal(forCutAt:)`,
//  `Document.resolvedTitle(forCutAt:)`.
//  Owner context: GalleyCore — UI-free Swift, the model-as-truth (ADR-0004).
//

extension SectionRole {

    /// The non-empty title a freshly inserted section of this role is seeded with
    /// (LT3 — a section title is never empty; the writer edits this default rather
    /// than starting blank). A chapter carries the arabic numbering macro so it
    /// auto-numbers out of the box; the other roles are their own heading.
    public var defaultTitle: String {
        switch self {
        case .chapter: return "Chapter #a"
        case .prologue: return "Prologue"
        case .epilogue: return "Epilogue"
        case .dedication: return "Dedication"
        }
    }
}

extension Document {

    /// The chapter number applicable at the boundary cut anchored at `blockID`,
    /// counting only `.chapter`-role boundary cuts in document order (ADR-0026).
    ///
    /// For a chapter cut this is its own 1-based ordinal (it counts itself); for a
    /// non-chapter cut it is the count of chapters before it. If no boundary cut is
    /// anchored at `blockID`, returns the document's total chapter count.
    public func chapterOrdinal(forCutAt blockID: BlockID) -> Int {
        var count = 0
        for block in blocks {
            for cut in cuts where cut.blockID == block.id && cut.offsetInBlock == nil {
                if cut.role == .chapter { count += 1 }
                if cut.blockID == blockID { return count }
            }
        }
        return count
    }

    /// The display title for the boundary cut anchored at `blockID`: its stored
    /// title with the numbering macros (`#a` → arabic, `#r` → roman) resolved to the
    /// chapter number (ADR-0026). The stored title is unchanged. Empty string if no
    /// boundary cut is anchored at `blockID` or its title is `nil`.
    public func resolvedTitle(forCutAt blockID: BlockID) -> String {
        guard let cut = cuts.first(where: { $0.blockID == blockID && $0.offsetInBlock == nil }),
              let raw = cut.title else { return "" }
        let number = chapterOrdinal(forCutAt: blockID)
        return raw
            .replacingOccurrences(of: "#a", with: String(number))
            .replacingOccurrences(of: "#r", with: romanNumeral(number))
    }
}

/// The uppercase Roman numeral for `n` (1...3999); empty string for `n < 1`.
func romanNumeral(_ n: Int) -> String {
    guard n >= 1 else { return "" }
    let table: [(value: Int, symbol: String)] = [
        (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
        (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
        (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
    ]
    var remaining = n
    var out = ""
    for entry in table {
        while remaining >= entry.value {
            out += entry.symbol
            remaining -= entry.value
        }
    }
    return out
}
