//
//  TemplateIndex.swift
//  GalleyShell
//
//  Purpose: The block-template source (BP1) — a fuzzy index over the writer's
//  reusable, pre-composed blocks, one `*.galley-template` file per template, read
//  from a `templates/` directory inside the `.galley` package (ADR-0020, alongside
//  `bible/` and `snippets/`). Each template carries body text plus a closed set of
//  presentation overrides parsed from a small front-matter; the Block Palette (BP2)
//  inserts a real, editable block from a chosen template. The override tokens are
//  the *same* closed vocabulary the sidecar uses, decoded through the shared
//  `PresentationOverride` wire codec in GalleyCore (rule 8b), so a templated block
//  round-trips identically. Plain file I/O, no AI (ADR-0008); the matcher is the
//  shared pure scorer (`FuzzyMatch`). Carries no AppKit, so it is headlessly testable.
//  Public interface: `BlockTemplate`, `TemplateParseError`, `TemplateIndex`,
//  `entries`, `load(directory:)`, `matches(for:limit:)`, `template(named:)`.
//  Owner context: GalleyShell — app-layer reference service. Foundation + GalleyCore.
//

import Foundation
import GalleyCore

/// One pre-composed, reusable block: a name (for the palette), the body text the
/// inserted block starts with, and the closed presentation overrides applied to it.
public struct BlockTemplate: Equatable, Hashable, Sendable {

    /// The template's display name / lookup key, derived from its filename.
    public var name: String

    /// The text the inserted block is seeded with.
    public var body: String

    /// The presentation overrides applied to the inserted block (ADR-0009), in
    /// front-matter order. Empty for a plain-text template.
    public var overrides: [PresentationOverride]

    /// Creates a block template.
    public init(name: String, body: String, overrides: [PresentationOverride] = []) {
        self.name = name
        self.body = body
        self.overrides = overrides
    }

    /// The front-matter directive prefix. A leading line of the form
    /// `override: <token>` declares one presentation override.
    private static let overrideDirective = "override:"

    /// Parses one `*.galley-template` file's text into a template.
    ///
    /// The format (ADR-0022) is a hand-rolled front-matter — zero or more leading
    /// `override: <token>` lines — followed by the body text, with one optional
    /// blank line consumed as the separator. A file that begins with prose has no
    /// front-matter and is all body. Every override token is decoded through the
    /// shared closed-vocabulary codec; an unknown token is a hard rejection, never
    /// silently dropped, so a template can never carry a presentation a sidecar
    /// could not.
    ///
    /// - Parameters:
    ///   - text: the full file contents.
    ///   - name: the display name (derived from the filename by the caller).
    /// - Returns: the parsed template.
    /// - Throws: `TemplateParseError.unknownOverrideToken` if a front-matter line
    ///   names a token outside the closed `PresentationOverride` vocabulary.
    public static func parse(_ text: String, name: String) throws -> BlockTemplate {
        let lines = text.components(separatedBy: "\n")
        var index = 0
        var overrides: [PresentationOverride] = []

        // Front-matter: the maximal run of leading `override:` directives.
        while index < lines.count, lines[index].hasPrefix(overrideDirective) {
            let token = String(lines[index].dropFirst(overrideDirective.count))
                .trimmingCharacters(in: .whitespaces)
            guard let override = PresentationOverride(token: token) else {
                throw TemplateParseError.unknownOverrideToken(token)
            }
            overrides.append(override)
            index += 1
        }

        // Consume a single blank separator line between front-matter and body.
        if !overrides.isEmpty, index < lines.count, lines[index].isEmpty {
            index += 1
        }

        // Body: the remainder, with only the trailing newline most editors append
        // trimmed (interior blank lines kept so multi-paragraph bodies survive).
        var body = lines[index...].joined(separator: "\n")
        if body.hasSuffix("\n") { body = String(body.dropLast()) }

        return BlockTemplate(name: name, body: body, overrides: overrides)
    }
}

/// A failure encountered while parsing a `*.galley-template` file.
public enum TemplateParseError: Error, Equatable {

    /// A front-matter `override:` line named a token outside the closed
    /// `PresentationOverride` vocabulary (ADR-0009). The whole template is rejected.
    case unknownOverrideToken(String)
}

/// A fuzzy index over a project's reusable block templates (BP1).
///
/// Each template is one `*.galley-template` file in the package's `templates/`
/// directory; the name is derived from the filename (`epigraph.galley-template` →
/// "Epigraph"). Mirrors `SnippetIndex` — same load/match/lookup shape — so the two
/// reference sources stay structurally parallel.
public struct TemplateIndex: Equatable, Sendable {

