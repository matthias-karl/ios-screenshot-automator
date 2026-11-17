import CoreGraphics
import Foundation
import ImageIO

public struct PipelineResult: Sendable {
    public var runs: [CaptureRun]
    public var finalFiles: [URL]
    public var issues: [ValidationIssue]
    public var failures: [String]

    public init(runs: [CaptureRun] = [], finalFiles: [URL] = [], issues: [ValidationIssue] = [], failures: [String] = []) {
        self.runs = runs
        self.finalFiles = finalFiles
        self.issues = issues
        self.failures = failures
    }

    /// `true` only without failures and without validation errors (warnings are fine).
    public var succeeded: Bool {
        failures.isEmpty && !issues.contains { $0.severity == .error }
    }
}

public struct SizeRow: Equatable, Sendable {
    public var id: String
    public var label: String
    public var required: Bool
    public var pixelSizes: [PixelSize]
    /// Chosen simulator, "macOS (no simulator)", or `nil` when none is installed.
    public var simulator: String?
}

/// capture → compose → validate, relative to the folder of `screenshots.json`.
public struct Pipeline: Sendable {
    private let configURL: URL
    private let shell: CommandRunning
    private let log: @Sendable (String) -> Void
    private let catalogLoader: @Sendable () throws -> DeviceCatalog

    public init(configURL: URL, shell: CommandRunning, log: @escaping @Sendable (String) -> Void) {
        self.init(configURL: configURL, shell: shell, log: log, catalogLoader: { try DeviceCatalog.load(shell: shell) })
    }

    init(configURL: URL, shell: CommandRunning, log: @escaping @Sendable (String) -> Void,
         catalogLoader: @escaping @Sendable () throws -> DeviceCatalog) {
        self.configURL = configURL
        self.shell = shell
        self.log = log
        self.catalogLoader = catalogLoader
    }

    // MARK: Paths

    private struct Paths {
        var root: URL
        var output: URL
        var raw: URL { output.appendingPathComponent("raw") }
        var finalRoot: URL { output.appendingPathComponent("final") }
        var work: URL { output.appendingPathComponent(".work") }
        var index: URL { output.appendingPathComponent("index.html") }

        func finalDir(_ language: String) -> URL { finalRoot.appendingPathComponent(language) }
        func rawDir(_ run: CaptureRun) -> URL {
            raw.appendingPathComponent(run.size.id).appendingPathComponent("\(run.language)-\(run.appearance.rawValue)")
        }
    }

    private func load() throws -> (Config, Paths) {
        let config = try Config.load(from: configURL)
        let root = configURL.deletingLastPathComponent()
        return (config, Paths(root: root, output: root.appendingPathComponent(config.output)))
    }

    // MARK: Commands

    /// Validates configuration and setup. Changes nothing.
    public func check() throws -> PipelineResult {
        let (config, paths) = try load()
        var result = PipelineResult(issues: Validator.checkSet(config: config))
        switch planRuns(config, filter: RunFilter()) {
        case .failure(let failure): result.failures.append(failure.description)
        case .success(let runs): result.runs = runs
        }
        let produced = rawShotNames(paths)
        if !produced.isEmpty {
            result.failures += orphanTitles(config: config, produced: produced)
        }
        return result
    }

    /// Builds each target once and runs every planned capture; a failing run does not stop the others.
    public func capture(filter: RunFilter) throws -> PipelineResult {
        let (config, paths) = try load()
        switch planRuns(config, filter: filter) {
        case .failure(let failure): return PipelineResult(failures: [failure.description])
        case .success(let runs):
            let outcome = captureRuns(runs, config: config, paths: paths)
            return PipelineResult(runs: runs, failures: outcome.failures)
        }
    }

    /// Composes the final images from existing raw images. Starts no simulator.
    public func compose(filter: RunFilter) throws -> PipelineResult {
        let (config, paths) = try load()
        switch planRuns(config, filter: filter) {
        case .failure(let failure): return PipelineResult(failures: [failure.description])
        case .success(let runs):
            return composeRuns(runs, config: config, filter: filter, paths: paths, skipping: [], previousFailures: [])
        }
    }

    /// capture + compose + validate + `index.html`.
    public func run(filter: RunFilter) throws -> PipelineResult {
        let (config, paths) = try load()
        switch planRuns(config, filter: filter) {
        case .failure(let failure): return PipelineResult(failures: [failure.description])
        case .success(let runs):
            let outcome = captureRuns(runs, config: config, paths: paths)
            return composeRuns(runs, config: config, filter: filter, paths: paths,
                               skipping: outcome.failedSlugs, previousFailures: outcome.failures)
        }
    }

