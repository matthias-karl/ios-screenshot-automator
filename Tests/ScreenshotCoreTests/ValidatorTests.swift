import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotCore

@Suite struct ValidatorTests {
    // MARK: Helpers

    func config(sizes: [String], platform: Platform = .iOS, languages: [String] = ["de-DE", "en-US"]) -> Config {
        Config(project: "A.xcodeproj",
               targets: [.init(platform: platform, scheme: "A", tests: "T/S", sizes: sizes)],
               languages: languages)
    }

    func errors(_ issues: [ValidationIssue]) -> [ValidationIssue] { issues.filter { $0.severity == .error } }
    func warnings(_ issues: [ValidationIssue]) -> [ValidationIssue] { issues.filter { $0.severity == .warning } }

    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("validator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func write(_ finalDir: URL, language: String, name: String, size: PixelSize = PixelSize(width: 1206, height: 2622), alpha: Bool = false) throws -> URL {
        let url = finalDir.appendingPathComponent(language).appendingPathComponent(name)
        let image = alpha ? TestImage.solid(size, .pRed) : TestImage.opaque(size, .pRed)
        try Composer.writePNG(image, to: url)
        return url
    }

    // MARK: Set rules

    @Test func iPhoneSetWithoutRequiredSizeIsAnError() {
        let found = errors(Validator.checkSet(config: config(sizes: ["iphone-6.9"])))
        #expect(found.count == 1)
        #expect(found[0].message.contains("iphone-6.3"))
    }

    @Test func iPadSetNeedsThirteenInch() {
        let found = errors(Validator.checkSet(config: config(sizes: ["ipad-11"])))
        #expect(found.count == 1)
        #expect(found[0].message.contains("ipad-13"))
    }

    @Test func missingDuoIsOnlyAWarning() {
        let issues = Validator.checkSet(config: config(sizes: ["iphone-6.3"]))
        #expect(errors(issues).isEmpty)
        #expect(warnings(issues).count == 1)
        #expect(warnings(issues)[0].message.contains("April 2027"))
    }

    @Test func completeIOSSetHasNoIssues() {
        let sizes = ["iphone-6.3", "iphone-duo-outer", "iphone-duo-inner", "ipad-13"]
        #expect(Validator.checkSet(config: config(sizes: sizes)).isEmpty)
    }

    @Test func twoWatchSizesAreAnError() {
        let found = errors(Validator.checkSet(config: config(sizes: ["watch-ultra", "watch-series"], platform: .watchOS)))
        #expect(found.count == 1)
        #expect(found[0].message.lowercased().contains("watch"))
    }

    @Test func singleWatchSizeIsFine() {
        #expect(Validator.checkSet(config: config(sizes: ["watch-series"], platform: .watchOS)).isEmpty)
    }

    // MARK: Output

    static let sizes = ["iphone-6.3", "iphone-duo-outer", "iphone-duo-inner"]

    @Test func fileNames() {
        #expect(Validator.finalFileName(size: "iphone-6.3", shot: "01_Home", appearance: .light) == "iphone-6.3_01_Home.png")
        #expect(Validator.finalFileName(size: "iphone-6.3", shot: "01_Home", appearance: .dark) == "iphone-6.3_01_Home_dark.png")
    }

    @Test func validOutputHasNoIssues() throws {
        let dir = try tempDir()
        for language in ["de-DE", "en-US"] {
            try write(dir, language: language, name: "iphone-6.3_01_Home.png")
            try write(dir, language: language, name: "iphone-6.3_02_Items.png")
        }
        #expect(Validator.checkOutput(finalDir: dir, config: config(sizes: ["iphone-6.3"])).isEmpty)
    }

