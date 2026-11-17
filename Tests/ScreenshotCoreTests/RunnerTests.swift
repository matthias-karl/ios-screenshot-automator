import Foundation
import Testing
@testable import ScreenshotCore

@Suite struct RunnerTests {
    static let udid = "UDID-1"
    static let statusBar = ["xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41",
                            "--batteryState", "charged", "--batteryLevel", "100", "--wifiBars", "3", "--cellularBars", "4"]

    struct Env {
        var runner: Runner
        var fake: FakeRunner
        var root: URL
        var workDir: URL
        var project: String { root.appendingPathComponent("Demo.xcodeproj").path }
    }

    func makeEnv(
        projectName: String = "Demo.xcodeproj", rootName: String = "root", platform: Platform = .iOS,
        scheme: String = "Demo", permissions: [String] = [], workspace: Bool = false
    ) throws -> (Env, Config.Target) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("runner-\(UUID().uuidString)")
        let root = base.appendingPathComponent(rootName)
        let workDir = base.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = Config.Target(platform: platform, scheme: scheme, tests: "DemoUITests/Screenshots", sizes: ["iphone-6.3"])
        var config = Config(targets: [target], languages: ["de-DE"], permissions: permissions)
        if workspace { config.workspace = projectName } else { config.project = projectName }
        let fake = FakeRunner()
        let runner = Runner(config: config, root: root, workDir: workDir, shell: fake, log: { _ in })
        return (Env(runner: runner, fake: fake, root: root, workDir: workDir), target)
    }

    func run(
        _ target: Config.Target, sizeID: String = "iphone-6.3", language: String = "de-DE",
        appearance: Appearance = .light, booted: Bool = false, mac: Bool = false, landscape: Bool = false
    ) -> CaptureRun {
        let size = StoreSizes.size(id: sizeID)!
        let sim = Simulator(udid: Self.udid, name: "iPhone 18 Pro", deviceTypeIdentifier: "t", runtimeIdentifier: "r", isBooted: booted)
        let display = DisplaySpec(name: "primary", pixelSize: size.pixelSizes[0], scale: 3, cornerRadii: .zero)
        return CaptureRun(target: target, size: size, simulator: mac ? nil : sim, display: mac ? nil : display,
                          deviceTypeName: mac ? nil : "iPhone 18 Pro", hasDynamicIsland: false,
                          language: language, appearance: appearance, landscape: landscape)
    }

    func testCall(_ env: Env, destination: String, slug: String, language: String = "de", region: String? = "DE",
                  scheme: String = "Demo", derived: String = "dd-iOS") -> [String] {
        var argv = ["xcodebuild", "test-without-building", "-project", env.project, "-scheme", scheme,
                    "-destination", destination, "-derivedDataPath", env.workDir.appendingPathComponent(derived).path,
                    "-only-testing:DemoUITests/Screenshots", "-testLanguage", language]
        if let region { argv += ["-testRegion", region] }
        argv += ["-parallel-testing-enabled", "NO", "-resultBundlePath", env.workDir.appendingPathComponent("\(slug).xcresult").path]
        return argv
    }

    // MARK: Build

    @Test func buildsOncePerTargetWithGenericDestination() throws {
        let (env, target) = try makeEnv()
        try env.runner.build(target: target)
        #expect(env.fake.calls == [[
            "xcodebuild", "build-for-testing", "-project", env.project, "-scheme", "Demo",
            "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", env.workDir.appendingPathComponent("dd-iOS").path,
        ]])
    }

    @Test func buildFailureCarriesLogTail() throws {
        let (env, target) = try makeEnv()
        env.fake.stub(prefix: ["xcodebuild", "build-for-testing"], result: .failure(65, stderr: "error: no such scheme"))
        do {
            try env.runner.build(target: target)
            Issue.record("expected an error")
        } catch let RunnerError.buildFailed(scheme, tail) {
            #expect(scheme == "Demo")
            #expect(tail.contains("no such scheme"))
        }
    }

    // MARK: Capture sequence

    @Test func iOSRunFollowsExactCallOrder() throws {
        let (env, target) = try makeEnv()
        let result = try env.runner.capture(run(target))
        let u = Self.udid
        #expect(env.fake.calls == [
            ["xcrun", "simctl", "boot", u],
            ["xcrun", "simctl", "bootstatus", u, "-b"],
            Self.statusBar,
            ["xcrun", "simctl", "ui", u, "appearance", "light"],
            testCall(env, destination: "platform=iOS Simulator,id=\(u)", slug: "iphone-6.3_de-DE_light"),
            ["xcrun", "simctl", "status_bar", u, "clear"],
            ["xcrun", "simctl", "shutdown", u],
        ])
        #expect(result == env.workDir.appendingPathComponent("iphone-6.3_de-DE_light.xcresult"))
    }

    @Test func testRunReceivesProtocolEnvironment() throws {
        let (env, target) = try makeEnv()
        _ = try env.runner.capture(run(target, appearance: .dark, landscape: true))
        let index = try #require(env.fake.calls.firstIndex { $0.starts(with: ["xcodebuild", "test-without-building"]) })
        let environment = env.fake.environments[index]
        #expect(environment["TEST_RUNNER_SA2_DISPLAY"] == "primary")
        #expect(environment["TEST_RUNNER_SA2_LANDSCAPE"] == "1")
        #expect(environment["TEST_RUNNER_SA2_APPEARANCE"] == "dark")
        #expect(env.fake.calls.contains(["xcrun", "simctl", "ui", Self.udid, "appearance", "dark"]))
    }

    @Test func alreadyBootedSimulatorIsNeitherBootedNorShutDown() throws {
        let (env, target) = try makeEnv()
        _ = try env.runner.capture(run(target, booted: true))
        let calls = env.fake.calls
        #expect(!calls.contains { $0.starts(with: ["xcrun", "simctl", "boot"]) && $0.count == 4 })
        #expect(!calls.contains { $0.starts(with: ["xcrun", "simctl", "shutdown"]) })
        #expect(calls.contains(["xcrun", "simctl", "status_bar", Self.udid, "clear"]))
    }

    @Test func simulatorBootedBySomeoneElseMeanwhileIsNotShutDown() throws {
        let (env, target) = try makeEnv()
        env.fake.stub(prefix: ["xcrun", "simctl", "boot"],
                      result: .failure(149, stderr: "Unable to boot device in current state: Booted"))
        _ = try env.runner.capture(run(target))
        #expect(!env.fake.calls.contains { $0.starts(with: ["xcrun", "simctl", "shutdown"]) })
    }

    @Test func failedTestStillCleansUp() throws {
        let (env, target) = try makeEnv()
        env.fake.stub(prefix: ["xcodebuild", "test-without-building"], result: .failure(65, stderr: "Test Case failed"))
        do {
            _ = try env.runner.capture(run(target))
            Issue.record("expected an error")
        } catch let RunnerError.testFailed(slug, tail) {
            #expect(slug == "iphone-6.3_de-DE_light")
            #expect(tail.contains("Test Case failed"))
        }
        let calls = env.fake.calls
        #expect(calls.suffix(2) == [["xcrun", "simctl", "status_bar", Self.udid, "clear"],
                                    ["xcrun", "simctl", "shutdown", Self.udid]])
    }

    @Test func failedBootReportsSetupErrorAndStillClearsStatusBar() throws {
        let (env, target) = try makeEnv()
        env.fake.stub(prefix: ["xcrun", "simctl", "bootstatus"], result: .failure(1, stderr: "timeout"))
        do {
            _ = try env.runner.capture(run(target))
            Issue.record("expected an error")
        } catch RunnerError.setupFailed(let slug, _, _) {
            #expect(slug == "iphone-6.3_de-DE_light")
        }
        #expect(env.fake.calls.contains(["xcrun", "simctl", "shutdown", Self.udid]))
    }

    @Test func logTailKeepsOnlyLast40Lines() throws {
        let (env, target) = try makeEnv()
        let output = (1...100).map { "line \($0)" }.joined(separator: "\n")
        env.fake.stub(prefix: ["xcodebuild", "test-without-building"], result: CommandResult(
            exitCode: 65, stdout: Data(output.utf8), stderr: Data()))
        do {
            _ = try env.runner.capture(run(target))
            Issue.record("expected an error")
        } catch let RunnerError.testFailed(_, tail) {
            #expect(tail.contains("line 100"))
            #expect(tail.contains("line 61"))
            #expect(!tail.contains("line 60\n") && !tail.hasPrefix("line 60"))
        }
    }

    @Test func staleResultBundleIsRemovedBeforeTheRun() throws {
        let (env, target) = try makeEnv()
        let stale = env.workDir.appendingPathComponent("iphone-6.3_de-DE_light.xcresult")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        _ = try env.runner.capture(run(target))
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    @Test func hungTestRunIsRetriedOnce() throws {
        let (env, target) = try makeEnv()
        let attempts = Counter()
        env.fake.stub(prefix: ["xcodebuild", "test-without-building"]) { _ in
            attempts.increment() == 1 ? .failure(124, stderr: "command timed out") : .ok()
        }
        _ = try env.runner.capture(run(target, booted: true))
        #expect(attempts.value == 2)
    }

    @Test func secondTimeoutIsAFailure() throws {
        let (env, target) = try makeEnv()
        env.fake.stub(prefix: ["xcodebuild", "test-without-building"], result: .failure(124, stderr: "command timed out"))
        #expect(throws: RunnerError.self) { try env.runner.capture(run(target, booted: true)) }
        #expect(env.fake.calls.filter { $0.starts(with: ["xcodebuild", "test-without-building"]) }.count == 2)
    }

    // MARK: Arguments

    @Test func pathsAndSchemesWithSpacesStayOneArgument() throws {
        let (env, target) = try makeEnv(projectName: "My App.xcodeproj", rootName: "My Folder", scheme: "My App")
        _ = try env.runner.capture(run(target))
        let project = env.root.appendingPathComponent("My App.xcodeproj").path
        let call = try #require(env.fake.calls.first { $0.starts(with: ["xcodebuild", "test-without-building"]) })
        #expect(call[2] == "-project" && call[3] == project)
        #expect(call[4] == "-scheme" && call[5] == "My App")
        #expect(project.contains("My Folder"))
    }

    @Test func workspaceReplacesProjectFlag() throws {
        let (env, target) = try makeEnv(projectName: "Demo.xcworkspace", workspace: true)
        _ = try env.runner.capture(run(target))
        let call = try #require(env.fake.calls.first { $0.starts(with: ["xcodebuild", "test-without-building"]) })
        #expect(call[2] == "-workspace")
    }

    @Test func languageAndRegionAreSplit() throws {
        let (env, target) = try makeEnv()
        _ = try env.runner.capture(run(target, language: "zh-Hans"))
        let call = try #require(env.fake.calls.first { $0.starts(with: ["xcodebuild", "test-without-building"]) })
        #expect(call.contains("zh-Hans"))
        #expect(!call.contains("-testRegion"))
    }

    // MARK: Platforms

    @Test func tvOSRunHasNoStatusBarOverride() throws {
        let (env, target) = try makeEnv(platform: .tvOS)
        _ = try env.runner.capture(run(target, sizeID: "appletv"))
        let calls = env.fake.calls
        #expect(!calls.contains { $0.contains("status_bar") })
        #expect(calls.contains(testCall(env, destination: "platform=tvOS Simulator,id=\(Self.udid)",
                                        slug: "appletv_de-DE_light", derived: "dd-tvOS")))
    }

    @Test func macOSRunUsesNoSimctl() throws {
        let (env, target) = try makeEnv(platform: .macOS)
        _ = try env.runner.capture(run(target, sizeID: "mac", mac: true, landscape: true))
        #expect(env.fake.calls == [testCall(env, destination: "platform=macOS", slug: "mac_de-DE_light", derived: "dd-macOS")])
    }

    // MARK: Permissions

    @Test func permissionsAreGrantedForTheAppBundleID() throws {
        let (env, target) = try makeEnv(permissions: ["photos", "camera"])
        let settings = """
        [{"target":"DemoUITests","buildSettings":{"PRODUCT_BUNDLE_IDENTIFIER":"dev.example.UITests","TEST_TARGET_NAME":"Demo"}},
         {"target":"Demo","buildSettings":{"PRODUCT_BUNDLE_IDENTIFIER":"dev.example.Demo"}}]
        """
        env.fake.stub(prefix: ["xcodebuild", "-showBuildSettings"], result: .ok(settings))
        _ = try env.runner.capture(run(target, booted: true))
        let calls = env.fake.calls
        #expect(calls.contains(["xcrun", "simctl", "privacy", Self.udid, "grant", "photos", "dev.example.Demo"]))
        #expect(calls.contains(["xcrun", "simctl", "privacy", Self.udid, "grant", "camera", "dev.example.Demo"]))
        #expect(calls.filter { $0.starts(with: ["xcodebuild", "-showBuildSettings"]) }.count == 1)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    @discardableResult func increment() -> Int { lock.withLock { count += 1; return count } }
    var value: Int { lock.withLock { count } }
}
