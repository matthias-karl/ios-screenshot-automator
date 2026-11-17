import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ComposeRequest {
    public var screenshot: CGImage
    public var canvas: PixelSize
    public var display: DisplaySpec?
    public var hasDynamicIsland: Bool
    public var platform: Platform
    public var style: Config.Style
    public var title: String?
    public var subtitle: String?
    public var frameImage: CGImage?

    public init(
        screenshot: CGImage, canvas: PixelSize, display: DisplaySpec?, hasDynamicIsland: Bool, platform: Platform,
        style: Config.Style, title: String?, subtitle: String?, frameImage: CGImage?
    ) {
        self.screenshot = screenshot
        self.canvas = canvas
        self.display = display
        self.hasDynamicIsland = hasDynamicIsland
        self.platform = platform
        self.style = style
        self.title = title
        self.subtitle = subtitle
        self.frameImage = frameImage
    }
}

public enum ComposeError: Error, Equatable, CustomStringConvertible {
    case badColor(String)
    case frameAspectMismatch(expected: Double, actual: Double)
    case fontUnreadable(String)
    case missingFrameImage

    public var description: String {
        switch self {
        case .badColor(let value): return "\"\(value)\" is not a color like #RRGGBB"
        case .frameAspectMismatch(let expected, let actual):
            return String(format: "The screen area of the frame image has aspect ratio %.3f, but the screenshot has %.3f.", actual, expected)
        case .fontUnreadable(let path): return "Cannot load the font at \(path)"
        case .missingFrameImage: return "Frame \"image\" needs a frame image, but none was loaded."
        }
    }
}

public enum Composer {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Background, frame and (later) caption in the exact canvas size, without alpha channel.
    public static func compose(_ r: ComposeRequest) throws -> CGImage {
        let style = r.style
        // Validate every color up front so errors do not depend on which branch draws it.
        let background = try Colors.background(style.background)
        let frameColor = try Colors.cgColor(style.frameColor)

        let width = r.canvas.width, height = r.canvas.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ComposeError.badColor("(cannot create a \(width)×\(height) context)") }
        context.interpolationQuality = .high
        context.setShouldAntialias(true)

        drawBackground(background, in: context, size: r.canvas)

        let screenshotSize = PixelSize(width: r.screenshot.width, height: r.screenshot.height)
        let frame = r.platform == .macOS ? Config.Frame.none : style.frame
        let ringFactor = frame == .bezel ? Layout.bezelRingFactor : 0

        // Text only when a caption style is set (`caption: null` switches captions off).
        let title = r.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subtitle = r.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let captionRect: CGRect? = {
            guard let caption = style.caption, !title.isEmpty || !subtitle.isEmpty else { return nil }
            return Layout.captionRect(canvas: r.canvas, position: caption.position)
        }()
        let captionColor = try style.caption.map { try Colors.cgColor($0.color) }
        // Resolve the font before drawing anything, so an unreadable font fails early.
        var captionLayout: CaptionLayout.Result?
        if let captionRect, let caption = style.caption {
            captionLayout = try CaptionLayout.layout(
                title: title, subtitle: subtitle.isEmpty ? nil : subtitle, in: captionRect,
                canvasHeight: Double(height), fontPath: caption.font)
        }

