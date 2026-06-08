//
//  Storage.swift
//  GalleyCore
//
//  Purpose: The on-disk round-trip (§10, ADR-0007) — `serialize` renders a
//  `Document` to a Fountain-for-prose string plus a JSON sidecar, and `parse`
//  reconstructs the exact document from the pair. Prose is continuous and
//  writer-owned; block identity, structure, and metadata live in the sidecar
//  (ADR-0010) so unrelated prose edits never rot the cut anchors.
//  Public interface: `serialize(_:)`, `parse(proseText:sidecar:)`, `ParseError`.
//  Owner context: GalleyCore — UI-free Swift, the model-as-truth (ADR-0004).
//

import Foundation

/// A failure encountered while parsing the prose/sidecar pair back into a model.
///
/// Every case names a specific malformation so callers (and tests) can assert on
/// the exact reason a load was rejected, never a generic error.
public enum ParseError: Error, Equatable {

    /// A set-piece fence (`:::kind`) was opened but never closed before EOF.
    case unterminatedSetPiece

    /// A set-piece fence named a kind outside the closed vocabulary (§9).
    case unknownSetPieceKind(String)

    /// The prose and sidecar disagree on how many blocks the document has.
    case blockCountMismatch(prose: Int, sidecar: Int)

    /// A sidecar cut anchors to a block ID that no parsed block carries.
    case unknownBlockID(BlockID)

    /// A sidecar block carried a presentation-override token outside the closed
    /// `PresentationOverride` vocabulary (ADR-0009).
    case unknownOverrideToken(String)

    /// A sidecar cut carried a section-role token outside the closed `SectionRole`
    /// vocabulary (ADR-0026).
    case unknownSectionRole(String)

    /// The sidecar text was not the expected JSON shape.
    case malformedSidecar(String)
}

// MARK: - Serialize

