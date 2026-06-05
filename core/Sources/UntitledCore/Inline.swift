//
//  Inline.swift
//  UntitledCore
//
//  Purpose: The inline layer of the document model — runs of text carrying the
//  single permitted inline mark (italic). The smallest unit of the §4 model.
//  Public interface: `Run`.
//  Owner context: UntitledCore — UI-free Swift, the model-as-truth (ADR-0004).
//

/// A run of text plus its inline marks.
///
/// Italic is the only inline mark in v1 (ADR-0009: closed vocabulary). A
/// paragraph or set-piece line is a sequence of runs; adjacent runs differ only
/// in their marks.
public struct Run: Equatable, Hashable, Sendable {

    /// The literal text of the run. May be empty (e.g. a freshly split run).
    public var text: String

    /// Whether this run is italicised. The only inline mark in v1.
    public var italic: Bool

    /// Creates a run of text.
    /// - Parameters:
    ///   - text: the literal characters of the run.
    ///   - italic: whether the run is italicised; defaults to `false`.
    public init(text: String, italic: Bool = false) {
        self.text = text
        self.italic = italic
    }
}