    /// All known sizes with the simulator that would be used.
    public static func sizeTable(catalog: DeviceCatalog) -> [SizeRow] {
        StoreSizes.all.map { size in
            var simulator: String?
            if size.platform == .macOS {
                simulator = "macOS (no simulator)"
            } else if let choice = try? Planner.pick(size: size, catalog: catalog) {
                let runtime = choice.simulator.runtimeIdentifier.split(separator: ".").last.map(String.init) ?? ""
                simulator = "\(choice.type.name) (\(runtime))"
            }
            return SizeRow(id: size.id, label: size.label, required: size.requiredWithinFamily,
                           pixelSizes: size.pixelSizes, simulator: simulator)
        }
    }

    // MARK: Planning

    private func planRuns(_ config: Config, filter: RunFilter) -> Swift.Result<[CaptureRun], PlanFailure> {
        do {
            let catalog = try catalogLoader()
            let runs = try Planner.plan(config: config, catalog: catalog, filter: filter)
            guard !runs.isEmpty else { return .failure(PlanFailure("The size/language/scheme filter matches no runs of this configuration.")) }
            return .success(runs)
        } catch let error as PlanError {
            return .failure(PlanFailure(error.description))
        } catch {
            return .failure(PlanFailure("Cannot read the installed simulators: \(error)"))
        }
    }

    private struct PlanFailure: Error, CustomStringConvertible, Sendable {
        var description: String
        init(_ description: String) { self.description = description }
    }

    // MARK: Capture

    private func captureRuns(_ runs: [CaptureRun], config: Config, paths: Paths) -> (failures: [String], failedSlugs: Set<String>) {
        let runner = Runner(config: config, root: paths.root, workDir: paths.work, shell: shell, log: log)
        var failures: [String] = []
        var failedSlugs = Set<String>()
        var built = Set<String>()
        var failedBuilds: [String: String] = [:]

        for run in runs {
            let key = "\(run.target.platform.rawValue)/\(run.target.scheme)"
            if failedBuilds[key] == nil, !built.contains(key) {
                do {
                    try runner.build(target: run.target)
                    built.insert(key)
                } catch {
                    failedBuilds[key] = "\(error)"
                    failures.append("\(error)")
                }
            }
            if failedBuilds[key] != nil {
                failedSlugs.insert(run.slug)
                try? FileManager.default.removeItem(at: paths.rawDir(run))
                continue
            }
            do {
                let bundle = try runner.capture(run)
                let shots = try Exporter.export(xcresult: bundle, run: run, rawRoot: paths.raw, shell: shell)
                log("\(run.slug): \(shots.count) screenshots")
            } catch {
                failures.append("\(run.slug): \(error)")
                // Every test method is its own run: when one fails, the screenshots of the others are
                // still in the result bundle and are kept (the run itself stays a failure).
                var exported = false
                if case RunnerError.testFailed = error,
                   let shots = try? Exporter.export(xcresult: runner.resultBundleURL(for: run), run: run, rawRoot: paths.raw, shell: shell) {
                    log("\(run.slug): \(shots.count) screenshots exported although the tests failed")
                    exported = true
                }
                if !exported {
                    failedSlugs.insert(run.slug)
                    // Never let an older capture pass for this one.
                    try? FileManager.default.removeItem(at: paths.rawDir(run))
                }
            }
        }
        return (failures, failedSlugs)
    }

    // MARK: Compose