/// Renders a document to its on-disk pair: continuous prose plus a JSON sidecar.
///
/// - Parameter doc: a canonical document (coalesced runs, no empty paragraphs).
/// - Returns: `prose` — blocks joined by a blank line, with `_italic_` marks,
///   `***` scene breaks, and `:::kind … :::` set-piece fences; `sidecar` — a
///   deterministic (sorted-key) JSON object carrying `nextBlockID`, metadata,
///   the ordered block IDs and overrides, the chapter cuts, and the bible.
/// - Note: total function — escaping makes the prose unambiguous, so the pair
///   always satisfies `parse(serialize(doc)) == doc` for a canonical document.
public func serialize(_ doc: Document) -> (prose: String, sidecar: String) {
    // Empty paragraphs (e.g. a freshly-inserted section's body, not yet typed) have
    // no prose line — they would be indistinguishable from a block separator — so
    // they are omitted from the prose and flagged in the sidecar instead, and the
    // parser reconstructs them from that flag. This keeps the prose plain (ADR-0007)
    // while making the round-trip total even with empty blocks (ADR-0010).
    let prose = doc.blocks
        .filter { !isEmptyParagraph($0.content) }
        .map { serializeBlock($0.content) }
        .joined(separator: "\n\n")

    let dto = SidecarDTO(
        nextBlockID: doc.nextBlockID,
        title: doc.meta.title,
        author: doc.meta.author,
        legalName: doc.meta.legalName,
        email: doc.meta.email,
        phone: doc.meta.phone,
        address: doc.meta.address,
        wordCount: doc.meta.wordCount,
        genre: doc.meta.genre,
        logline: doc.meta.logline,
        bio: doc.meta.bio,
        agent: doc.meta.agent,
        blocks: doc.blocks.map {
            BlockDTO(id: $0.id, overrides: encodeOverrides($0.overrides),
                     empty: isEmptyParagraph($0.content) ? true : nil)
        },
        cuts: doc.cuts.map {
            // Omit the default `.chapter` role so legacy sidecars (which never
            // carried one) stay byte-identical on round-trip (ADR-0026).
            CutDTO(blockID: $0.blockID, offset: $0.offsetInBlock, title: $0.title,
                   role: $0.role == .chapter ? nil : $0.role.rawValue, opener: $0.opener?.id)
        },
        bible: doc.bible.entries.map {
            BibleDTO(name: $0.name, canonicalText: $0.canonicalText, notes: $0.notes)
        }
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    // Encoding a fixed Codable struct cannot fail; fall back to "{}" defensively.
    let data = (try? encoder.encode(dto)) ?? Data("{}".utf8)
    let sidecar = String(decoding: data, as: UTF8.self)

    return (prose, sidecar)
}

/// Whether a block is an empty paragraph — one carrying no run text. These have no
/// prose representation and are flagged in the sidecar instead (ADR-0007/0010).
private func isEmptyParagraph(_ content: BlockContent) -> Bool {
    guard case .paragraph(let runs) = content else { return false }
    return runsTextLength(runs) == 0
}

/// Renders one block to its prose lines (no trailing block separator).
private func serializeBlock(_ content: BlockContent) -> String {
    switch content {
    case .paragraph(let runs):
        return serializeParagraphLine(runs)
    case .sceneBreak:
        return "***"
    case .setPiece(let kind, let lines):
        let body = lines.map { serializeRuns($0) }
        return ([":::" + kindName(kind)] + body + [":::"]).joined(separator: "\n")
    case .figure(let imageRef, let caption):
        // A single human-readable marker line (ADR-0027): `[figure: ref]`, or
        // `[figure: ref | caption]` when captioned. `\`, `]`, and `|` are escaped so
        // the fields round-trip; the caption lives in the prose (ADR-0007).
        let ref = encodeFigureField(imageRef)
        return caption.isEmpty
            ? "[figure: \(ref)]"
            : "[figure: \(ref) | \(encodeFigureField(caption))]"
    }
}

/// Escapes a figure field (`imageRef`/`caption`) for the prose marker: `\`, `]`, and
/// `|` are backslash-escaped so the marker's delimiters stay unambiguous (ADR-0027).
private func encodeFigureField(_ text: String) -> String {
    var out = ""
    for character in text {
        switch character {
        case "\\": out += "\\\\"
        case "]": out += "\\]"
        case "|": out += "\\|"
        default: out.append(character)
        }
    }
    return out
}

/// Reverses `encodeFigureField`: honours `\` escapes, copying the escaped character
/// verbatim.
private func decodeFigureField(_ text: String) -> String {
    var out = ""
    var index = text.startIndex
    while index < text.endIndex {
        if text[index] == "\\" {
            let next = text.index(after: index)
            if next < text.endIndex {
                out.append(text[next])
                index = text.index(after: next)
                continue
            }
        }
        out.append(text[index])
        index = text.index(after: index)
    }
    return out
}

/// Parses a `[figure: …]` marker line into its `(imageRef, caption)` (ADR-0027).
///
/// The payload between `[figure:` and the trailing `]` is split at the first
/// *unescaped* `|`; the single cosmetic spaces the serializer adds (`[figure: `,
/// ` | `) are stripped, then each side is unescaped. No `|` means an empty caption.
private func parseFigureMarker(_ line: String) -> (imageRef: String, caption: String) {
    var payload = String(line.dropFirst("[figure:".count).dropLast())   // strip "[figure:" and "]"
    if payload.hasPrefix(" ") { payload.removeFirst() }

    guard let bar = firstUnescapedPipe(in: payload) else {
        return (decodeFigureField(payload), "")
    }
    var refPart = String(payload[..<bar])
    var captionPart = String(payload[payload.index(after: bar)...])
    if refPart.hasSuffix(" ") { refPart.removeLast() }
    if captionPart.hasPrefix(" ") { captionPart.removeFirst() }
    return (decodeFigureField(refPart), decodeFigureField(captionPart))
}

/// The index of the first `|` not preceded by a `\` escape, or `nil`.
private func firstUnescapedPipe(in text: String) -> String.Index? {
    var index = text.startIndex
    while index < text.endIndex {
        let character = text[index]
        if character == "\\" {
            let next = text.index(after: index)
            index = next < text.endIndex ? text.index(after: next) : text.endIndex
            continue
        }
        if character == "|" { return index }
        index = text.index(after: index)
    }
    return nil
}

/// Serializes a paragraph's runs to a single line, escaping it further if the
/// result would otherwise be misread as a scene break or set-piece fence.
private func serializeParagraphLine(_ runs: [Run]) -> String {
    let line = serializeRuns(runs)
    if line == "***" || line == "#" || line.hasPrefix(":::") || line.hasPrefix("[figure:") {
        return "\\" + line
    }
    return line
}

/// Serializes a run sequence to text, wrapping italic runs in `_…_` and escaping
/// backslashes and literal underscores so the italic delimiters stay unambiguous.
private func serializeRuns(_ runs: [Run]) -> String {
    runs.map { run in
        let escaped = run.text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "_", with: "\\_")
        return run.italic ? "_\(escaped)_" : escaped
    }.joined()
}

/// The lowercase fence name for a set-piece kind: `verse`, `epigraph`, `letter`.
private func kindName(_ kind: SetPieceKind) -> String {
    switch kind {
    case .verse: return "verse"
    case .epigraph: return "epigraph"
    case .letter: return "letter"
    }
}

