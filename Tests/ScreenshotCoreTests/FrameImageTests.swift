import CoreGraphics
import Testing
@testable import ScreenshotCore

@Suite struct FrameImageTests {
    let frameSize = PixelSize(width: 400, height: 800)
    var frame: CGImage { TestImage.frameWithHole(frameSize, hole: CGRect(x: 20, y: 30, width: 360, height: 740)) }

    @Test func findsTransparentScreen() throws {
        #expect(try FrameImage.screenRect(in: frame) == CGRect(x: 20, y: 30, width: 360, height: 740))
    }

    @Test func fullyOpaqueFrameHasNoScreen() {
        let opaque = TestImage.solid(frameSize, .pBlack)
        #expect(throws: FrameImageError.noTransparentScreen) { try FrameImage.screenRect(in: opaque) }
    }

    func request(screenshot: PixelSize) -> ComposeRequest {
        let style = Config.Style(
            background: .color("#FFFFFF"), frame: .image, frameColor: "#000000", frameImage: "frame.png", caption: nil)
        return ComposeRequest(
            screenshot: TestImage.solid(screenshot, .pRed), canvas: PixelSize(width: 800, height: 1600), display: nil,
            hasDynamicIsland: true, platform: .iOS, style: style, title: nil, subtitle: nil, frameImage: frame)
    }

    @Test func screenshotFillsTheHoleAndFrameCoversTheRest() throws {
        let image = try Composer.compose(request(screenshot: PixelSize(width: 360, height: 740)))
        let bitmap = TestImage.bitmap(image)
        #expect(bitmap[400, 800] == .pRed)                // middle of the screen
        #expect(bitmap[0, 0] == .pWhite)                  // background outside the frame
        // Frame is scaled to fit the canvas margin; its left bar is black right next to the screen.
        let frameRect = Layout.deviceRect(canvas: PixelSize(width: 800, height: 1600), screenshot: frameSize, caption: nil, ringWidthFactor: 0)
        #expect(bitmap[Int(frameRect.minX) + 2, Int(frameRect.midY)] == .pBlack)
        // No island is added on top of a custom frame image.
        #expect(bitmap[400, Int(frameRect.minY + 0.08 * frameRect.width) + 60] == .pRed)
    }

    @Test func wrongAspectRatioIsRejected() {
        #expect(throws: (any Error).self) {
            try Composer.compose(request(screenshot: PixelSize(width: 100, height: 100)))
        }
        do {
            _ = try Composer.compose(request(screenshot: PixelSize(width: 100, height: 100)))
        } catch let ComposeError.frameAspectMismatch(expected, actual) {
            #expect(abs(expected - 1) < 0.001)
            #expect(abs(actual - 360.0 / 740.0) < 0.001)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func missingFrameImageIsReported() {
        var r = request(screenshot: PixelSize(width: 360, height: 740))
        r.frameImage = nil
        #expect(throws: ComposeError.missingFrameImage) { try Composer.compose(r) }
    }
}
