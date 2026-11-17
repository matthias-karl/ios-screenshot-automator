import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ScreenshotCore

@Suite struct ComposerTests {
    static let phone = PixelSize(width: 1206, height: 2622)
    static let duoOuterSize = PixelSize(width: 1398, height: 2034)
    static let duoOuter = DisplaySpec(
        name: "primary", pixelSize: duoOuterSize, scale: 3,
        cornerRadii: CornerRadii(upperLeft: 8, upperRight: 59, lowerLeft: 8, lowerRight: 59))
    static let squareDisplay = DisplaySpec(
        name: "primary", pixelSize: phone, scale: 3, cornerRadii: .zero)

    func style(frame: Config.Frame = .outline, background: Config.Background = .color("#FFFFFF")) -> Config.Style {
        Config.Style(background: background, frame: frame, frameColor: "#000000", frameImage: nil, caption: nil)
    }

    func request(
        size: PixelSize = phone, canvas: PixelSize? = nil, display: DisplaySpec? = squareDisplay, island: Bool = false,
        platform: Platform = .iOS, style: Config.Style? = nil
    ) -> ComposeRequest {
        ComposeRequest(
            screenshot: TestImage.solid(size, .pRed), canvas: canvas ?? size, display: display, hasDynamicIsland: island,
            platform: platform, style: style ?? self.style(), title: nil, subtitle: nil, frameImage: nil)
    }

    func deviceRect(_ r: ComposeRequest, ring: Double = 0) -> CGRect {
        Layout.deviceRect(canvas: r.canvas, screenshot: PixelSize(width: r.screenshot.width, height: r.screenshot.height),
                          caption: nil, ringWidthFactor: ring)
    }

    @Test func outputHasCanvasSizeAndExpectedPixels() throws {
        let r = request()
        let image = try Composer.compose(r)
        #expect(image.width == 1206 && image.height == 2622)
        let bitmap = TestImage.bitmap(image)
        let rect = deviceRect(r)
        #expect(bitmap[0, 0] == .pWhite)
        #expect(bitmap[Int(rect.midX), Int(rect.midY)] == .pRed)
    }

    @Test func outlineDrawsBlackLineOnTopEdge() throws {
        let r = request()
        let bitmap = TestImage.bitmap(try Composer.compose(r))
        let rect = deviceRect(r)
        #expect(bitmap[Int(rect.midX), Int(rect.minY)] == .pBlack)
        #expect(bitmap[Int(rect.minX), Int(rect.midY)] == .pBlack)
        // Just outside the line stays background.
        #expect(bitmap[Int(rect.midX), Int(rect.minY) - 3] == .pWhite)
    }

    @Test func duoOuterHasSharpLeftAndRoundRightCorners() throws {
        let r = request(size: Self.duoOuterSize, display: Self.duoOuter)
        let bitmap = TestImage.bitmap(try Composer.compose(r))
        let rect = deviceRect(r)
        // Upper right: radius ≈ 130 px, so 3 px inside the corner is outside the rounded shape.
        #expect(bitmap[Int(rect.maxX) - 3, Int(rect.minY) + 3] == .pWhite)
        // Upper left: radius ≈ 18 px, 30 px inside is on the device (red or the black line).
        let left = bitmap[Int(rect.minX) + 30, Int(rect.minY) + 30]
        #expect(left == .pRed || left == .pBlack)
        #expect(left != .pWhite)
    }

    @Test func frameNoneDrawsNoBlack() throws {
        let image = try Composer.compose(request(style: style(frame: .none)))
        let bitmap = TestImage.bitmap(image)
        let anyBlack = bitmap.contains(in: CGRect(x: 0, y: 0, width: image.width, height: image.height)) { $0.isClose(to: .pBlack, tolerance: 60) }
        #expect(!anyBlack)
    }

    @Test func dynamicIslandIsDrawnForOutlineOnPrimaryPortrait() throws {
        let withIsland = request(island: true)
        let rect = deviceRect(withIsland)
        let x = Int(rect.midX), y = Int(rect.minY + 0.08 * rect.width)
        #expect(TestImage.pixel(try Composer.compose(withIsland), x: x, y: y) == .pBlack)
        #expect(TestImage.pixel(try Composer.compose(request(island: false)), x: x, y: y) == .pRed)
    }

    @Test func dynamicIslandIsSkippedWithoutFrame() throws {
        let r = request(island: true, style: style(frame: .none))
        let rect = deviceRect(r)
        #expect(TestImage.pixel(try Composer.compose(r), x: Int(rect.midX), y: Int(rect.minY + 0.08 * rect.width)) == .pRed)
    }

    @Test func bezelRingSurroundsTheScreen() throws {
        let r = request(style: style(frame: .bezel))
        let rect = deviceRect(r, ring: 0.022)
        let bitmap = TestImage.bitmap(try Composer.compose(r))
        let x = Int(rect.minX - 0.01 * rect.width)
        #expect(bitmap[x, Int(rect.midY)] == .pBlack)
        #expect(bitmap[Int(rect.midX), Int(rect.midY)] == .pRed)
    }

    @Test func gradientRunsAlongTheAngle() throws {
        let r = request(style: style(frame: .none, background: .gradient(["#000000", "#FFFFFF"], angle: 90)))
        let bitmap = TestImage.bitmap(try Composer.compose(r))
        let top = bitmap[603, 0], bottom = bitmap[603, 2621]
        #expect(abs(Int(bottom.red) - Int(top.red)) > 200)
        #expect(abs(Int(bottom.green) - Int(top.green)) > 200)
        #expect(abs(Int(bottom.blue) - Int(top.blue)) > 200)
    }

    @Test func macWindowGetsShadowAndNoFrame() throws {
        let canvas = PixelSize(width: 2880, height: 1800)
        let r = request(size: PixelSize(width: 2000, height: 1200), canvas: canvas, display: nil, platform: .macOS)
        let rect = deviceRect(r)
        let bitmap = TestImage.bitmap(try Composer.compose(r))
        #expect(bitmap[Int(rect.midX), Int(rect.midY)] == .pRed)
        #expect(bitmap[Int(rect.minX), Int(rect.midY)] == .pRed)            // no frame line
        let below = bitmap[Int(rect.midX), Int(rect.maxY) + 6]
        #expect(below.red < 250)                                            // shadow darkens the white background
    }

    @Test func pngHasNoAlphaChannel() throws {
        let image = try Composer.compose(request())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("compose-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Composer.writePNG(image, to: url)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let loaded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(loaded.alphaInfo == .none || loaded.alphaInfo == .noneSkipLast || loaded.alphaInfo == .noneSkipFirst)
        #expect(loaded.width == 1206 && loaded.height == 2622)
    }

    @Test func badColorIsReported() {
        let r = request(style: style(background: .color("#12")))
        #expect(throws: ComposeError.badColor("#12")) { try Composer.compose(r) }
    }
}
