import CoreGraphics
import Testing
@testable import ScreenshotCore

@Suite struct CaptionTests {
    static let canvas = PixelSize(width: 1206, height: 2622)
    let height = 2622.0
    var rect: CGRect { Layout.captionRect(canvas: Self.canvas, position: .top) }

    @Test func shortTitleKeepsStartSize() throws {
        let fit = try CaptionLayout.fit(title: "Home", subtitle: nil, in: rect, canvasHeight: height, fontPath: nil)
        #expect(abs(fit.titleSize - 0.042 * height) < 0.001)
        #expect(fit.lines == 1)
    }

    @Test func subtitleUsesItsOwnSize() throws {
        let fit = try CaptionLayout.fit(title: "Home", subtitle: "Everything in one place", in: rect, canvasHeight: height, fontPath: nil)
        #expect(abs(fit.subtitleSize - 0.026 * height) < 0.001)
    }

    @Test func longTitleWrapsToTwoLinesAndShrinksNotBelowSixtyPercent() throws {
        let title = String(repeating: "Alle Pflanzen im Blick ", count: 6).trimmingCharacters(in: .whitespaces)
        #expect(title.count >= 120)
        let fit = try CaptionLayout.fit(title: title, subtitle: nil, in: rect, canvasHeight: height, fontPath: nil)
        #expect(fit.lines <= 2)
        #expect(fit.titleSize >= 0.6 * 0.042 * height - 0.001)
    }

    @Test(arguments: ["Gießen nicht vergessen 🌱", "植物の水やりを忘れずに", "لا تنسَ الري"])
    func unusualScriptsAreLaidOut(title: String) throws {
        let fit = try CaptionLayout.fit(title: title, subtitle: nil, in: rect, canvasHeight: height, fontPath: nil)
        #expect(fit.lines >= 1)
    }

    @Test func unreadableFontIsAnError() {
        #expect(throws: ComposeError.fontUnreadable("/nope.ttf")) {
            try CaptionLayout.fit(title: "Home", subtitle: nil, in: rect, canvasHeight: height, fontPath: "/nope.ttf")
        }
    }

    // MARK: Composed image

    func request(title: String?, subtitle: String? = nil, position: Config.Caption.Position = .top, fontPath: String? = nil) -> ComposeRequest {
        let style = Config.Style(
            background: .color("#000000"), frame: .none, frameColor: "#000000", frameImage: nil,
            caption: Config.Caption(color: "#FFFFFF", position: position, font: fontPath))
        return ComposeRequest(
            screenshot: TestImage.solid(Self.canvas, .pRed), canvas: Self.canvas, display: nil, hasDynamicIsland: false,
            platform: .iOS, style: style, title: title, subtitle: subtitle, frameImage: nil)
    }

    func isWhitish(_ p: RGBA) -> Bool { p.red > 200 && p.green > 200 && p.blue > 200 }

    @Test func titleIsDrawnInsideCaptionAreaOnly() throws {
        let r = request(title: "Alle Pflanzen im Blick")
        let bitmap = TestImage.bitmap(try Composer.compose(r))
        let caption = Layout.captionRect(canvas: Self.canvas, position: .top)
        let device = Layout.deviceRect(canvas: Self.canvas, screenshot: Self.canvas, caption: caption, ringWidthFactor: 0)
        #expect(bitmap.contains(in: caption, where: isWhitish))
        #expect(!bitmap.contains(in: device, where: isWhitish))
        #expect(device.minY >= caption.maxY)
    }

    @Test func bottomCaptionIsDrawnBelowTheDevice() throws {
        let r = request(title: "Alle Pflanzen im Blick", position: .bottom)
        let bitmap = TestImage.bitmap(try Composer.compose(r))
        let caption = Layout.captionRect(canvas: Self.canvas, position: .bottom)
        #expect(bitmap.contains(in: caption, where: isWhitish))
    }

    @Test func overlongTitleNeverLeavesTheCaptionArea() throws {
        let r = request(title: String(repeating: "Wasserstand überwachen und rechtzeitig gießen ", count: 12), subtitle: "Mit Erinnerungen")
        let bitmap = TestImage.bitmap(try Composer.compose(r))
        let caption = Layout.captionRect(canvas: Self.canvas, position: .top)
        let device = Layout.deviceRect(canvas: Self.canvas, screenshot: Self.canvas, caption: caption, ringWidthFactor: 0)
        #expect(bitmap.contains(in: caption, where: isWhitish))
        #expect(!bitmap.contains(in: device, where: isWhitish))
    }

    @Test func titleLessImageHasNoCaptionArea() throws {
        // Without text the device uses the full free area (centered, like before).
        let r = request(title: nil)
        let image = try Composer.compose(r)
        let device = Layout.deviceRect(canvas: Self.canvas, screenshot: Self.canvas, caption: nil, ringWidthFactor: 0)
        #expect(TestImage.pixel(image, x: Int(device.midX), y: Int(device.minY) + 2) == .pRed)
    }

    @Test func composeReportsUnreadableFont() {
        #expect(throws: ComposeError.fontUnreadable("/nope.ttf")) {
            try Composer.compose(request(title: "Home", fontPath: "/nope.ttf"))
        }
    }
}
