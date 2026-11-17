import Testing
@testable import ScreenshotCore

@Suite struct ModelTests {
    @Test func splitsLanguageAndRegion() {
        #expect(LocaleCode.split("de-DE") == ("de", "DE"))
        #expect(LocaleCode.split("zh-Hans") == ("zh-Hans", nil))
        #expect(LocaleCode.split("fr") == ("fr", nil))
        #expect(LocaleCode.split("zh-Hans-CN") == ("zh-Hans", "CN"))
    }

    @Test func pixelSizeSwapAndOrientation() {
        let portrait = PixelSize(width: 1206, height: 2622)
        #expect(portrait.swapped == PixelSize(width: 2622, height: 1206))
        #expect(!portrait.isLandscape)
        #expect(portrait.swapped.isLandscape)
    }
}