    private func composeRuns(
        _ runs: [CaptureRun], config: Config, filter: RunFilter, paths: Paths,
        skipping: Set<String>, previousFailures: [String]
    ) -> PipelineResult {
        let fm = FileManager.default
        var failures = previousFailures
        var finalFiles: [URL] = []

        // 1. Replace everything in scope: images of earlier runs never stay behind.
        var cleared = Set<String>()
        for run in runs where cleared.insert("\(run.language)/\(run.size.id)").inserted {
            let dir = paths.finalDir(run.language)
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            where name.hasPrefix("\(run.size.id)_") && name.hasSuffix(".png") {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }

        // 2. Raw images per run.
        var rawByRun: [String: [(name: String, url: URL)]] = [:]
        for run in runs where !skipping.contains(run.slug) {
            let dir = paths.rawDir(run)
            let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
            if names.isEmpty {
                failures.append("\(run.slug): no raw images in \(dir.path). Run `screenshots capture` (or `run`) first.")
            } else {
                rawByRun[run.slug] = names.map { (String($0.dropLast(4)), dir.appendingPathComponent($0)) }
            }
        }

        // 3. Titles must belong to shots that exist.
        let produced = Set(rawByRun.values.flatMap { $0.map(\.name) })
        if !produced.isEmpty { failures += orphanTitles(config: config, produced: produced) }

        // 4. Compose.
        var frameImages: [String: CGImage] = [:]
        for run in runs {
            guard let shots = rawByRun[run.slug] else { continue }
            log("Composing \(run.slug) (\(shots.count) images)…")
            let style = config.style(forSize: run.size.id)
            var frameImage: CGImage?
            if style.frame == .image, let path = style.frameImage {
                if let cached = frameImages[path] {
                    frameImage = cached
                } else if let loaded = try? Self.loadImage(paths.root.appendingPathComponent(path)) {
                    frameImages[path] = loaded
                    frameImage = loaded
                } else {
                    failures.append("\(run.slug): cannot read the frame image \(path)")
                    continue
                }
            }
            let canvas = Self.canvas(for: run, config: config)
            for shot in shots {
                do {
                    let screenshot = try Self.loadImage(shot.url)
                    let actual = PixelSize(width: screenshot.width, height: screenshot.height)
                    if let reason = Self.rawSizeProblem(actual, run: run) {
                        failures.append("\(run.slug): raw image \(shot.name).png is \(actual.width)×\(actual.height); \(reason)")
                        continue
                    }
                    let texts = config.shots[shot.name]
                    let image = try Composer.compose(ComposeRequest(
                        screenshot: screenshot, canvas: canvas, display: run.display, hasDynamicIsland: run.hasDynamicIsland,
                        platform: run.size.platform, style: style,
                        title: texts?.title?[run.language], subtitle: texts?.subtitle?[run.language], frameImage: frameImage))
                    let target = paths.finalDir(run.language)
                        .appendingPathComponent(Validator.finalFileName(size: run.size.id, shot: shot.name, appearance: run.appearance))
                    try Composer.writePNG(image, to: target)
                    finalFiles.append(target)
                } catch {
                    failures.append("\(run.slug): \(shot.name): \(error)")
                }
            }
        }

        // 5. Validate and write the overview.
        var issues = Validator.checkSet(config: config)
        issues += Validator.checkOutput(finalDir: paths.finalRoot, config: Self.scoped(config, to: filter))
        do { try Report.writeIndex(finalDir: paths.finalRoot, to: paths.index) } catch {
            failures.append("Cannot write index.html: \(error)")
        }
        return PipelineResult(runs: runs, finalFiles: finalFiles, issues: issues, failures: failures)
    }

    // MARK: Helpers

    private func orphanTitles(config: Config, produced: Set<String>) -> [String] {
        config.shots.keys.sorted().filter { !produced.contains($0) }.map {
            "shots.\($0): has texts, but no test produced a shot named \"\($0)\"."
        }
    }

    private func rawShotNames(_ paths: Paths) -> Set<String> {
        let fm = FileManager.default
        var names = Set<String>()
        for size in (try? fm.contentsOfDirectory(atPath: paths.raw.path)) ?? [] {
            for variant in (try? fm.contentsOfDirectory(atPath: paths.raw.appendingPathComponent(size).path)) ?? [] {
                let dir = paths.raw.appendingPathComponent(size).appendingPathComponent(variant)
                for file in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where file.hasSuffix(".png") {
                    names.insert(String(file.dropLast(4)))
                }
            }
        }
        return names
    }

    static func loadImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path]) }
        return image
    }

    /// The exact App Store pixel size of the final image.
    static func canvas(for run: CaptureRun, config: Config) -> PixelSize {
        if run.size.platform == .macOS { return config.macCanvas }
        let oriented: (PixelSize) -> PixelSize = { $0.isLandscape == run.landscape ? $0 : $0.swapped }
        let accepted = run.size.pixelSizes.map(oriented)
        if let display = run.display?.pixelSize, accepted.contains(oriented(display)) { return oriented(display) }
        return accepted[0]
    }

    /// `nil` if the raw image has a size this run may produce.
    static func rawSizeProblem(_ actual: PixelSize, run: CaptureRun) -> String? {
        if run.size.platform == .macOS { return nil }   // window screenshots have any size
        var allowed = run.size.pixelSizes.flatMap { [$0, $0.swapped] }
        if let display = run.display?.pixelSize { allowed += [display, display.swapped] }
        guard !allowed.contains(actual) else { return nil }
        return "not a valid size for \(run.size.id). Is the wrong simulator booted?"
    }

    static func scoped(_ config: Config, to filter: RunFilter) -> Config {
        var scoped = config
        scoped.targets = config.targets.compactMap { target in
            if let scheme = filter.scheme, scheme != target.scheme { return nil }
            var target = target
            if let sizes = filter.sizes { target.sizes = target.sizes.filter(sizes.contains) }
            return target.sizes.isEmpty ? nil : target
        }
        if let languages = filter.languages { scoped.languages = config.languages.filter(languages.contains) }
        return scoped
    }
}
