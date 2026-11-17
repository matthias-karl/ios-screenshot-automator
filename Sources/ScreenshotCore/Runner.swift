import Foundation

public enum RunnerError: Error, Equatable, CustomStringConvertible {
    case buildFailed(scheme: String, logTail: String)
    case testFailed(slug: String, logTail: String)
    /// Simulator preparation (boot, status bar, appearance, permissions) failed before the test ran.
    case setupFailed(slug: String, step: String, logTail: String)

    public var description: String {
        switch self {
        case .buildFailed(let scheme, let tail):
            return "Build of scheme \"\(scheme)\" failed:\n\(tail)"
        case .testFailed(let slug, let tail):
            return "Test run \(slug) failed:\n\(tail)"
        case .setupFailed(let slug, let step, let tail):
            return "Preparing the simulator for \(slug) failed at \"\(step)\":\n\(tail)"
        }
    }
}

/// Runs `xcodebuild` and `simctl` for one `CaptureRun`.
public struct Runner: Sendable {
    public static let statusBarArguments = [
        "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
        "--wifiBars", "3", "--cellularBars", "4",
    ]

    /// Exit code `ProcessRunner` reports for a command it terminated after its timeout.
    static let timeoutExitCode: Int32 = 124

    private let config: Config
    private let root: URL
    private let workDir: URL
    private let shell: CommandRunning
    private let log: @Sendable (String) -> Void
    private let bundleIDs = BundleIDCache()

    /// - Parameters:
    ///   - root: folder of `screenshots.json`; `project`/`workspace` are relative to it.
    ///   - workDir: scratch folder for derived data and `.xcresult` bundles.
    public init(config: Config, root: URL, workDir: URL, shell: CommandRunning, log: @escaping @Sendable (String) -> Void) {
        self.config = config
        self.root = root
        self.workDir = workDir
        self.shell = shell
        self.log = log
    }

    /// Where `capture(_:)` writes the result bundle of a run (also after a failed test run).
    public func resultBundleURL(for run: CaptureRun) -> URL {
        workDir.appendingPathComponent("\(run.slug).xcresult")
    }

    // MARK: Build

    /// `build-for-testing`, once per target.
    public func build(target: Config.Target) throws {
        log("Building \(target.scheme) (\(target.platform.rawValue))…")
        let arguments = ["build-for-testing"] + containerArguments + ["-scheme", target.scheme,
            "-destination", Self.genericDestination(target.platform),
            "-derivedDataPath", derivedData(target.platform).path]
        let result = try shell.run("xcodebuild", arguments, environment: [:])
        guard result.exitCode == 0 else {
            throw RunnerError.buildFailed(scheme: target.scheme, logTail: Self.logTail(result))
        }
    }

    // MARK: Capture

    /// Runs the UI tests for one run and returns the `.xcresult` bundle.
    public func capture(_ run: CaptureRun) throws -> URL {
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let resultBundle = resultBundleURL(for: run)
        try? FileManager.default.removeItem(at: resultBundle)
        log("Capturing \(run.slug)…")

        guard let simulator = run.simulator else {
            try runTests(run, destination: "platform=macOS", resultBundle: resultBundle)
            return resultBundle
        }

        // Review focus: only shut down what we booted ourselves, always clear the status bar override.
        var bootedByUs = false
        var statusBarOverridden = false
        defer {
            if statusBarOverridden { _ = try? shell.run("xcrun", ["simctl", "status_bar", simulator.udid, "clear"], environment: [:]) }
            if bootedByUs { _ = try? shell.run("xcrun", ["simctl", "shutdown", simulator.udid], environment: [:]) }
        }

        if !simulator.isBooted {
            let result = try shell.run("xcrun", ["simctl", "boot", simulator.udid], environment: [:])
            if result.exitCode == 0 {
                bootedByUs = true
            } else if !Self.logTail(result).contains("current state: Booted") {
                throw RunnerError.setupFailed(slug: run.slug, step: "boot", logTail: Self.logTail(result))
            }
        }
        try simctl(run, "bootstatus", ["bootstatus", simulator.udid, "-b"])

        if run.target.platform == .iOS {
            try simctl(run, "status_bar override", ["status_bar", simulator.udid, "override"] + Self.statusBarArguments)
            statusBarOverridden = true
        }
        try simctl(run, "appearance", ["ui", simulator.udid, "appearance", run.appearance.rawValue])

        if !config.permissions.isEmpty {
            let bundleID = try appBundleID(for: run)
            for service in config.permissions {
                try simctl(run, "privacy \(service)", ["privacy", simulator.udid, "grant", service, bundleID])
            }
        }

        try runTests(run, destination: "platform=\(Self.simulatorPlatform(run.target.platform)),id=\(simulator.udid)",
                     resultBundle: resultBundle)
        return resultBundle
    }

