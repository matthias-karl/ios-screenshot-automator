import CoreGraphics
import Foundation

/// Geometry of the composed image. All rectangles use a **top-left origin** (y grows downwards)
/// and whole pixels, so pixel probes and drawing agree.
public enum Layout {
    /// Outer margin: 6 % of the shorter canvas side.
    static let marginFactor = 0.06
    /// The caption area takes 18 % of the canvas height.
    static let captionHeightFactor = 0.18
    /// Space left and right of the caption text: 6 % of the width.
    static let captionSideFactor = 0.06
    /// Ring width of the `bezel` frame, relative to the device width.
    static let bezelRingFactor = 0.022

    public static func captionRect(canvas: PixelSize, position: Config.Caption.Position) -> CGRect {
        let width = Double(canvas.width), height = Double(canvas.height)
        let rectHeight = (height * captionHeightFactor).rounded()
        let x = (width * captionSideFactor).rounded()
        let y = position == .top ? 0 : height - rectHeight
        return CGRect(x: x, y: y, width: width - 2 * x, height: rectHeight)
    }

    /// The screen rectangle: the screenshot scaled (never distorted) to fit the free area, centered.
    /// With a bezel (`ringWidthFactor` > 0) the ring around the screen fits inside the area as well.
    public static func deviceRect(canvas: PixelSize, screenshot: PixelSize, caption: CGRect?, ringWidthFactor: Double) -> CGRect {
        let width = Double(canvas.width), height = Double(canvas.height)
        let margin = marginFactor * min(width, height)

        var top = margin, bottom = height - margin
        if let caption {
            if caption.midY < height / 2 { top = max(top, caption.maxY) } else { bottom = min(bottom, caption.minY) }
        }
        let areaWidth = width - 2 * margin, areaHeight = max(1, bottom - top)

        let sw = Double(screenshot.width), sh = Double(screenshot.height)
        // Fit "screen + ring" (ring = factor × screen width) into the area.
        let scale = min(areaWidth / (sw * (1 + 2 * ringWidthFactor)), areaHeight / (sh + 2 * ringWidthFactor * sw))
        let w = (sw * scale).rounded(), h = (sh * scale).rounded()
        let x = ((width - w) / 2).rounded(), y = (top + (areaHeight - h) / 2).rounded()
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Display corner radii (points) converted to pixels of the drawn screen.
    public static func cornerRadii(display: DisplaySpec, drawnWidth: Double) -> CornerRadii {
        let factor = display.scale * drawnWidth / Double(display.pixelSize.width)
        let r = display.cornerRadii
        return CornerRadii(upperLeft: r.upperLeft * factor, upperRight: r.upperRight * factor,
                           lowerLeft: r.lowerLeft * factor, lowerRight: r.lowerRight * factor)
    }
}
