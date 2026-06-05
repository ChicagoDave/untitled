//
//  Attribution.swift
//  UntitledApp
//
//  Purpose: The shell's attribution step — maps the core's pure `[DisplayToken]`
//  stream (ADR-0006) to an `NSAttributedString` for the editor's text view. This
//  is where the closed typographic vocabulary lives (body indent, verse
//  centering and italic, the scene-break ornament, chapter headings); the model
//  and its projections stay free of fonts and measurements (ADR-0009).
//  Public interface: `Attribution.attributedString(for:)`.
//  Owner context: UntitledApp — the macOS shell's AppKit rendering layer.
//

import AppKit
import UntitledCore

/// Renders a display-token stream into an `NSAttributedString`.
///
/// Stateless and deterministic: the same tokens always produce the same string.
/// Each token becomes one paragraph terminated by a newline, so the resulting
/// string is a sequence of styled paragraphs the text view lays out top to bottom.
enum Attribution {

    // MARK: Typographic vocabulary (the only place concrete type is decided)

    private static let bodySize: CGFloat = 14
    private static let headingSize: CGFloat = 22
    private static let firstLineIndent: CGFloat = 24
    private static let paragraphSpacing: CGFloat = 8
    private static let blockSpacing: CGFloat = 16

    private static var bodyFont: NSFont {
        NSFont(name: "Georgia", size: bodySize) ?? NSFont.systemFont(ofSize: bodySize)
    }

    private static var headingFont: NSFont {
        NSFont(name: "Georgia-Bold", size: headingSize)
            ?? NSFont.boldSystemFont(ofSize: headingSize)
    }

    /// Maps a display-token stream to a styled attributed string.
    ///
    /// - Parameter tokens: the projection from `Document.displayProjection()`.
    /// - Returns: one styled paragraph per token, concatenated.
    static func attributedString(for tokens: [DisplayToken]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for token in tokens {
            switch token {
            case .paragraph(let spans, let overrides):
                out.append(bodyParagraph(spans, overrides: overrides))
            case .sceneBreak:
                out.append(ornament("* * *"))
            case .setPieceLine(let kind, let spans, let overrides):
                out.append(setPieceLine(kind: kind, spans: spans, overrides: overrides))
            case .chapterStart(let title):
                out.append(chapterHeading(title))
            }
        }
        return out
    }

    // MARK: Block renderers

    /// A body paragraph: serif body font, first-line indent, leading alignment
    /// unless an override says otherwise.
    private static func bodyParagraph(_ spans: [DisplaySpan], overrides: [PresentationOverride]) -> NSAttributedString {
        let style = paragraphStyle(
            alignment: alignment(from: overrides) ?? .natural,
            firstLineIndent: alignment(from: overrides) == nil ? firstLineIndent : 0,
            spacingAfter: paragraphSpacing
        )
        return line(spans, baseFont: font(bodyFont, smallCaps: hasSmallCaps(overrides)), derivedItalic: false, style: style)
    }

    /// A set-piece line: centered and italic for verse/epigraph, leading for a
    /// letter; the block's overrides still win on alignment.
    private static func setPieceLine(kind: SetPieceKind, spans: [DisplaySpan], overrides: [PresentationOverride]) -> NSAttributedString {
        let derivedAlignment: NSTextAlignment
        let derivedItalic: Bool
        switch kind {
        case .verse, .epigraph:
            derivedAlignment = .center
            derivedItalic = true
        case .letter:
            derivedAlignment = .natural
            derivedItalic = false
        }
        let style = paragraphStyle(
            alignment: alignment(from: overrides) ?? derivedAlignment,
            firstLineIndent: 0,
            spacingAfter: paragraphSpacing
        )
        return line(spans, baseFont: font(bodyFont, smallCaps: hasSmallCaps(overrides)), derivedItalic: derivedItalic, style: style)
    }

    /// The scene-break ornament, centered with generous spacing.
    private static func ornament(_ glyphs: String) -> NSAttributedString {
        let style = paragraphStyle(alignment: .center, firstLineIndent: 0, spacingBefore: blockSpacing, spacingAfter: blockSpacing)
        return NSAttributedString(string: glyphs + "\n", attributes: [
            .font: bodyFont,
            .paragraphStyle: style,
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    /// A chapter heading: bold serif, centered, with space above and below. A
    /// titleless cut renders a centered divider so the boundary is still visible.
    private static func chapterHeading(_ title: String?) -> NSAttributedString {
        let style = paragraphStyle(alignment: .center, firstLineIndent: 0, spacingBefore: blockSpacing * 2, spacingAfter: blockSpacing)
        let text = (title?.isEmpty == false ? title! : "·   ·   ·")
        return NSAttributedString(string: text + "\n", attributes: [
            .font: headingFont,
            .paragraphStyle: style,
            .foregroundColor: NSColor.labelColor,
        ])
    }

    // MARK: Inline spans

    /// Builds one paragraph's attributed text from its spans, terminated by a
    /// newline. A span is italic if it carries the explicit mark or the block
    /// derives italic (e.g. verse).
    private static func line(_ spans: [DisplaySpan], baseFont: NSFont, derivedItalic: Bool, style: NSParagraphStyle) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for span in spans {
            let italic = derivedItalic || span.italic
            let runFont = italic ? italicized(baseFont) : baseFont
            out.append(NSAttributedString(string: span.text, attributes: [
                .font: runFont,
                .paragraphStyle: style,
                .foregroundColor: NSColor.labelColor,
            ]))
        }
        out.append(NSAttributedString(string: "\n", attributes: [.font: baseFont, .paragraphStyle: style]))
        return out
    }

    // MARK: Font / style helpers

    private static func italicized(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    /// Applies the small-caps OpenType feature, falling back to the input font if
    /// the face lacks it.
    private static func font(_ font: NSFont, smallCaps: Bool) -> NSFont {
        guard smallCaps else { return font }
        let descriptor = font.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kLowerCaseType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kLowerCaseSmallCapsSelector,
            ]],
        ])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    private static func alignment(from overrides: [PresentationOverride]) -> NSTextAlignment? {
        for case let .alignment(a) in overrides {
            switch a {
            case .leading: return .left
            case .center: return .center
            case .trailing: return .right
            }
        }
        return nil
    }

    private static func hasSmallCaps(_ overrides: [PresentationOverride]) -> Bool {
        overrides.contains(.smallCaps)
    }

    private static func paragraphStyle(
        alignment: NSTextAlignment,
        firstLineIndent: CGFloat,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.firstLineHeadIndent = firstLineIndent
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.lineHeightMultiple = 1.2
        return style
    }
}
