import Testing
@testable import ScreenshotCore

@Suite struct StoreSizesTests {
    @Test func duoOuterHasSingleSize() {
        #expect(StoreSizes.size(id: "iphone-duo-outer")?.pixelSizes == [PixelSize(width: 1398, height: 2034)])
    }

    @Test func iphone63IsRequiredWithinFamily() {
        #expect(StoreSizes.size(id: "iphone-6.3")?.requiredWithinFamily == true)
        #expect(StoreSizes.size(id: "iphone-6.9")?.requiredWithinFamily == false)
    }

    @Test func idsAreUnique() {
        let ids = StoreSizes.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func allPixelSizesArePortrait() {
        for size in StoreSizes.all {
            #expect(!size.pixelSizes.isEmpty, "\(size.id) has no sizes")
            for pixels in size.pixelSizes {
                #expect(pixels.width < pixels.height, "\(size.id) \(pixels) is not portrait")
            }
        }
    }

    @Test func unknownIdIsNil() {
        #expect(StoreSizes.size(id: "iphone-6.7") == nil)
    }

    @Test func tableCarriesProvenance() {
        #expect(StoreSizes.lastVerified == "2026-11-14")
        #expect(StoreSizes.source.hasPrefix("https://developer.apple.com/"))
    }

    @Test func platformsAndFamiliesMatchTable() {
        #expect(StoreSizes.size(id: "appletv")?.platform == .tvOS)
        #expect(StoreSizes.size(id: "mac")?.family == .mac)
        #expect(StoreSizes.size(id: "watch-series")?.platform == .watchOS)
        #expect(StoreSizes.size(id: "ipad-13")?.family == .iPad)
    }
}
