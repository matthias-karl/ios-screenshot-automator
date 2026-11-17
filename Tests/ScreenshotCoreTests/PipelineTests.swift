import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ScreenshotCore

@Suite struct PipelineTests {
    // MARK: Project fixture

    struct Project {
        var dir: URL
        var configURL: URL { dir.appendingPathComponent("screenshots.json") }
        var raw: URL { dir.appendingPathComponent("screenshots/raw") }
        var final: URL { dir.appendingPathComponent("screenshots/final") }
    }

    static func exportSize(for slug: String) -> PixelSize {
        slug.hasPrefix("ipad-13") ? PixelSize(width: 2064, height: 2752) : PixelSize(width: 1206, height: 2622)
    }

    func makeProject(
        sizes: [String] = ["iphone-6.3"], languages: [String] = ["de-DE", "en-US"],
        shotNames: [String] = ["01_Home", "02_Items"], extraTitles: [String] = []
    ) throws -> Project {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let titles = Dictionary(uniqueKeysWithValues: (shotNames + extraTitles).map { name in
            (name, ["title": Dictionary(uniqueKeysWithValues: languages.map { ($0, "Title \(name) \($0)") })])
        })
        let json: [String: Any] = [
            "version": 2, "project": "Demo.xcodeproj",
            "targets": [["platform": "iOS", "scheme": "Demo", "tests": "DemoUITests/Screenshots", "sizes": sizes]],
            "languages": languages, "shots": titles,
        ]
        try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("screenshots.json"))
        return Project(dir: dir)
    }

    /// A `FakeRunner` whose `xcresulttool` writes real PNGs named by the run's `.xcresult` file name.
    func makeShell(shotNames: [String] = ["01_Home", "02_Items"], failingLanguage: String? = nil, emptyExportPrefix: String? = nil) -> FakeRunner {
        let fake = FakeRunner()
        fake.stub(prefix: ["xcrun", "xcresulttool", "export", "attachments"]) { argv in
            let path = argv[argv.index(after: argv.firstIndex(of: "--path")!)]
            let slug = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let out = URL(fileURLWithPath: argv[argv.index(after: argv.firstIndex(of: "--output-path")!)])
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            var attachments: [[String: Any]] = []
            let names = emptyExportPrefix.map { slug.hasPrefix($0) } == true ? [] : shotNames
            for (index, name) in names.enumerated() {
                try Composer.writePNG(TestImage.opaque(Self.exportSize(for: slug), .pRed), to: out.appendingPathComponent("f\(index).png"))
                attachments.append(["exportedFileName": "f\(index).png", "suggestedHumanReadableName": "sa2v2__\(name)_0_AAAAAAAA-0000-0000-0000-00000000000\(index).png"])
            }
            try JSONSerialization.data(withJSONObject: [["testIdentifier": "T", "attachments": attachments]])
                .write(to: out.appendingPathComponent("manifest.json"))
            return .ok()
        }
        if let failingLanguage {
            fake.stub(prefix: ["xcodebuild", "test-without-building"]) { argv in
                let language = argv[argv.index(after: argv.firstIndex(of: "-testLanguage")!)]
                return language == failingLanguage ? .failure(65, stderr: "Test Case failed") : .ok()
            }
        }
        return fake
    }

    func pipeline(_ project: Project, shell: FakeRunner, ipad13: Bool = true) -> Pipeline {
        let catalog = PlannerTests.catalog(ipad13: ipad13)
        return Pipeline(configURL: project.configURL, shell: shell, log: { _ in }, catalogLoader: { catalog })
    }

    func pixelSize(_ url: URL) throws -> PixelSize {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return PixelSize(width: props[kCGImagePropertyPixelWidth] as! Int, height: props[kCGImagePropertyPixelHeight] as! Int)
    }

    // MARK: run

    @Test func runProducesFinalImagesInExactStoreSize() throws {
        let project = try makeProject()
        let result = try pipeline(project, shell: makeShell()).run(filter: RunFilter())
        #expect(result.succeeded, "\(result.failures) \(result.issues)")
        let file = project.final.appendingPathComponent("de-DE/iphone-6.3_01_Home.png")
        #expect(try pixelSize(file) == PixelSize(width: 1206, height: 2622))
        #expect(result.finalFiles.count == 4)
        #expect(FileManager.default.fileExists(atPath: project.dir.appendingPathComponent("screenshots/index.html").path))
        #expect(FileManager.default.fileExists(atPath: project.raw.appendingPathComponent("iphone-6.3/de-DE-light/01_Home.png").path))
    }

    @Test func buildsEachTargetOnce() throws {
        let project = try makeProject(sizes: ["iphone-6.3", "ipad-13"])
        let shell = makeShell()
        _ = try pipeline(project, shell: shell).run(filter: RunFilter())
        #expect(shell.calls.filter { $0.starts(with: ["xcodebuild", "build-for-testing"]) }.count == 1)
        #expect(shell.calls.filter { $0.starts(with: ["xcodebuild", "test-without-building"]) }.count == 4)
    }

    @Test func failingTestStillYieldsItsScreenshots() throws {
        // Every test method is its own run: when one fails, the images of the others must still appear.
        let project = try makeProject()
        let result = try pipeline(project, shell: makeShell(failingLanguage: "de")).run(filter: RunFilter())
        #expect(!result.succeeded)
        #expect(result.failures.contains { $0.contains("iphone-6.3_de-DE_light") })
        #expect(FileManager.default.fileExists(atPath: project.final.appendingPathComponent("en-US/iphone-6.3_01_Home.png").path))
        #expect(FileManager.default.fileExists(atPath: project.final.appendingPathComponent("de-DE/iphone-6.3_01_Home.png").path))
    }

    @Test func runWithoutAnyExportedImageLeavesNoStaleImages() throws {
        let project = try makeProject()
        _ = try pipeline(project, shell: makeShell()).run(filter: RunFilter())
        #expect(FileManager.default.fileExists(atPath: project.final.appendingPathComponent("de-DE/iphone-6.3_01_Home.png").path))
        let again = try pipeline(project, shell: makeShell(failingLanguage: "de", emptyExportPrefix: "iphone-6.3_de")).run(filter: RunFilter())
        #expect(!again.succeeded)
        #expect(!FileManager.default.fileExists(atPath: project.final.appendingPathComponent("de-DE/iphone-6.3_01_Home.png").path))
        #expect(!FileManager.default.fileExists(atPath: project.raw.appendingPathComponent("iphone-6.3/de-DE-light/01_Home.png").path))
    }

    @Test func buildFailureFailsEveryRunOfTheTarget() throws {
        let project = try makeProject()
        let shell = makeShell()
        shell.stub(prefix: ["xcodebuild", "build-for-testing"], result: .failure(65, stderr: "error: no such scheme"))
        let result = try pipeline(project, shell: shell).run(filter: RunFilter())
        #expect(!result.succeeded)
        #expect(result.failures.contains { $0.contains("no such scheme") })
        #expect(!shell.calls.contains { $0.starts(with: ["xcodebuild", "test-without-building"]) })
    }

    @Test func filterThatMatchesNothingFails() throws {
        let project = try makeProject()
        var filter = RunFilter()
        filter.sizes = ["ipad-13"]
        let result = try pipeline(project, shell: makeShell()).run(filter: filter)
        #expect(!result.succeeded)
        #expect(result.failures.contains { $0.contains("matches no") })
    }

    @Test func filteredRunOnlyValidatesItsScope() throws {
        let project = try makeProject(sizes: ["iphone-6.3", "ipad-13"])
        var filter = RunFilter()
        filter.sizes = ["iphone-6.3"]
        let result = try pipeline(project, shell: makeShell()).run(filter: filter)
        #expect(result.succeeded, "\(result.failures) \(result.issues)")
    }

    // MARK: compose

    @Test func composeRemovesFinalImagesWhoseRawImageIsGone() throws {
        let project = try makeProject()
        let pipeline = pipeline(project, shell: makeShell())
        _ = try pipeline.run(filter: RunFilter())
        let stale = project.final.appendingPathComponent("de-DE/iphone-6.3_02_Items.png")
        #expect(FileManager.default.fileExists(atPath: stale.path))
        try FileManager.default.removeItem(at: project.raw.appendingPathComponent("iphone-6.3/de-DE-light/02_Items.png"))
        _ = try pipeline.compose(filter: RunFilter())
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    @Test func composeWithoutRawImagesFails() throws {
        let project = try makeProject()
        let result = try pipeline(project, shell: makeShell()).compose(filter: RunFilter())
        #expect(!result.succeeded)
        #expect(result.failures.contains { $0.contains("no raw images") })
    }

    @Test func rawImageOfWrongSizeIsRejected() throws {
        let project = try makeProject(languages: ["en-US"], shotNames: ["01_Home"])
        let dir = project.raw.appendingPathComponent("iphone-6.3/en-US-light")
        try Composer.writePNG(TestImage.opaque(PixelSize(width: 500, height: 500), .pRed), to: dir.appendingPathComponent("01_Home.png"))
        let result = try pipeline(project, shell: makeShell()).compose(filter: RunFilter())
        #expect(!result.succeeded)
        #expect(result.failures.contains { $0.contains("500×500") })
    }

    @Test func titleForUnknownShotIsAnErrorInRunAndCompose() throws {
        let project = try makeProject(extraTitles: ["99_Missing"])
        let pipeline = pipeline(project, shell: makeShell())
        let run = try pipeline.run(filter: RunFilter())
        #expect(!run.succeeded)
        #expect(run.failures.contains { $0.contains("99_Missing") })
        let compose = try pipeline.compose(filter: RunFilter())
        #expect(compose.failures.contains { $0.contains("99_Missing") })
    }

    // MARK: check

    @Test func checkNamesTheSizeWithoutInstalledSimulator() throws {
        let project = try makeProject(sizes: ["iphone-6.3", "ipad-13"])
        let result = try pipeline(project, shell: makeShell(), ipad13: false).check()
        #expect(!result.succeeded)
        #expect(result.failures.contains { $0.contains("ipad-13") })
    }

    @Test func checkPassesForACompleteSetup() throws {
        let project = try makeProject()
        let result = try pipeline(project, shell: makeShell()).check()
        #expect(result.succeeded, "\(result.failures) \(result.issues)")
    }

    @Test func checkReportsUnknownShotTitlesOnlyOnceRawImagesExist() throws {
        let project = try makeProject(extraTitles: ["99_Missing"])
        let pipeline = pipeline(project, shell: makeShell())
        #expect(try pipeline.check().succeeded)                        // no raw/ yet
        _ = try pipeline.capture(filter: RunFilter())
        let after = try pipeline.check()
        #expect(!after.succeeded)
        #expect(after.failures.contains { $0.contains("99_Missing") })
    }

    @Test func checkDoesNotChangeAnything() throws {
        let project = try makeProject()
        let shell = makeShell()
        _ = try pipeline(project, shell: shell).check()
        #expect(!FileManager.default.fileExists(atPath: project.dir.appendingPathComponent("screenshots").path))
        #expect(!shell.calls.contains { $0.starts(with: ["xcodebuild"]) })
    }

    @Test func invalidConfigThrows() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"version": 1}"#.utf8).write(to: dir.appendingPathComponent("screenshots.json"))
        let pipeline = Pipeline(configURL: dir.appendingPathComponent("screenshots.json"), shell: FakeRunner(), log: { _ in })
        #expect(throws: ConfigError.self) { try pipeline.check() }
    }
}
