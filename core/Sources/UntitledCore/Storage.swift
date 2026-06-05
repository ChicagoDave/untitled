//
//  Storage.swift
//  UntitledCore
//
//  Purpose: The on-disk round-trip (§10, ADR-0007) — `serialize` renders a
//  `Document` to a Fountain-for-prose string plus a JSON sidecar, and `parse`
//  reconstructs the exact document from the pair. Prose is continuous and
//  writer-owned; block identity, structure, and metadata live in the sidecar
//  (ADR-0010) so unrelated prose edits never rot the cut anchors.
//  Public interface: `serialize(_:)`, `parse(proseText:sidecar:)`, `ParseError`.
//  Owner context: UntitledCore — UI-free Swift, the model-as-truth (ADR-0004).
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
    let prose = doc.blocks
        .map { serializeBlock($0.content) }
        .joined(separator: "\n\n")

    let dto = SidecarDTO(
        nextBlockID: doc.nextBlockID,
        title: doc.meta.title,
        author: doc.meta.author,
        blocks: doc.blocks.map { BlockDTO(id: $0.id, overrides: encodeOverrides($0.overrides)) },
        cuts: doc.cuts.map {
            CutDTO(blockID: $0.blockID, offset: $0.offsetInBlock, title: $0.title, opener: $0.opener?.id)
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
    }
}

/// Serializes a paragraph's runs to a single line, escaping it further if the
/// result would otherwise be misread as a scene break or set-piece fence.
private func serializeParagraphLine(_ runs: [Run]) -> String {
    let line = serializeRuns(runs)
    if line == "***" || line == "#" || line.hasPrefix(":::") {
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

/// Encodes a block's presentation overrides as sidecar tokens (ADR-0009).
private func encodeOverrides(_ overrides: [PresentationOverride]) -> [String] {
    overrides.map { override in
        switch override {
        case .smallCaps: return "smallCaps"
        case .alignment(.leading): return "align:leading"
        case .alignment(.center): return "align:center"
        case .alignment(.trailing): return "align:trailing"
        }
    }
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

    guard dto.blocks.count == contents.count else {
        throw ParseError.blockCountMismatch(prose: contents.count, sidecar: dto.blocks.count)
    }

    var blocks: [Block] = []
    blocks.reserveCapacity(contents.count)
    for (content, meta) in zip(contents, dto.blocks) {
        let overrides = try meta.overrides.map(decodeOverride)
        blocks.append(Block(id: meta.id, content: content, overrides: overrides))
    }

    let knownIDs = Set(blocks.map(\.id))
    let cuts = try dto.cuts.map { cut -> ChapterCut in
        guard knownIDs.contains(cut.blockID) else { throw ParseError.unknownBlockID(cut.blockID) }
        return ChapterCut(
            blockID: cut.blockID,
            offsetInBlock: cut.offset,
            title: cut.title,
            opener: cut.opener.map { TemplateRef(id: $0) }
        )
    }

    let bible = Bible(entries: dto.bible.map {
        BibleEntry(name: $0.name, canonicalText: $0.canonicalText, notes: $0.notes)
    })
    let meta = Metadata(title: dto.title, author: dto.author)

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

/// Decodes a sidecar override token back to a `PresentationOverride` (ADR-0009).
private func decodeOverride(_ token: String) throws -> PresentationOverride {
    switch token {
    case "smallCaps": return .smallCaps
    case "align:leading": return .alignment(.leading)
    case "align:center": return .alignment(.center)
    case "align:trailing": return .alignment(.trailing)
    default: throw ParseError.unknownOverrideToken(token)
    }
}

// MARK: - Sidecar DTO

/// The JSON shape of the chapter sidecar (ADR-0007). A dedicated transfer type so
/// the domain model never gains a serialization dependency; block content is
/// never stored here — only identity, structure, and metadata.
private struct SidecarDTO: Codable {
    var nextBlockID: Int
    var title: String
    var author: String
    var blocks: [BlockDTO]
    var cuts: [CutDTO]
    var bible: [BibleDTO]
}

/// Per-block sidecar entry: stable identity plus override tokens, positionally
/// parallel to the prose blocks.
private struct BlockDTO: Codable {
    var id: Int
    var overrides: [String]
}

/// Sidecar entry for a chapter cut (ADR-0010): anchored by block ID, never by
/// prose position.
private struct CutDTO: Codable {
    var blockID: Int
    var offset: Int?
    var title: String?
    var opener: String?
}

/// Sidecar entry for one bible reference (§9).
private struct BibleDTO: Codable {
    var name: String
    var canonicalText: String
    var notes: String
}
