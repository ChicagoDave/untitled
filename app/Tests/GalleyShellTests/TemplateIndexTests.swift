//
//  TemplateIndexTests.swift
//  GalleyShellTests
//
//  Behavioral tests for `BlockTemplate.parse` and `TemplateIndex`, derived from
//  their Behavior Statements (BP1). The `load` path runs against real
//  `.galley-template` files on disk — no stub stands in for the filesystem read
//  (Integration Reality, rule 13a, ADR-0020). The override-token assertions check
//  that a template carries the *same* closed vocabulary the sidecar encodes, so a
//  templated block round-trips identically (rule 8b).
//

import Foundation
import Testing
@testable import GalleyShell
import GalleyCore

@Suite("Block template parsing and index loading")
struct TemplateIndexTests {

    // MARK: BlockTemplate.parse — front-matter + body

    @Test func parseReadsOverridesInOrderThenBody() throws {
        let text = "override: align:center\noverride: smallCaps\n\nThe sea does not forget.\n"
        let template = try BlockTemplate.parse(text, name: "Epigraph")
        #expect(template.overrides == [.alignment(.center), .smallCaps])
        #expect(template.body == "The sea does not forget.")
    }

    @Test func parseDecodesBlockQuoteOverride() throws {
        let template = try BlockTemplate.parse("override: blockQuote\n\nSet off from the margin.", name: "Inscription")
        #expect(template.overrides == [.blockQuote])
        #expect(template.body == "Set off from the margin.")
    }

    @Test func parseKeepsMultiParagraphBodyTrimmingOnlyTrailingNewline() throws {
        let text = "override: smallCaps\n\nFirst paragraph.\n\nSecond paragraph.\n"
        let template = try BlockTemplate.parse(text, name: "Two Para")
        #expect(template.body == "First paragraph.\n\nSecond paragraph.")
    }

    @Test func parseTreatsAProseOnlyFileAsAllBodyWithNoOverrides() throws {
        let template = try BlockTemplate.parse("Just a plain reusable block.\n", name: "Plain")
        #expect(template.overrides.isEmpty)
        #expect(template.body == "Just a plain reusable block.")
    }

    // MARK: REJECTS WHEN — unknown override token (hard reject, never silently skipped)

