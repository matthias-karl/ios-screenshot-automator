import CoreGraphics
import Testing
@testable import ScreenshotCore

@Suite struct LayoutTests {
    let canvas = PixelSize(width: 1206, height: 2622)

    @Test func captionRectIsEighteenPercentAtTop() {
        let rect = Layout.captionRect(canvas: canvas, position: .top)
        #expect(abs(rect.height - 0.18 * 2622) <= 1)
        #expect(rect.minY == 0)
        #expect(abs(rect.minX - 0.06 * 1206) <= 1)
        #expect(abs(rect.width - 0.88 * 1206) <= 2)
    }

    @Test func captionRectAtBottomTouchesCanvasEdge() {
        let rect = Layout.captionRect(canvas: canvas, position: .bottom)
        #expect(rect.maxY == 2622)
    }

    @Test func deviceRectKeepsAspectRatioAndIsCentered() {
        let rect = Layout.deviceRect(canvas: canvas, screenshot: canvas, caption: nil, ringWidthFactor: 0)
        #expect(abs(rect.width / rect.height - 1206.0 / 2622.0) < 0.001)
        #expect(abs(rect.midX - 603) <= 1)
        #expect(abs(rect.midY - 1311) <= 1)
        #expect(rect.minX >= 72)
    }

    @Test func deviceRectIsWholePixels() {
        let rect = Layout.deviceRect(canvas: canvas, screenshot: canvas, caption: nil, ringWidthFactor: 0)
        #expect(rect == rect.integral)
    }

    @Test func deviceRectStartsBelowTopCaption() {
        let caption = Layout.captionRect(canvas: canvas, position: .top)
        let rect = Layout.deviceRect(canvas: canvas, screenshot: canvas, caption: caption, ringWidthFactor: 0)
        #expect(rect.minY >= caption.maxY)
        #expect(rect.maxY <= 2622)
    }

    @Test func deviceRectEndsAboveBottomCaption() {
        let caption = Layout.captionRect(canvas: canvas, position: .bottom)
        let rect = Layout.deviceRect(canvas: canvas, screenshot: canvas, caption: caption, ringWidthFactor: 0)
        #expect(rect.maxY <= caption.minY)
        #expect(rect.minY >= 0)
    }

    @Test func bezelRingStaysInsideTheOuterMargin() {
        let rect = Layout.deviceRect(canvas: canvas, screenshot: canvas, caption: nil, ringWidthFactor: 0.022)
        let ring = 0.022 * rect.width
        #expect(rect.minX - ring >= 0.06 * 1206 - 1)
        #expect(rect.minY - ring >= 0.06 * 1206 - 1)
    }

    @Test func landscapeScreenshotFitsLandscapeCanvas() {
        let tv = PixelSize(width: 1920, height: 1080)
        let rect = Layout.deviceRect(canvas: tv, screenshot: tv, caption: nil, ringWidthFactor: 0)
        #expect(abs(rect.width / rect.height - 1920.0 / 1080.0) < 0.002)
        #expect(rect.minX >= 0.06 * 1080 - 1)
    }

    @Test func cornerRadiiScaleFromPointsToDrawnPixels() {
        let duoOuter = DisplaySpec(
            name: "primary", pixelSize: PixelSize(width: 1398, height: 2034), scale: 3,
            cornerRadii: CornerRadii(upperLeft: 8, upperRight: 59, lowerLeft: 8, lowerRight: 59))
        #expect(Layout.cornerRadii(display: duoOuter, drawnWidth: 1398) == CornerRadii(upperLeft: 24, upperRight: 177, lowerLeft: 24, lowerRight: 177))
        #expect(Layout.cornerRadii(display: duoOuter, drawnWidth: 699) == CornerRadii(upperLeft: 12, upperRight: 88.5, lowerLeft: 12, lowerRight: 88.5))
    }
}