        if frame == .image && r.platform != .macOS {
            guard let frameImage = r.frameImage else { throw ComposeError.missingFrameImage }
            let hole = try FrameImage.screenRect(in: frameImage)
            let expected = Double(screenshotSize.width) / Double(screenshotSize.height)
            let actual = hole.width / hole.height
            guard abs(actual / expected - 1) <= 0.01 else {
                throw ComposeError.frameAspectMismatch(expected: expected, actual: actual)
            }
            let frameRect = Layout.deviceRect(
                canvas: r.canvas, screenshot: PixelSize(width: frameImage.width, height: frameImage.height),
                caption: captionRect, ringWidthFactor: 0)
            let scale = frameRect.width / Double(frameImage.width)
            let screen = CGRect(x: frameRect.minX + hole.minX * scale, y: frameRect.minY + hole.minY * scale,
                                width: hole.width * scale, height: hole.height * scale)
            context.draw(r.screenshot, in: flipped(screen, canvasHeight: height))
            context.draw(frameImage, in: flipped(frameRect, canvasHeight: height))
        } else {
            let rect = Layout.deviceRect(canvas: r.canvas, screenshot: screenshotSize, caption: captionRect, ringWidthFactor: ringFactor)
            let cgRect = flipped(rect, canvasHeight: height)

            if r.platform == .macOS {
                drawMacWindow(r.screenshot, in: cgRect, canvas: r.canvas, context: context)
            } else {
                let radii = r.display.map { Layout.cornerRadii(display: $0, drawnWidth: rect.width) } ?? .zero
                switch frame {
                case .bezel:
                    let ring = Layout.bezelRingFactor * rect.width
                    context.setFillColor(frameColor)
                    context.addPath(roundedPath(cgRect.insetBy(dx: -ring, dy: -ring), radii.expanded(by: ring)))
                    context.fillPath()
                    drawScreenshot(r.screenshot, in: cgRect, radii: radii, context: context)
                case .outline, .image:
                    drawScreenshot(r.screenshot, in: cgRect, radii: radii, context: context)
                    let line = 0.006 * min(rect.width, rect.height)
                    context.setStrokeColor(frameColor)
                    context.setLineWidth(line)
                    context.addPath(roundedPath(cgRect.insetBy(dx: line / 2, dy: line / 2), radii.expanded(by: -line / 2)))
                    context.strokePath()
                case .none:
                    drawScreenshot(r.screenshot, in: cgRect, radii: radii, context: context)
                }
                if r.hasDynamicIsland, r.display?.name == "primary", !screenshotSize.isLandscape, frame == .outline || frame == .bezel {
                    drawIsland(in: cgRect, color: frameColor, context: context)
                }
            }
        }

        if let captionRect, let captionLayout, let caption = style.caption, let captionColor {
            try drawCaption(captionLayout, in: captionRect, caption: caption, color: captionColor, canvasHeight: height, context: context)
        }
        return context.makeImage()!
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    // MARK: - Drawing

    private static func drawBackground(_ background: Colors.Background, in context: CGContext, size: PixelSize) {
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        switch background {
        case .color(let color):
            context.setFillColor(color)
            context.fill(rect)
        case .gradient(let colors, let angle):
            // Direction in screen coordinates (y down): 0° = left→right, 90° = top→bottom.
            // The line is long enough that the corners reach the end colors.
            let radians = angle * .pi / 180
            let dx = cos(radians), dy = sin(radians)   // y down
            let length = abs(rect.width * dx) + abs(rect.height * dy)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            // Convert to CG (y up): flip dy.
            let start = CGPoint(x: center.x - dx * length / 2, y: center.y + dy * length / 2)
            let end = CGPoint(x: center.x + dx * length / 2, y: center.y - dy * length / 2)
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil)!
            context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    private static func drawScreenshot(_ image: CGImage, in rect: CGRect, radii: CornerRadii, context: CGContext) {
        context.saveGState()
        context.addPath(roundedPath(rect, radii))
        context.clip()
        context.draw(image, in: rect)
        context.restoreGState()
    }

    /// Mac: the window as it is (with its own transparent corners) plus a soft shadow, no frame.
    private static func drawMacWindow(_ image: CGImage, in rect: CGRect, canvas: PixelSize, context: CGContext) {
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -0.012 * Double(canvas.height)), blur: 0.03 * Double(canvas.height),
            color: CGColor(colorSpace: colorSpace, components: [0, 0, 0, 0.35])!)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    /// A black capsule: 31 % of the screen width wide, 9.2 % high, 3.5 % below the top edge.
    private static func drawIsland(in screen: CGRect, color: CGColor, context: CGContext) {
        let width = 0.31 * screen.width, height = 0.092 * screen.width, top = 0.035 * screen.width
        let capsule = CGRect(x: screen.midX - width / 2, y: screen.maxY - top - height, width: width, height: height)
        context.setFillColor(color)
        context.addPath(roundedPath(capsule, CornerRadii(upperLeft: height / 2, upperRight: height / 2, lowerLeft: height / 2, lowerRight: height / 2)))
        context.fillPath()
    }