    @Test func parseRejectsAnUnknownOverrideTokenInsteadOfSkippingIt() {
        #expect(throws: TemplateParseError.unknownOverrideToken("blink")) {
            _ = try BlockTemplate.parse("override: align:center\noverride: blink\n\nbody", name: "Bad")
        }
    }

    // MARK: matches / lookup

    @Test func matchesEmptyQueryReturnsAllTemplatesAlphabetically() {
        let index = TemplateIndex(entries: [
            BlockTemplate(name: "Inscription", body: "x", overrides: [.blockQuote]),
            BlockTemplate(name: "Epigraph", body: "y", overrides: [.alignment(.center)]),
        ])
        #expect(index.matches(for: "").map(\.name) == ["Epigraph", "Inscription"])
    }

    @Test func matchesRanksBestFuzzyMatchFirst() {
        let index = TemplateIndex(entries: [
            BlockTemplate(name: "Inscription", body: "x"),
            BlockTemplate(name: "Epigraph", body: "y"),
        ])
        #expect(index.matches(for: "epi").first?.name == "Epigraph")
    }

    @Test func templateNamedIsCaseInsensitive() {
        let index = TemplateIndex(entries: [BlockTemplate(name: "Epigraph", body: "y")])
        #expect(index.template(named: "epigraph")?.body == "y")
        #expect(index.template(named: "nope") == nil)
    }

    // MARK: load (real-path — directory of .galley-template files)

    @Test func loadParsesEveryTemplateFileNamingFromFilenameAndDecodingOverrides() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "override: align:center\noverride: smallCaps\n\nCentered, small caps.\n".write(
            to: dir.appendingPathComponent("epigraph.galley-template"), atomically: true, encoding: .utf8)
        try "override: blockQuote\n\nSet off from the margin.\n".write(
            to: dir.appendingPathComponent("inscription.galley-template"), atomically: true, encoding: .utf8)
        // A non-template file must be ignored.
        try "ignore".write(
            to: dir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        let index = TemplateIndex.load(directory: dir)

        #expect(index.entries.count == 2)
        let epigraph = index.template(named: "Epigraph")
        #expect(epigraph?.overrides == [.alignment(.center), .smallCaps])
        #expect(epigraph?.body == "Centered, small caps.")
        #expect(index.template(named: "Inscription")?.overrides == [.blockQuote])
    }

    @Test func loadOmitsAFileWithAnUnknownOverrideTokenButKeepsTheRest() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "override: smallCaps\n\nGood.\n".write(
            to: dir.appendingPathComponent("good.galley-template"), atomically: true, encoding: .utf8)
        try "override: rainbow\n\nBad.\n".write(
            to: dir.appendingPathComponent("bad.galley-template"), atomically: true, encoding: .utf8)

        let index = TemplateIndex.load(directory: dir)

        // The malformed file is dropped whole — never partially loaded — and the
        // valid template still loads.
        #expect(index.entries.map(\.name) == ["Good"])
    }

    @Test func loadMissingDirectoryYieldsEmptyIndex() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(TemplateIndex.load(directory: missing).entries.isEmpty)
    }

    // MARK: merged — layered library (built-in / user / story), LT1

    @Test func mergedWithNoDirectoriesYieldsTheBuiltInToolkit() {
        let index = TemplateIndex.merged(builtIns: BuiltInTemplates.all, userDirectory: nil, storyDirectory: nil)
        // Every built-in is present even with no project and no user folder.
        for builtin in BuiltInTemplates.all {
            #expect(index.template(named: builtin.name) != nil)
        }
        #expect(index.template(named: "Epigraph")?.overrides == [.alignment(.center), .smallCaps])
    }

    @Test func mergedAddsUserDirectoryTemplatesOnTopOfBuiltIns() throws {
        let userDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: userDir) }
        try "override: align:center\n\nMy salutation.\n".write(
            to: userDir.appendingPathComponent("salutation.galley-template"), atomically: true, encoding: .utf8)

        let index = TemplateIndex.merged(builtIns: BuiltInTemplates.all, userDirectory: userDir, storyDirectory: nil)

        #expect(index.template(named: "Salutation")?.body == "My salutation.")
        #expect(index.template(named: "Epigraph") != nil)   // built-ins still present
    }

    @Test func userTemplateOverridesBuiltInOfSameName() throws {
        let userDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: userDir) }
        // A user "Epigraph" with a different override set must win over the built-in.
        try "override: align:trailing\n\nMine.\n".write(
            to: userDir.appendingPathComponent("epigraph.galley-template"), atomically: true, encoding: .utf8)

        let index = TemplateIndex.merged(builtIns: BuiltInTemplates.all, userDirectory: userDir, storyDirectory: nil)

        #expect(index.template(named: "Epigraph")?.overrides == [.alignment(.trailing)])
        #expect(index.template(named: "Epigraph")?.body == "Mine.")
    }

    @Test func storyTemplateOverridesUserOnSameName() throws {
        let userDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storyDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storyDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: userDir)
            try? FileManager.default.removeItem(at: storyDir)
        }
        try "override: smallCaps\n\nUser dateline.\n".write(
            to: userDir.appendingPathComponent("dateline.galley-template"), atomically: true, encoding: .utf8)
        try "override: align:center\n\nStory dateline.\n".write(
            to: storyDir.appendingPathComponent("dateline.galley-template"), atomically: true, encoding: .utf8)

        let index = TemplateIndex.merged(builtIns: BuiltInTemplates.all, userDirectory: userDir, storyDirectory: storyDir)

        // story > user > built-in
        #expect(index.template(named: "Dateline")?.body == "Story dateline.")
        #expect(index.template(named: "Dateline")?.overrides == [.alignment(.center)])
    }

    // MARK: real-path — the shipped GrayHarbor example templates

    @Test func loadReadsTheGrayHarborExampleTemplates() throws {
        // Resolve examples/GrayHarbor.galley/templates relative to this source file
        // so the test runs from any working directory.
        let here = URL(fileURLWithPath: #filePath)
        let repoRoot = here.deletingLastPathComponent()   // GalleyShellTests
            .deletingLastPathComponent()                   // Tests
            .deletingLastPathComponent()                   // app
            .deletingLastPathComponent()                   // repo root
        let templates = repoRoot
            .appendingPathComponent("examples/GrayHarbor.galley/templates", isDirectory: true)

        let index = TemplateIndex.load(directory: templates)
        #expect(index.template(named: "Epigraph")?.overrides == [.alignment(.center), .smallCaps])
        #expect(index.template(named: "Dateline")?.overrides == [.smallCaps])
        #expect(index.template(named: "Inscription")?.overrides == [.blockQuote])
    }
}
