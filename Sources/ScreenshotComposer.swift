//
//  ScreenshotComposer.swift
//  ios-screenshot-automator
//
//  Composes raw screenshots into App Store-ready images with
//  customizable gradient backgrounds and device frames.
//
//  Requires: Swift 5.9+ / iOS 16+
//

import UIKit

// MARK: - Configuration

/// Direction of the gradient background.
public enum GradientDirection {
    case topToBottom
    case bottomToTop
    case leftToRight
    case rightToLeft
    case topLeftToBottomRight
    case topRightToBottomLeft

    /// Returns the start and end points for the gradient in the unit coordinate space.
    var points: (start: CGPoint, end: CGPoint) {
        switch self {
        case .topToBottom:
            return (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
        case .bottomToTop:
            return (CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0))
        case .leftToRight:
            return (CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5))
        case .rightToLeft:
            return (CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5))
        case .topLeftToBottomRight:
            return (CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1))
        case .topRightToBottomLeft:
            return (CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1))
        }
    }
}

/// Style of the device frame drawn around the screenshot.
public enum DeviceFrameStyle {
    /// No frame – screenshot is placed directly on the gradient.
    case none
    /// Generic rounded-rectangle frame suitable for any device.
    case generic
    /// iPhone-shaped frame with narrower bezels and larger corner radius.
    case iPhone
    /// iPad-shaped frame with wider bezels and smaller corner radius.
    case iPad
    /// Automatically selects `.iPhone` or `.iPad` based on the current device idiom.
    case automatic
}

/// Configuration for composing screenshots into App Store-ready images.
///
/// ## Quick Start
/// ```swift
/// let config = ScreenshotComposerConfig(
///     gradientColors: [.systemBlue, .systemPurple]
/// )
/// ```
///
/// ## Custom Example
/// ```swift
/// let config = ScreenshotComposerConfig(
///     gradientColors: [UIColor(red: 0.2, green: 0.1, blue: 0.5, alpha: 1),
///                      UIColor(red: 0.8, green: 0.3, blue: 0.6, alpha: 1)],
///     gradientDirection: .topLeftToBottomRight,
///     deviceFrameStyle: .iPhone,
///     frameColor: .black,
///     screenshotScale: 0.75,
///     frameCornerRadius: 40
/// )
/// ```
public struct ScreenshotComposerConfig {

    /// Colors for the gradient background (minimum 2).
    public var gradientColors: [UIColor]

    /// Direction of the gradient.
    public var gradientDirection: GradientDirection

    /// Style of the device frame overlay.
    public var deviceFrameStyle: DeviceFrameStyle

    /// Color of the device frame bezel.
    public var frameColor: UIColor

    /// How much of the canvas the screenshot occupies (0.1–1.0).
    /// For example, `0.75` means the device takes up 75% of the height.
    /// Values below 0.1 are clamped to 0.1 to keep the screenshot visible.
    public var screenshotScale: CGFloat

    /// Corner radius of the device frame in points (set to 0 for sharp corners).
    /// When `nil`, a device-appropriate default is used.
    public var frameCornerRadius: CGFloat?

    /// Width of the device frame bezel in points.
    /// When `nil`, a device-appropriate default is used.
    public var frameBezelWidth: CGFloat?

    /// Creates a new composer configuration.
    ///
    /// - Parameters:
    ///   - gradientColors: At least two colors for the background gradient.
    ///   - gradientDirection: Direction of the gradient. Default is `.topToBottom`.
    ///   - deviceFrameStyle: Frame style. Default is `.automatic`.
    ///   - frameColor: Bezel color. Default is `.black`.
    ///   - screenshotScale: How much of the canvas the device occupies (0.1–1.0). Default is `0.75`.
    ///   - frameCornerRadius: Custom corner radius for the frame, or `nil` for a device-appropriate default.
    ///   - frameBezelWidth: Custom bezel width, or `nil` for a device-appropriate default.
    public init(
        gradientColors: [UIColor] = [.systemBlue, .systemPurple],
        gradientDirection: GradientDirection = .topToBottom,
        deviceFrameStyle: DeviceFrameStyle = .automatic,
        frameColor: UIColor = .black,
        screenshotScale: CGFloat = 0.75,
        frameCornerRadius: CGFloat? = nil,
        frameBezelWidth: CGFloat? = nil
    ) {
        self.gradientColors = gradientColors
        self.gradientDirection = gradientDirection
        self.deviceFrameStyle = deviceFrameStyle
        self.frameColor = frameColor
        self.screenshotScale = screenshotScale
        self.frameCornerRadius = frameCornerRadius
        self.frameBezelWidth = frameBezelWidth
    }