    private static func drawCaption(
        _ layout: CaptionLayout.Result, in rect: CGRect, caption: Config.Caption, color: CGColor,
        canvasHeight: Int, context: CGContext
    ) throws {
        let block = layout.titleHeight + layout.gap + layout.subtitleHeight
        let topLeftTop = rect.midY - block / 2                       // top of the text block, y down
        let cgRect = flipped(rect, canvasHeight: canvasHeight)
        context.saveGState()
        context.clip(to: cgRect)                                      // text never leaves the caption area
        var cursor = Double(canvasHeight) - topLeftTop                 // y up
        if layout.titleLines > 0 {
            let font = try CaptionLayout.font(path: caption.font, size: layout.titleSize, bold: true)
            CaptionLayout.draw(layout.title, font: font, color: color, x: rect.minX, top: cursor,
                               width: rect.width, height: layout.titleHeight, in: context)
            cursor -= layout.titleHeight + layout.gap
        }
        if let subtitle = layout.subtitle {
            let font = try CaptionLayout.font(path: caption.font, size: layout.subtitleSize, bold: false)
            CaptionLayout.draw(subtitle, font: font, color: color, x: rect.minX, top: cursor,
                               width: rect.width, height: layout.subtitleHeight, in: context)
        }
        context.restoreGState()
    }

    // MARK: - Geometry helpers

    /// Top-left rect → CoreGraphics (y up) rect.
    static func flipped(_ rect: CGRect, canvasHeight: Int) -> CGRect {
        CGRect(x: rect.minX, y: Double(canvasHeight) - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Rounded rectangle with individual radii. `rect` is in CG coordinates (y up), so "upper" is `maxY`.
    static func roundedPath(_ rect: CGRect, _ radii: CornerRadii) -> CGPath {
        var ul = max(0, radii.upperLeft), ur = max(0, radii.upperRight)
        var ll = max(0, radii.lowerLeft), lr = max(0, radii.lowerRight)
        // Radii that do not fit a side are scaled down together (like CSS).
        let w = rect.width, h = rect.height
        var factor = 1.0
        for (sum, side) in [(ul + ur, w), (ll + lr, w), (ul + ll, h), (ur + lr, h)] where sum > side && sum > 0 {
            factor = min(factor, side / sum)
        }
        ul *= factor; ur *= factor; ll *= factor; lr *= factor

        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + ll, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - lr, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + lr), radius: lr)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - ur))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - ur, y: rect.maxY), radius: ur)
        path.addLine(to: CGPoint(x: rect.minX + ul, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - ul), radius: ul)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + ll))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + ll, y: rect.minY), radius: ll)
        path.closeSubpath()
        return path
    }
}

extension CornerRadii {
    func expanded(by amount: Double) -> CornerRadii {
        CornerRadii(upperLeft: max(0, upperLeft + amount), upperRight: max(0, upperRight + amount),
                    lowerLeft: max(0, lowerLeft + amount), lowerRight: max(0, lowerRight + amount))
    }
}

enum Colors {
    enum Background {
        case color(CGColor)
        case gradient([CGColor], angle: Double)
    }

    static func cgColor(_ hex: String) throws -> CGColor {
        guard let rgba = RGBA(hex: hex) else { throw ComposeError.badColor(hex) }
        return CGColor(colorSpace: Composer.colorSpace, components: [
            CGFloat(rgba.red) / 255, CGFloat(rgba.green) / 255, CGFloat(rgba.blue) / 255, 1,
        ])!
    }

    static func background(_ background: Config.Background) throws -> Background {
        switch background {
        case .color(let hex): return .color(try cgColor(hex))
        case .gradient(let stops, let angle): return .gradient(try stops.map(cgColor), angle: angle)
        }
    }
}