    // MARK: - Steps

    private func runTests(_ run: CaptureRun, destination: String, resultBundle: URL) throws {
        let (language, region) = LocaleCode.split(run.language)
        var arguments = ["test-without-building"] + containerArguments + [
            "-scheme", run.target.scheme,
            "-destination", destination,
            "-derivedDataPath", derivedData(run.target.platform).path,
            "-only-testing:\(run.target.tests)",
            "-testLanguage", language,
        ]
        if let region { arguments += ["-testRegion", region] }
        arguments += ["-parallel-testing-enabled", "NO", "-resultBundlePath", resultBundle.path]

        let environment = [
            "TEST_RUNNER_SA2_DISPLAY": run.display?.name ?? "primary",
            "TEST_RUNNER_SA2_LANDSCAPE": run.landscape ? "1" : "0",
            "TEST_RUNNER_SA2_APPEARANCE": run.appearance.rawValue,
        ]
        var result = try shell.run("xcodebuild", arguments, environment: environment)
        if result.exitCode == Self.timeoutExitCode {
            // xcodebuild sometimes hangs after the tests finished; one more attempt starts clean.
            log("\(run.slug): xcodebuild timed out, trying once more…")
            try? FileManager.default.removeItem(at: resultBundle)
            result = try shell.run("xcodebuild", arguments, environment: environment)
        }
        guard result.exitCode == 0 else {
            throw RunnerError.testFailed(slug: run.slug, logTail: Self.logTail(result))
        }
    }

    private func simctl(_ run: CaptureRun, _ step: String, _ arguments: [String]) throws {
        let result = try shell.run("xcrun", ["simctl"] + arguments, environment: [:])
        guard result.exitCode == 0 else {
            throw RunnerError.setupFailed(slug: run.slug, step: step, logTail: Self.logTail(result))
        }
    }

    /// Bundle ID of the app under test (looked up once per scheme).
    private func appBundleID(for run: CaptureRun) throws -> String {
        let scheme = run.target.scheme
        if let cached = bundleIDs.value(for: scheme) { return cached }

        let arguments = ["-showBuildSettings", "-json"] + containerArguments + ["-scheme", scheme]
        let result = try shell.run("xcodebuild", arguments, environment: [:])
        guard result.exitCode == 0 else {
            throw RunnerError.setupFailed(slug: run.slug, step: "bundle id lookup", logTail: Self.logTail(result))
        }
        struct Entry: Decodable { var target: String; var buildSettings: [String: String] }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: result.stdout) else {
            throw RunnerError.setupFailed(slug: run.slug, step: "bundle id lookup", logTail: "unreadable build settings")
        }
        let uiTarget = run.target.tests.split(separator: "/").first.map(String.init)
        let appName = entries.first { $0.target == uiTarget }?.buildSettings["TEST_TARGET_NAME"]
        let app = entries.first { $0.target == appName } ?? entries.first { $0.buildSettings["TEST_TARGET_NAME"] == nil }
        guard let id = app?.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] else {
            throw RunnerError.setupFailed(slug: run.slug, step: "bundle id lookup", logTail: "no PRODUCT_BUNDLE_IDENTIFIER for the app target")
        }
        bundleIDs.set(id, for: scheme)
        return id
    }

    // MARK: - Helpers

    private var containerArguments: [String] {
        if let workspace = config.workspace { return ["-workspace", root.appendingPathComponent(workspace).path] }
        return ["-project", root.appendingPathComponent(config.project ?? "").path]
    }

    private func derivedData(_ platform: Platform) -> URL {
        workDir.appendingPathComponent("dd-\(platform.rawValue)")
    }

    static func genericDestination(_ platform: Platform) -> String {
        platform == .macOS ? "platform=macOS" : "generic/platform=\(simulatorPlatform(platform))"
    }

    static func simulatorPlatform(_ platform: Platform) -> String {
        platform == .macOS ? "macOS" : "\(platform.rawValue) Simulator"
    }

    /// The last 40 lines of the combined output.
    static func logTail(_ result: CommandResult) -> String {
        let text = result.stdoutString + (result.stderr.isEmpty ? "" : "\n" + result.stderrString)
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(40).joined(separator: "\n")
    }
}

private final class BundleIDCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func value(for scheme: String) -> String? { lock.withLock { values[scheme] } }
    func set(_ id: String, for scheme: String) { lock.withLock { values[scheme] = id } }
}