/// Encodes a block's presentation overrides as sidecar tokens (ADR-0009), via the
/// shared `PresentationOverride` wire codec.
private func encodeOverrides(_ overrides: [PresentationOverride]) -> [String] {
    overrides.map(\.token)
}

// MARK: - Parse

/// Reconstructs a document from its prose and optional sidecar.
///
/// - Parameters:
///   - proseText: the continuous Fountain-for-prose text.
///   - sidecar: the JSON sidecar; when `nil`, block IDs are minted `0..<n` and
///     `nextBlockID` is set to `n` (a fresh import with no prior identity).
/// - Returns: the reconstructed `Document`.
/// - Throws: `ParseError` for an unterminated/unknown fence, a prose/sidecar
///   block-count mismatch, a cut anchored to an unknown block, an unknown
///   override token, or malformed sidecar JSON.
public func parse(proseText: String, sidecar: String?) throws -> Document {
    let contents = try parseProseBlocks(proseText)

    guard let sidecar else {
        let blocks = contents.enumerated().map { Block(id: $0.offset, content: $0.element) }
        return Document(blocks: blocks, nextBlockID: contents.count)
    }

    let dto: SidecarDTO
    do {
        dto = try JSONDecoder().decode(SidecarDTO.self, from: Data(sidecar.utf8))
    } catch {
        throw ParseError.malformedSidecar(String(describing: error))
    }

    // Reconstruct blocks from the sidecar's ordered list, drawing prose content for
    // each non-empty block in order and synthesizing an empty paragraph wherever the
    // sidecar flags one (it has no prose line). A block past the available prose
    // content is also treated as empty — recovering legacy bundles written before
    // empty paragraphs were flagged (they silently lost their blank blocks).
    var blocks: [Block] = []
    blocks.reserveCapacity(dto.blocks.count)
    var contentIndex = 0
    for meta in dto.blocks {
        let overrides = try meta.overrides.map(decodeOverride)
        if meta.empty == true || contentIndex >= contents.count {
            blocks.append(Block(id: meta.id, content: .paragraph(runs: []), overrides: overrides))
        } else {
            blocks.append(Block(id: meta.id, content: contents[contentIndex], overrides: overrides))
            contentIndex += 1
        }
    }
    guard contentIndex == contents.count else {
        // More prose blocks than the sidecar accounts for — genuinely out of sync.
        throw ParseError.blockCountMismatch(prose: contents.count, sidecar: dto.blocks.count)
    }

    let knownIDs = Set(blocks.map(\.id))
    let cuts = try dto.cuts.map { cut -> ChapterCut in
        guard knownIDs.contains(cut.blockID) else { throw ParseError.unknownBlockID(cut.blockID) }
        let role = try decodeSectionRole(cut.role)
        return ChapterCut(
            blockID: cut.blockID,
            offsetInBlock: cut.offset,
            title: cut.title,
            role: role,
            opener: cut.opener.map { TemplateRef(id: $0) }
        )
    }

    let bible = Bible(entries: dto.bible.map {
        BibleEntry(name: $0.name, canonicalText: $0.canonicalText, notes: $0.notes)
    })
    let meta = Metadata(
        title: dto.title,
        author: dto.author,
        legalName: dto.legalName ?? "",
        email: dto.email ?? "",
        phone: dto.phone ?? "",
        address: dto.address ?? "",
        wordCount: dto.wordCount ?? "",
        genre: dto.genre ?? "",
        logline: dto.logline ?? "",
        bio: dto.bio ?? "",
        agent: dto.agent ?? ""
    )

    return Document(blocks: blocks, cuts: cuts, bible: bible, meta: meta, nextBlockID: dto.nextBlockID)
}

/// Parses the prose text into an ordered list of block contents.
///
/// Blank top-level lines separate blocks and are skipped; `***`/`#` is a scene
/// break; a `:::kind` line opens a set-piece fence read verbatim (blank lines
/// preserved) until a closing `:::`; any other line is a paragraph.
private func parseProseBlocks(_ proseText: String) throws -> [BlockContent] {
    let lines = proseText.components(separatedBy: "\n")
    var blocks: [BlockContent] = []
    var index = 0

    while index < lines.count {
        let line = lines[index]

        if line.isEmpty {
            index += 1
            continue
        }

        if line == "***" || line == "#" {
            blocks.append(.sceneBreak)
            index += 1
            continue
        }

        if line.hasPrefix("[figure:") && line.hasSuffix("]") {
            let (imageRef, caption) = parseFigureMarker(line)
            blocks.append(.figure(imageRef: imageRef, caption: caption))
            index += 1
            continue
        }

        if line.hasPrefix(":::") {
            let kindToken = String(line.dropFirst(3))
            guard let kind = setPieceKind(kindToken) else {
                throw ParseError.unknownSetPieceKind(kindToken)
            }
            index += 1
            var body: [[Run]] = []
            var closed = false
            while index < lines.count {
                if lines[index] == ":::" {
                    closed = true
                    index += 1
                    break
                }
                body.append(parseRunLine(lines[index]))
                index += 1
            }
            guard closed else { throw ParseError.unterminatedSetPiece }
            blocks.append(.setPiece(kind: kind, lines: body))
            continue
        }

        blocks.append(.paragraph(runs: parseRunLine(line)))
        index += 1
    }

    return blocks
}

