//
//  Attribution.swift
//  Galley
//
//  Purpose: The shell's attribution step — maps the core's pure `[DisplayToken]`
//  stream (ADR-0006) to an `NSAttributedString` for the editor's text view. This
//  is where the closed typographic vocabulary lives (body indent, verse
//  centering and italic, the scene-break ornament, chapter headings); the model
//  and its projections stay free of fonts and measurements (ADR-0009).
//  Public interface: `Attribution.attributedString(for:)`.
//  Owner context: Galley — the macOS shell's AppKit rendering layer.
//

import AppKit
import GalleyCore

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
    /// Margin inset applied to both edges of a `blockQuote` paragraph.
    private static let blockQuoteIndent: CGFloat = 36

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
            case .chapterStart(let role, let title):
                out.append(chapterHeading(role: role, title: title))
            case .figure(let imageRef, let caption):
                out.append(figureBox(imageRef: imageRef))
                out.append(figureCaption(caption))
            }
        }
        return out
    }

    // MARK: Block renderers

    /// A body paragraph: serif body font, first-line indent, leading alignment
    /// unless an override says otherwise. A `blockQuote` override sets the block
    /// off with a symmetric margin inset and no first-line indent.
    private static func bodyParagraph(_ spans: [DisplaySpan], overrides: [PresentationOverride]) -> NSAttributedString {
        let explicitAlignment = alignment(from: overrides)
        let style: NSParagraphStyle
        if hasBlockQuote(overrides) {
            style = paragraphStyle(
                alignment: explicitAlignment ?? .natural,
                firstLineIndent: blockQuoteIndent,
                spacingAfter: paragraphSpacing,
                headIndent: blockQuoteIndent,
                tailIndent: -blockQuoteIndent
            )
        } else {
            style = paragraphStyle(
                alignment: explicitAlignment ?? .natural,
                firstLineIndent: explicitAlignment == nil ? firstLineIndent : 0,
                spacingAfter: paragraphSpacing
            )
        }
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

    /// The figure placeholder box (LT4-2): a drawn rounded-rect `NSTextAttachment`
    /// showing a photo glyph + the image reference in monospaced type — Galley shows
    /// intent, never the image (ADR-0024). A non-editable boundary segment (the caret
    /// never enters it, like a scene break); the caption beneath it is the editable
    /// part. Rendered as its own paragraph so `EditorLayout` can map it to one
    /// segment. Internal so `EditorLayout` composes the two figure segments.
    static func figureBox(imageRef: String) -> NSAttributedString {
        let style = paragraphStyle(alignment: .center, firstLineIndent: 0, spacingBefore: blockSpacing, spacingAfter: 4)
        let box = NSTextAttachment()
        box.image = figureBoxImage(imageRef.isEmpty ? "(image ref)" : imageRef)
        let size = box.image!.size
        box.bounds = NSRect(x: 0, y: bodyFont.descender, width: size.width, height: size.height)
        let out = NSMutableAttributedString(attachment: box)
        out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: out.length))
        out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
        return out
    }

    /// The figure caption line (LT4-2, ADR-0028 Option A): the writer's caption
    /// beneath the box, in a small italic secondary style. Rendered as its *literal*
    /// text — an empty caption is an empty editable line — so the editor's
    /// character↔offset mapping over this segment stays exact. No inline "(caption)"
    /// placeholder text is injected: it would desync the editable segment's offsets,
    /// and the box above already identifies the block. Internal so `EditorLayout`
    /// maps it to the figure's editable caption segment.
    static func figureCaption(_ caption: String) -> NSAttributedString {
        let style = paragraphStyle(alignment: .center, firstLineIndent: 0, spacingAfter: blockSpacing)
        let captionFont = NSFont(descriptor: bodyFont.fontDescriptor.withSymbolicTraits(.italic), size: bodyFont.pointSize - 1) ?? bodyFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: captionFont,
            .paragraphStyle: style,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let out = NSMutableAttributedString(string: caption, attributes: attributes)
        out.append(NSAttributedString(string: "\n", attributes: attributes))
        return out
    }

    /// Draws the figure placeholder box image: a rounded rectangle with a subtle
    /// fill and border, a photo glyph, and `label` in monospaced type. Backing-scale
    /// aware so it stays crisp on Retina.
    private static func figureBoxImage(_ label: String) -> NSImage {
        let text = "🖼  \(label)"
        let font = NSFont.monospacedSystemFont(ofSize: bodySize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let horizontalPadding: CGFloat = 14
        let verticalPadding: CGFloat = 10
        let size = NSSize(width: ceil(textSize.width) + horizontalPadding * 2,
                          height: ceil(textSize.height) + verticalPadding * 2)
        return NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 0.5, dy: 0.5)
            let box = NSBezierPath(roundedRect: inset, xRadius: 8, yRadius: 8)
            NSColor.quaternaryLabelColor.withAlphaComponent(0.4).setFill()
            box.fill()
            box.lineWidth = 1
            NSColor.tertiaryLabelColor.setStroke()
            box.stroke()
            (text as NSString).draw(at: NSPoint(x: horizontalPadding, y: verticalPadding), withAttributes: attributes)
            return true
        }
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

    /// A chapter heading: bold serif, centered, with space above and below. The
    /// heading text is the title when set; otherwise the role name for a non-chapter
    /// section (Prologue / Epilogue / Dedication); otherwise — an untitled chapter —
    /// a centered divider so the boundary is still visible (ADR-0026).
    private static func chapterHeading(role: SectionRole, title: String?) -> NSAttributedString {
        let style = paragraphStyle(alignment: .center, firstLineIndent: 0, spacingBefore: blockSpacing * 2, spacingAfter: blockSpacing)
        let text: String
        if let title {
            // A non-nil title — including the empty string while its heading is being
            // edited — renders verbatim, so the editable region matches the model.
            text = title
        } else if role != .chapter {
            text = roleName(role)            // legacy: roleless title falls back to the role
        } else {
            text = "·   ·   ·"               // legacy: an untitled chapter shows a divider
        }
        return NSAttributedString(string: text + "\n", attributes: [
            .font: headingFont,
            .paragraphStyle: style,
            .foregroundColor: NSColor.labelColor,
        ])
    }

    /// A break-deletion confirmation heading (LT3): the heading becomes a reveal-style
    /// rounded chip (the title on an accent capsule) with plain `Delete [Y/N]?` text
    /// beside it, so removing a break is a deliberate, visible Y/N answer — not a
    /// silent prose merge. Left-aligned, matching the reveal chip's look.
    static func deletePrompt(title: String) -> NSAttributedString {
        let style = paragraphStyle(alignment: .natural, firstLineIndent: 0, spacingBefore: blockSpacing * 2, spacingAfter: blockSpacing)
        let out = NSMutableAttributedString()

        let chip = NSTextAttachment()
        chip.image = chipImage(title.isEmpty ? "Break" : title)
        let chipSize = chip.image!.size
        chip.bounds = NSRect(x: 0, y: bodyFont.descender, width: chipSize.width, height: chipSize.height)
        let chipString = NSMutableAttributedString(attachment: chip)
        chipString.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: chipString.length))
        out.append(chipString)

        out.append(NSAttributedString(string: "  Delete [Y/N]?", attributes: [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]))
        out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
        return out
    }

    /// Draws a rounded-capsule chip with `text` (accent fill, white label), matching
    /// the reveal pane's chip. Backing-scale aware so it stays crisp on Retina.
    private static func chipImage(_ text: String) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 3
        let size = NSSize(width: ceil(textSize.width) + horizontalPadding * 2,
                          height: ceil(textSize.height) + verticalPadding * 2)
        return NSImage(size: size, flipped: false) { rect in
            let radius = rect.height / 2
            let capsule = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            NSColor.controlAccentColor.setFill()
            capsule.fill()
            (text as NSString).draw(at: NSPoint(x: horizontalPadding, y: verticalPadding), withAttributes: attributes)
            return true
        }
    }

    /// The display name of a section role (ADR-0026).
    private static func roleName(_ role: SectionRole) -> String {
        switch role {
        case .chapter: return "Chapter"
        case .prologue: return "Prologue"
        case .epilogue: return "Epilogue"
        case .dedication: return "Dedication"
        }
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

    private static func hasBlockQuote(_ overrides: [PresentationOverride]) -> Bool {
        overrides.contains(.blockQuote)
    }

    private static func paragraphStyle(
        alignment: NSTextAlignment,
        firstLineIndent: CGFloat,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 0,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.firstLineHeadIndent = firstLineIndent
        style.headIndent = headIndent
        style.tailIndent = tailIndent
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.lineHeightMultiple = 1.2
        return style
    }
}