    /// A default configuration with a blue-to-purple gradient and automatic device frame.
    public static let `default` = ScreenshotComposerConfig()
}

// MARK: - Per-screenshot overrides

/// Optional per-screenshot overrides for the composer configuration.
///
/// Set any property to override the base configuration for a single screenshot.
/// Properties left as `nil` fall through to the values in `ScreenshotComposerConfig`.
public struct ScreenshotComposerOverride {
    public var gradientColors: [UIColor]?
    public var gradientDirection: GradientDirection?

    public init(
        gradientColors: [UIColor]? = nil,
        gradientDirection: GradientDirection? = nil
    ) {
        self.gradientColors = gradientColors
        self.gradientDirection = gradientDirection
    }
}

// MARK: - Composer

/// Composes a raw screenshot into an App Store-ready image.
///
/// The composer:
/// 1. Creates a canvas matching the original screenshot dimensions.
/// 2. Draws a configurable gradient background.
/// 3. Optionally draws a device frame (bezel).
/// 4. Centers the (scaled) screenshot inside the frame.
///
/// Usage is automatic when a `composerConfig` is set on `ScreenshotTestBase`.
public struct ScreenshotComposer {

    /// Compose a screenshot image into an App Store-ready image.
    ///
    /// - Parameters:
    ///   - screenshotData: Raw PNG data of the captured screenshot.
    ///   - config: Composer configuration.
    ///   - override: Optional per-screenshot overrides.
    /// - Returns: PNG data of the composed image, or the original data on failure.
    public static func compose(
        screenshotData: Data,
        config: ScreenshotComposerConfig,
        override: ScreenshotComposerOverride? = nil
    ) -> Data {
        guard let originalImage = UIImage(data: screenshotData) else {
            return screenshotData
        }

        let canvasSize = originalImage.size
        let scale = originalImage.scale

        let renderer = UIGraphicsImageRenderer(
            size: canvasSize,
            format: {
                let fmt = UIGraphicsImageRendererFormat()
                fmt.scale = scale
                fmt.opaque = true
                return fmt
            }()
        )

        let composedImage = renderer.image { context in
            let ctx = context.cgContext
            let rect = CGRect(origin: .zero, size: canvasSize)

            // 1. Draw gradient background
            drawGradient(
                in: ctx,
                rect: rect,
                colors: override?.gradientColors ?? config.gradientColors,
                direction: override?.gradientDirection ?? config.gradientDirection
            )

            // 2. Determine frame style
            let resolvedStyle = resolveFrameStyle(config.deviceFrameStyle)

            // 3. Calculate device rect (centered, scaled)
            let deviceRect = calculateDeviceRect(
                canvasSize: canvasSize,
                screenshotScale: config.screenshotScale
            )

            // 4. Draw device frame and screenshot
            switch resolvedStyle {
            case .none:
                drawScreenshot(originalImage, in: ctx, rect: deviceRect, cornerRadius: 0)
            case .iPhone, .iPad, .generic:
                let bezelWidth = config.frameBezelWidth ?? defaultBezelWidth(for: resolvedStyle, canvasSize: canvasSize)
                let cornerRadius = config.frameCornerRadius ?? defaultCornerRadius(for: resolvedStyle, canvasSize: canvasSize)

                drawDeviceFrame(
                    in: ctx,
                    deviceRect: deviceRect,
                    bezelWidth: bezelWidth,
                    cornerRadius: cornerRadius,
                    frameColor: config.frameColor
                )

                // Screenshot is drawn inside the frame (inset by bezel width)
                let screenshotRect = deviceRect.insetBy(dx: bezelWidth, dy: bezelWidth)
                let innerCornerRadius = max(0, cornerRadius - bezelWidth)
                drawScreenshot(originalImage, in: ctx, rect: screenshotRect, cornerRadius: innerCornerRadius)

            case .automatic:
                // Already resolved above; this branch is unreachable
                break
            }
        }

        return composedImage.pngData() ?? screenshotData
    }

