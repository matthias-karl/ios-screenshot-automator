import CoreGraphics
import CoreText
import Foundation

/// Fits title and subtitle into the caption area: bold title (at most 2 lines), regular subtitle (1 line).
public enum CaptionLayout {
    static let titleSizeFactor = 0.042
    static let subtitleSizeFactor = 0.026
    static let minimumScale = 0.6
    static let scaleStep = 0.05

    struct Result {
        var title: String
        var subtitle: String?
        var titleSize: Double
        var subtitleSize: Double
        var titleLines: Int
        var titleHeight: Double
        var subtitleHeight: Double
        var gap: Double
    }

    public static func fit(
        title: String, subtitle: String?, in rect: CGRect, canvasHeight: Double, fontPath: String?
    ) throws -> (titleSize: Double, subtitleSize: Double, lines: Int) {
        let result = try layout(title: title, subtitle: subtitle, in: rect, canvasHeight: canvasHeight, fontPath: fontPath)
        return (result.titleSize, result.subtitleSize, result.titleLines)
    }

    // MARK: Layout

    static func layout(title: String, subtitle: String?, in rect: CGRect, canvasHeight: Double, fontPath: String?) throws -> Result {
        let hasSubtitle = !(subtitle ?? "").isEmpty
        var title = title
        var subtitle = hasSubtitle ? subtitle : nil

        func measured(scale: Double) throws -> Result {
            let titleSize = titleSizeFactor * canvasHeight * scale
            let subtitleSize = subtitleSizeFactor * canvasHeight * scale
            let titleFont = try font(path: fontPath, size: titleSize, bold: true)
            let titleMetrics = title.isEmpty ? (lines: 0, height: 0.0) : measure(title, font: titleFont, width: rect.width)
            var subtitleMetrics = (lines: 0, height: 0.0)
            if let subtitle {
                subtitleMetrics = measure(subtitle, font: try font(path: fontPath, size: subtitleSize, bold: false), width: rect.width)
            }
            let gap = (titleMetrics.lines > 0 && subtitleMetrics.lines > 0) ? 0.3 * subtitleSize : 0
            return Result(title: title, subtitle: subtitle, titleSize: titleSize, subtitleSize: subtitleSize,
                          titleLines: titleMetrics.lines, titleHeight: titleMetrics.height,
                          subtitleHeight: subtitleMetrics.height, gap: gap)
        }
        func subtitleLines(_ r: Result) throws -> Int {
            guard let s = r.subtitle else { return 0 }
            return measure(s, font: try font(path: fontPath, size: r.subtitleSize, bold: false), width: rect.width).lines
        }
        func fits(_ r: Result) throws -> Bool {
            guard r.titleLines <= 2 else { return false }
            guard try subtitleLines(r) <= 1 else { return false }
            return r.titleHeight + r.gap + r.subtitleHeight <= rect.height
        }

        // 100 %, 95 %, … 60 % of the start size.
        var scale = 1.0
        while scale >= minimumScale - 1e-9 {
            let candidate = try measured(scale: scale)
            if try fits(candidate) { return candidate }
            scale -= scaleStep
        }

        // Still too long at 60 %: shorten with "…", subtitle first, then title.
        scale = minimumScale
        if subtitle != nil {
            subtitle = try truncated(subtitle!) { text in
                subtitle = text
                let r = try measured(scale: scale)
                return try subtitleLines(r) <= 1
            }
        }
        if !title.isEmpty {
            title = try truncated(title) { text in
                title = text
                return try fits(try measured(scale: scale))
            }
        }
        return try measured(scale: scale)
    }

    /// Removes characters from the end (never half a grapheme) until `fits` accepts `text + "…"`.
    private static func truncated(_ text: String, fits: (String) throws -> Bool) throws -> String {
        if try fits(text) { return text }
        var characters = Array(text)
        while characters.count > 1 {
            characters.removeLast()
            let candidate = String(characters).trimmingCharacters(in: .whitespaces) + "…"
            if try fits(candidate) { return candidate }
        }
        return "…"
    }

    // MARK: CoreText

    static func font(path: String?, size: Double, bold: Bool) throws -> CTFont {
        if let path {
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: path) as CFURL) as? [CTFontDescriptor],
                  let descriptor = descriptors.first
            else { throw ComposeError.fontUnreadable(path) }
            return CTFontCreateWithFontDescriptor(descriptor, size, nil)
        }
        return CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    static func attributed(_ text: String, font: CTFont, color: CGColor) -> CFAttributedString {
        var alignment = CTTextAlignment.center
        let paragraph = withUnsafeMutablePointer(to: &alignment) { pointer in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
            kCTParagraphStyleAttributeName: paragraph,
        ]
        return CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
    }

    static func measure(_ text: String, font: CTFont, width: Double) -> (lines: Int, height: Double) {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed(text, font: font, color: CGColor(gray: 0, alpha: 1)))
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0), CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 100_000), transform: nil), nil)
        let lines = (CTFrameGetLines(frame) as? [CTLine])?.count ?? 0
        return (lines, size.height.rounded(.up))
    }

    /// Draws centered text with its top edge at `top` (CG coordinates) inside `width`.
    static func draw(_ text: String, font: CTFont, color: CGColor, x: Double, top: Double, width: Double, height: Double, in context: CGContext) {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed(text, font: font, color: color))
        let path = CGPath(rect: CGRect(x: x, y: top - height, width: width, height: height), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}
