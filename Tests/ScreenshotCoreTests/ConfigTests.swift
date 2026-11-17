import Foundation
import Testing
@testable import ScreenshotCore

@Suite struct ConfigTests {
    func fixture() throws -> Config {
        try Config.load(from: Fixtures.url("plantner.json"))
    }

    /// Issues for the fixture after applying one mutation.
    func issues(_ mutate: (inout Config) -> Void) throws -> [ConfigIssue] {
        var config = try fixture()
        mutate(&config)
        return config.issues()
    }

    // MARK: Loading

    @Test func loadsFixtureWithDefaults() throws {
        let config = try fixture()
        #expect(config.languages == ["de-DE", "en-US"])
        #expect(config.targets[0].sizes.count == 5)
        #expect(config.style.frame == .outline)
        #expect(config.output == "screenshots")
        #expect(config.appearances == [.light])
        #expect(config.macCanvas == PixelSize(width: 2880, height: 1800))
        #expect(config.permissions == [])
        #expect(config.targets[0].landscape == [])
        #expect(config.style.frameColor == "#000000")
        #expect(config.style.caption == Config.Caption(color: "#FFFFFF", position: .top, font: nil))
        #expect(config.style.background == .gradient(["#1f881b", "#79b474"], angle: 135))
        #expect(config.issues().isEmpty)
    }

    @Test func missingFileIsUnreadable() {
        let url = URL(fileURLWithPath: "/nonexistent/screenshots.json")
        #expect(throws: ConfigError.self) { try Config.load(from: url) }
    }

    @Test func malformedJSONReportsFieldPath() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bad-\(UUID().uuidString).json")
        try Data(#"{"version": 2, "targets": [{"platform": "iOS"}]}"#.utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            _ = try Config.load(from: tmp)
            Issue.record("expected an error")
        } catch let ConfigError.invalid(found) {
            #expect(found.contains { $0.path.hasPrefix("targets[0]") })
        }
    }

    @Test func backgroundAndCaptionRoundTrip() throws {
        var config = try fixture()
        config.style.background = .color("#112233")
        config.style.caption = nil
        let data = try JSONEncoder().encode(config)
        let back = try JSONDecoder().decode(Config.self, from: data)
        #expect(back == config)
        #expect(back.style.caption == nil)   // null stays null, not the default caption
    }

    @Test func styleForSizeUsesOverride() throws {
        var config = try fixture()
        var watch = config.style
        watch.caption = nil
        config.sizeStyles["watch-series"] = watch
        #expect(config.style(forSize: "watch-series").caption == nil)
        #expect(config.style(forSize: "iphone-6.3") == config.style)
    }

    // MARK: Validation (one issue, exact path)

    @Test func rejectsWrongVersion() throws {
        #expect(try issues { $0.version = 1 }.map(\.path) == ["version"])
    }

    @Test func requiresExactlyOneOfProjectAndWorkspace() throws {
        #expect(try issues { $0.workspace = "A.xcworkspace" }.map(\.path) == ["project"])
        #expect(try issues { $0.project = nil }.map(\.path) == ["project"])
    }

    @Test func rejectsEmptyLanguages() throws {
        // Titles would also be flagged for the removed languages; keep shots empty to isolate the check.
        #expect(try issues { $0.languages = []; $0.shots = [:] }.map(\.path) == ["languages"])
    }

    @Test func testsPathNeedsClassSeparator() throws {
        #expect(try issues { $0.targets[0].tests = "NurTarget" }.map(\.path) == ["targets[0].tests"])
    }

    @Test func landscapeMustBeListedInSizes() throws {
        #expect(try issues { $0.targets[0].landscape = ["ipad-13", "mac"] }.map(\.path) == ["targets[0].landscape"])
        #expect(try issues { $0.targets[0].landscape = ["ipad-13"] }.isEmpty)
    }

    @Test func imageFrameNeedsFrameImage() throws {
        #expect(try issues { $0.style.frame = .image }.map(\.path) == ["style.frameImage"])
        #expect(try issues { $0.style.frame = .image; $0.style.frameImage = "Frames/phone.png" }.isEmpty)
    }

    @Test func rejectsBadColor() throws {
        #expect(try issues { $0.style.background = .color("#12") }.map(\.path) == ["style.background"])
        #expect(try issues { $0.style.background = .gradient(["#000000", "red"], angle: 0) }.map(\.path) == ["style.background"])
    }

    @Test func rejectsBadShotName() throws {
        #expect(try issues { $0.shots["a b"] = Config.Shot() }.map(\.path) == ["shots.a b"])
    }

    @Test func titleKeyMustBeConfiguredLanguage() throws {
        let found = try issues { config in
            config.shots["01_Home"]?.title = ["de": "Alle Pflanzen im Blick", "en-US": "All your plants at a glance"]
        }
        #expect(found.map(\.path) == ["shots.01_Home.title.de"])
        #expect(found[0].message.contains("de-DE"))   // hints at the intended code
    }

    @Test func titleMustExistForEveryLanguage() throws {
        let found = try issues { config in
            config.shots["01_Home"]?.title = ["de-DE": "Alle Pflanzen im Blick"]
        }
        #expect(found.map(\.path) == ["shots.01_Home.title.en-US"])
    }

    // MARK: RGBA

    @Test func parsesHexColors() {
        #expect(RGBA(hex: "#1f881b") == RGBA(red: 0x1f, green: 0x88, blue: 0x1b))
        #expect(RGBA(hex: "#FFF") == RGBA(red: 255, green: 255, blue: 255))
        #expect(RGBA(hex: "#12") == nil)
        #expect(RGBA(hex: "1f881b") == nil)
        #expect(RGBA(hex: "#GGGGGG") == nil)
    }
}