    @Test func wrongPixelSizeNamesTheFile() throws {
        let dir = try tempDir()
        for language in ["de-DE", "en-US"] {
            try write(dir, language: language, name: "iphone-6.3_01_Home.png", size: language == "de-DE" ? PixelSize(width: 1000, height: 1000) : PixelSize(width: 1206, height: 2622))
        }
        let found = errors(Validator.checkOutput(finalDir: dir, config: config(sizes: ["iphone-6.3"])))
        #expect(found.count == 1)
        #expect(found[0].message.contains("iphone-6.3_01_Home.png"))
        #expect(found[0].message.contains("1000"))
    }

    @Test func landscapeVariantIsAccepted() throws {
        let dir = try tempDir()
        for language in ["de-DE", "en-US"] {
            try write(dir, language: language, name: "ipad-13_01_Home.png", size: PixelSize(width: 2752, height: 2064))
        }
        #expect(Validator.checkOutput(finalDir: dir, config: config(sizes: ["ipad-13"])).isEmpty)
    }

    @Test func alphaChannelIsAnError() throws {
        let dir = try tempDir()
        try write(dir, language: "de-DE", name: "iphone-6.3_01_Home.png", alpha: true)
        try write(dir, language: "en-US", name: "iphone-6.3_01_Home.png")
        let found = errors(Validator.checkOutput(finalDir: dir, config: config(sizes: ["iphone-6.3"])))
        #expect(found.count == 1)
        #expect(found[0].message.lowercased().contains("alpha"))
        #expect(found[0].message.contains("iphone-6.3_01_Home.png"))
    }

    @Test func moreThanTenImagesIsAnError() throws {
        let dir = try tempDir()
        for language in ["de-DE", "en-US"] {
            for index in 1...11 { try write(dir, language: language, name: String(format: "iphone-6.3_%02d_Shot.png", index)) }
        }
        let found = errors(Validator.checkOutput(finalDir: dir, config: config(sizes: ["iphone-6.3"])))
        #expect(found.contains { $0.message.contains("11") && $0.message.contains("iphone-6.3") })
    }

    @Test func missingShotInOneLanguageNamesBothLanguages() throws {
        let dir = try tempDir()
        try write(dir, language: "de-DE", name: "iphone-6.3_01_Home.png")
        try write(dir, language: "de-DE", name: "iphone-6.3_03_Detail.png")
        try write(dir, language: "en-US", name: "iphone-6.3_01_Home.png")
        let found = errors(Validator.checkOutput(finalDir: dir, config: config(sizes: ["iphone-6.3"])))
        #expect(found.count == 1)
        #expect(found[0].message.contains("de-DE") && found[0].message.contains("en-US") && found[0].message.contains("03_Detail"))
    }

    @Test func configuredSizeWithoutImagesIsAnError() throws {
        let dir = try tempDir()
        for language in ["de-DE", "en-US"] { try write(dir, language: language, name: "iphone-6.3_01_Home.png") }
        let found = errors(Validator.checkOutput(finalDir: dir, config: config(sizes: ["iphone-6.3", "ipad-13"])))
        #expect(found.contains { $0.message.contains("ipad-13") })
    }

    @Test func missingLanguageFolderIsAnError() throws {
        let dir = try tempDir()
        try write(dir, language: "de-DE", name: "iphone-6.3_01_Home.png")
        let found = errors(Validator.checkOutput(finalDir: dir, config: config(sizes: ["iphone-6.3"])))
        #expect(found.contains { $0.message.contains("en-US") })
    }

    @Test func macImagesMustMatchTheConfiguredCanvas() throws {
        let dir = try tempDir()
        for language in ["de-DE", "en-US"] {
            try write(dir, language: language, name: "mac_01_Home.png", size: PixelSize(width: 2880, height: 1800))
            try write(dir, language: language, name: "mac_02_Items.png", size: PixelSize(width: 1440, height: 900))
        }
        let found = errors(Validator.checkOutput(finalDir: dir, config: config(sizes: ["mac"], platform: .macOS)))
        #expect(found.count == 2)   // 02_Items in both languages: valid Apple size, but not the configured canvas
        #expect(found.allSatisfy { $0.message.contains("mac_02_Items.png") })
    }
}