    // MARK: - Private helpers

    /// Draw a linear gradient into the given rect.
    private static func drawGradient(
        in ctx: CGContext,
        rect: CGRect,
        colors: [UIColor],
        direction: GradientDirection
    ) {
        let cgColors = colors.map { $0.cgColor }
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: cgColors as CFArray,
            locations: nil
        ) else { return }

        let pts = direction.points
        let start = CGPoint(x: rect.width * pts.start.x, y: rect.height * pts.start.y)
        let end = CGPoint(x: rect.width * pts.end.x, y: rect.height * pts.end.y)

        ctx.drawLinearGradient(gradient, start: start, end: end, options: [
            .drawsBeforeStartLocation,
            .drawsAfterEndLocation,
        ])
    }

    /// Draw the device frame (bezel) as a rounded rectangle.
    private static func drawDeviceFrame(
        in ctx: CGContext,
        deviceRect: CGRect,
        bezelWidth: CGFloat,
        cornerRadius: CGFloat,
        frameColor: UIColor
    ) {
        ctx.saveGState()
        ctx.setFillColor(frameColor.cgColor)

        let outerPath = UIBezierPath(roundedRect: deviceRect, cornerRadius: cornerRadius)
        let innerRect = deviceRect.insetBy(dx: bezelWidth, dy: bezelWidth)
        let innerCornerRadius = max(0, cornerRadius - bezelWidth)
        let innerPath = UIBezierPath(roundedRect: innerRect, cornerRadius: innerCornerRadius)

        outerPath.append(innerPath.reversing())
        outerPath.fill()

        ctx.restoreGState()
    }

    /// Draw the screenshot image clipped to a rounded rectangle.
    private static func drawScreenshot(
        _ image: UIImage,
        in ctx: CGContext,
        rect: CGRect,
        cornerRadius: CGFloat
    ) {
        ctx.saveGState()

        if cornerRadius > 0 {
            let clipPath = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            clipPath.addClip()
        }

        image.draw(in: rect)

        ctx.restoreGState()
    }

    /// Calculate the centered device rectangle within the canvas.
    private static func calculateDeviceRect(
        canvasSize: CGSize,
        screenshotScale: CGFloat
    ) -> CGRect {
        let clampedScale = min(max(screenshotScale, 0.1), 1.0)

        let deviceHeight = canvasSize.height * clampedScale
        let deviceWidth = canvasSize.width * clampedScale

        let x = (canvasSize.width - deviceWidth) / 2
        let y = (canvasSize.height - deviceHeight) / 2

        return CGRect(x: x, y: y, width: deviceWidth, height: deviceHeight)
    }

    /// Resolve `.automatic` frame style to `.iPhone` or `.iPad`.
    private static func resolveFrameStyle(_ style: DeviceFrameStyle) -> DeviceFrameStyle {
        guard style == .automatic else { return style }
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
    }

    /// Default bezel width for the given frame style relative to canvas size.
    private static func defaultBezelWidth(for style: DeviceFrameStyle, canvasSize: CGSize) -> CGFloat {
        let shortSide = min(canvasSize.width, canvasSize.height)
        switch style {
        case .iPhone:
            return shortSide * 0.015
        case .iPad:
            return shortSide * 0.02
        default:
            return shortSide * 0.018
        }
    }

    /// Default corner radius for the given frame style relative to canvas size.
    private static func defaultCornerRadius(for style: DeviceFrameStyle, canvasSize: CGSize) -> CGFloat {
        let shortSide = min(canvasSize.width, canvasSize.height)
        switch style {
        case .iPhone:
            return shortSide * 0.08
        case .iPad:
            return shortSide * 0.04
        default:
            return shortSide * 0.06
        }
    }
}