/// Parses one text line into canonical runs, honouring `\` escapes and `_`
/// italic toggles. Adjacent same-mark runs are coalesced and empties dropped.
private func parseRunLine(_ line: String) -> [Run] {
    var runs: [Run] = []
    var current = ""
    var italic = false
    var iterator = line.startIndex

    while iterator < line.endIndex {
        let character = line[iterator]
        if character == "\\" {
            let next = line.index(after: iterator)
            if next < line.endIndex {
                current.append(line[next])
                iterator = line.index(after: next)
            } else {
                current.append("\\")
                iterator = next
            }
        } else if character == "_" {
            runs.append(Run(text: current, italic: italic))
            current = ""
            italic.toggle()
            iterator = line.index(after: iterator)
        } else {
            current.append(character)
            iterator = line.index(after: iterator)
        }
    }
    runs.append(Run(text: current, italic: italic))

    return coalesceRuns(runs)
}

/// Maps a fence kind token to its `SetPieceKind`, or `nil` if outside vocabulary.
private func setPieceKind(_ token: String) -> SetPieceKind? {
    switch token {
    case "verse": return .verse
    case "epigraph": return .epigraph
    case "letter": return .letter
    default: return nil
    }
}

/// Decodes a sidecar override token back to a `PresentationOverride` (ADR-0009),
/// via the shared wire codec. An unknown token is a hard rejection, never skipped.
private func decodeOverride(_ token: String) throws -> PresentationOverride {
    guard let override = PresentationOverride(token: token) else {
        throw ParseError.unknownOverrideToken(token)
    }
    return override
}

/// Decodes a sidecar section-role token back to a `SectionRole` (ADR-0026). A
/// missing token (`nil`) is a legacy roleless cut → `.chapter` (back-compatible);
/// a present-but-unknown token is a hard rejection, never silently defaulted,
/// mirroring the closed-vocabulary discipline of `decodeOverride`.
private func decodeSectionRole(_ token: String?) throws -> SectionRole {
    guard let token else { return .chapter }
    guard let role = SectionRole(rawValue: token) else {
        throw ParseError.unknownSectionRole(token)
    }
    return role
}

// MARK: - Sidecar DTO

/// The JSON shape of the chapter sidecar (ADR-0007). A dedicated transfer type so
/// the domain model never gains a serialization dependency; block content is
/// never stored here — only identity, structure, and metadata.
private struct SidecarDTO: Codable {
    var nextBlockID: Int
    var title: String
    var author: String
    // Submission fields added after the initial format; optional so sidecars
    // written before they existed still decode (missing key → nil → "").
    var legalName: String?
    var email: String?
    var phone: String?
    var address: String?
    var wordCount: String?
    var genre: String?
    var logline: String?
    var bio: String?
    var agent: String?
    var blocks: [BlockDTO]
    var cuts: [CutDTO]
    var bible: [BibleDTO]
}

/// Per-block sidecar entry: stable identity plus override tokens, positionally
/// parallel to the prose blocks.
private struct BlockDTO: Codable {
    var id: Int
    var overrides: [String]
    // `true` for an empty paragraph, which has no prose line and is reconstructed
    // from this flag. Omitted (nil) for ordinary blocks, so non-empty sidecars stay
    // byte-identical and pre-flag bundles still decode.
    var empty: Bool?
}

/// Sidecar entry for a chapter cut (ADR-0010): anchored by block ID, never by
/// prose position.
private struct CutDTO: Codable {
    var blockID: Int
    var offset: Int?
    var title: String?
    // Section role token (ADR-0026); optional so cuts written before roles existed
    // still decode (missing key → nil → `.chapter`). The default `.chapter` is
    // written as nil so legacy sidecars round-trip byte-identical.
    var role: String?
    var opener: String?
}

/// Sidecar entry for one bible reference (§9).
private struct BibleDTO: Codable {
    var name: String
    var canonicalText: String
    var notes: String
}