    /// The indexed templates, in load order (one per file).
    public private(set) var entries: [BlockTemplate]

    /// Creates an index over an explicit set of templates. The `load(directory:)`
    /// factory is the normal entry point; this exists for composition and testing.
    public init(entries: [BlockTemplate] = []) {
        self.entries = entries
    }

    /// The user-level global template directory — the cross-project layer (LT1,
    /// ADR-0025): `~/Library/Application Support/Galley/templates/`. Plain
    /// `.galley-template` files the writer edits in any text editor, available to
    /// every project. `nil` only if the OS reports no application-support directory.
    public static var userTemplateDirectory: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Galley/templates", isDirectory: true)
    }

    /// Builds a merged index from the three layers (ADR-0025): built-in values,
    /// the user-level directory, and the per-project `templates/` directory.
    ///
    /// Layers overlay by case-insensitive name with the most-specific winning —
    /// **story > user > built-in** — so a project may override a built-in or user
    /// template, and a user template may override a built-in. Order is built-ins
    /// first, then first-seen user, then first-seen story. Any layer may be empty: a
    /// `nil` or missing directory contributes nothing, and a new project (no story
    /// directory) still gets the built-in and user toolkit.
    ///
    /// - Parameters:
    ///   - builtIns: the always-present in-code templates (normally `BuiltInTemplates.all`).
    ///   - userDirectory: the user-level global templates directory, or `nil`.
    ///   - storyDirectory: the per-project `templates/` directory, or `nil` (unsaved buffer).
    /// - Returns: the merged index.
    public static func merged(
        builtIns: [BlockTemplate],
        userDirectory: URL?,
        storyDirectory: URL?
    ) -> TemplateIndex {
        var byName: [String: BlockTemplate] = [:]
        var order: [String] = []

        func overlay(_ templates: [BlockTemplate]) {
            for template in templates {
                let key = template.name.lowercased()
                if byName[key] == nil { order.append(key) }
                byName[key] = template               // a later layer wins on collision
            }
        }

        overlay(builtIns)
        if let userDirectory { overlay(load(directory: userDirectory).entries) }
        if let storyDirectory { overlay(load(directory: storyDirectory).entries) }

        return TemplateIndex(entries: order.map { byName[$0]! })
    }

    /// Loads a template index from a directory of `*.galley-template` files.
    ///
    /// Every parseable `.galley-template` file becomes one template. A missing or
    /// unreadable directory yields an empty index — a project without templates is
    /// normal. A file whose front-matter names an unknown override token fails its
    /// strict parse and is omitted from the index (the hard rejection happens in
    /// `BlockTemplate.parse`); one bad file never breaks loading the rest.
    ///
    /// - Parameter directory: the package's `templates/` directory URL.
    /// - Returns: an index over the directory's templates, or an empty index.
    public static func load(directory: URL) -> TemplateIndex {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        let entries = files
            .filter { $0.pathExtension.lowercased() == "galley-template" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> BlockTemplate? in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let name = FuzzyMatch.humanize((url.lastPathComponent as NSString).deletingPathExtension)
                return try? BlockTemplate.parse(content, name: name)
            }

        return TemplateIndex(entries: entries)
    }

    /// The templates whose name fuzzy-matches `query`, ranked best-first.
    ///
    /// An empty query returns every template alphabetically — the bare-palette
    /// browse case. A non-empty query keeps only names matching as a subsequence.
    ///
    /// - Parameters:
    ///   - query: the text typed to filter the palette.
    ///   - limit: the maximum number of results; defaults to 8.
    /// - Returns: the matching templates, best first, at most `limit`.
    public func matches(for query: String, limit: Int = 8) -> [BlockTemplate] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return Array(entries.sorted { $0.name.lowercased() < $1.name.lowercased() }.prefix(limit))
        }

        let scored = entries.compactMap { entry -> (entry: BlockTemplate, score: Int)? in
            guard let score = FuzzyMatch.score(query: trimmed, in: entry.name) else { return nil }
            return (entry, score)
        }

        return scored
            .sorted { lhs, rhs in
                lhs.score != rhs.score
                    ? lhs.score > rhs.score
                    : lhs.entry.name.lowercased() < rhs.entry.name.lowercased()
            }
            .prefix(limit)
            .map(\.entry)
    }

    /// The template with the given name, or `nil` if absent. Case-insensitive.
    public func template(named name: String) -> BlockTemplate? {
        entries.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
