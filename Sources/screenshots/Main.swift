import ArgumentParser
import Foundation
import ScreenshotCore

@main
struct Screenshots: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshots",
        abstract: "Create App Store screenshots from XCUITest runs.",
        discussion: """
        Exit codes: 0 success · 1 a requested image is missing or a check failed · 2 invalid configuration.
        """,
        version: "2.0.0",
        subcommands: [Init.self, Run.self, Compose.self, Check.self, Sizes.self]
    )
}

// MARK: - Shared options

struct GlobalOptions: ParsableArguments {
    @Option(help: "Path to screenshots.json.")
    var config: String = "./screenshots.json"

    var configURL: URL { URL(fileURLWithPath: config) }
}

struct FilterOptions: ParsableArguments {
    @Option(name: .customLong("size"), help: "Only this size ID (repeatable, see `screenshots sizes`).")
    var sizes: [String] = []

    @Option(name: .customLong("language"), help: "Only this language, e.g. en-US (repeatable).")
    var languages: [String] = []

    @Option(name: .customLong("scheme"), help: "Only the target with this scheme (repeatable).")
    var schemes: [String] = []

    var filter: RunFilter {
        var filter = RunFilter()
        if !sizes.isEmpty { filter.sizes = Set(sizes) }
        if !languages.isEmpty { filter.languages = Set(languages) }
        if let scheme = schemes.first { filter.scheme = scheme }
        return filter
    }
}

// MARK: - Output

enum Console {
    static func out(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    static func err(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

/// Longest time one external command (xcodebuild, simctl …) may run. Override with
/// `SCREENSHOTS_COMMAND_TIMEOUT` (seconds); a hung xcodebuild must not block forever.
var commandTimeout: TimeInterval {
    ProcessInfo.processInfo.environment["SCREENSHOTS_COMMAND_TIMEOUT"].flatMap(TimeInterval.init) ?? 20 * 60
}

func makePipeline(_ options: GlobalOptions) -> Pipeline {
    Pipeline(configURL: options.configURL, shell: ProcessRunner(timeout: commandTimeout), log: { Console.out($0) })
}

/// Runs a pipeline step, prints problems and maps the outcome to the exit code.
func execute(success: (PipelineResult) -> String = { "✓ Done (\($0.finalFiles.count) images written)." }, _ body: () throws -> PipelineResult) throws {
    do {
        let result = try body()
        for failure in result.failures { Console.err("error: \(failure)") }
        for issue in result.issues { Console.err(issue.description) }
        if result.succeeded {
            Console.out(success(result))
        } else {
            Console.err("✗ Failed.")
            throw ExitCode(1)
        }
    } catch let error as ConfigError {
        switch error {
        case .invalid(let issues): for issue in issues { Console.err("config error: \(issue)") }
        case .unreadable(let message): Console.err("config error: \(message)")
        }
        throw ExitCode(2)
    }
}

// MARK: - Commands

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Capture, compose and validate all screenshots.")
    @OptionGroup var global: GlobalOptions
    @OptionGroup var filter: FilterOptions

    func run() throws {
        try execute { try makePipeline(global).run(filter: filter.filter) }
    }
}

struct Compose: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Rebuild the final images from existing raw images (no simulator).")
    @OptionGroup var global: GlobalOptions
    @OptionGroup var filter: FilterOptions

    func run() throws {
        try execute { try makePipeline(global).compose(filter: filter.filter) }
    }
}

struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check configuration, installed simulators and required sizes. Changes nothing.")
    @OptionGroup var global: GlobalOptions

    func run() throws {
        try execute(success: { "✓ Configuration and simulators are fine (\($0.runs.count) runs planned)." }) {
            try makePipeline(global).check()
        }
    }
}

struct Sizes: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List all known App Store sizes and the simulator that would be used.")

    func run() throws {
        let catalog = try DeviceCatalog.load(shell: ProcessRunner(timeout: 120))
        Console.out("Sizes verified \(StoreSizes.lastVerified) against \(StoreSizes.source)\n")
        let rows = Pipeline.sizeTable(catalog: catalog)
        let width = rows.map(\.id.count).max() ?? 0
        for row in rows {
            let sizes = row.pixelSizes.map { "\($0.width)×\($0.height)" }.joined(separator: ", ")
            let marker = row.required ? "required" : "optional"
            let simulator = row.simulator ?? "not installed"
            Console.out("\(row.id.padding(toLength: width, withPad: " ", startingAt: 0))  \(marker)  \(sizes)\n    → \(simulator)")
        }
    }
}

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create screenshots.json and a UI-test scaffold for the app in the current folder.",
        discussion: """
        Asks a few questions in a terminal. With --yes, or without a terminal (for example when a coding agent runs it), nothing is asked: given options win, everything else takes the defaults.

        Example: screenshots init --yes --scheme MyApp --size iphone-6.3 --size ipad-13 --language en-US --language de-DE
        """)

    @Flag(help: "Do not ask; use the given options and the defaults.")
    var yes = false

    @Option(help: "Scheme that builds the app and runs the UI tests.")
    var scheme: String?

    @Option(name: .customLong("ui-tests"), help: "UI-test target that gets Screenshots.swift.")
    var uiTests: String?

    @Option(name: .customLong("size"), help: "iOS size ID (repeatable; default: required sizes plus every installed one).")
    var sizes: [String] = []

    @Option(name: .customLong("language"), help: "App Store language code (repeatable; default en-US).")
    var languages: [String] = []

    @Option(help: "Frame style: outline, bezel, image or none (default outline).")
    var frame: String?

    @Option(name: .customLong("frame-image"), help: "PNG with a transparent screen area, for --frame image.")
    var frameImage: String?

    @Option(name: .customLong("gradient"), help: "Background gradient, two colors: --gradient '#1f881b' --gradient '#79b474'.")
    var gradient: [String] = []

    @Flag(name: .customLong("no-gitignore"), help: "Do not add raw/ and .work/ to .gitignore.")
    var noGitignore = false

    var presets: PresetAnswers {
        PresetAnswers(
            scheme: scheme, uiTestTarget: uiTests, sizes: sizes.isEmpty ? nil : sizes,
            languages: languages.isEmpty ? nil : languages, frame: frame, frameImage: frameImage,
            gradient: gradient.isEmpty ? nil : gradient)
    }

    /// No questions with --yes, with any preset option, or when stdin is not a terminal.
    var interactive: Bool {
        !yes && scheme == nil && uiTests == nil && sizes.isEmpty && languages.isEmpty && frame == nil
            && gradient.isEmpty && isatty(STDIN_FILENO) == 1
    }

    func run() throws {
        let problems = presets.problems
        guard problems.isEmpty else {
            for problem in problems { Console.err("error: \(problem)") }
            throw ExitCode(2)
        }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let configURL = directory.appendingPathComponent("screenshots.json")
        guard !FileManager.default.fileExists(atPath: configURL.path) else {
            Console.err("error: screenshots.json already exists. Edit it, or delete it to start over.")
            throw ExitCode(1)
        }

        let shell = ProcessRunner(timeout: 120)
        let info: ProjectInfo
        let catalog: DeviceCatalog
        do {
            info = try ProjectInspector.inspect(directory: directory, shell: shell)
            catalog = try DeviceCatalog.load(shell: shell)
        } catch {
            Console.err("error: \(error)")
            throw ExitCode(1)
        }
        Console.out("Project: \(info.container)\n")

        let prompt: Prompting = interactive ? TerminalPrompt() : presets
        let result = InitWizard.run(info: info, catalog: catalog, prompt: prompt)

        let testURL = directory.appendingPathComponent(result.testFilePath)
        guard !FileManager.default.fileExists(atPath: testURL.path) else {
            Console.err("error: \(result.testFilePath) already exists; nothing was written. Pick another UI test target or move the file.")
            throw ExitCode(1)
        }
        try Data(InitWizard.configJSON(result.config).utf8).write(to: configURL)
        try FileManager.default.createDirectory(at: testURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(result.testFileContents.utf8).write(to: testURL)
        Console.out("\n✓ screenshots.json written")
        Console.out("✓ \(result.testFilePath) created (add it to the UI test target in Xcode, and add the ScreenshotAutomator package to that target)")

        let addToGitignore = noGitignore ? false
            : interactive ? TerminalPrompt().confirm("Add \(result.gitignoreLines.joined(separator: " and ")) to .gitignore?", default: true)
            : true
        if addToGitignore {
            let gitignore = directory.appendingPathComponent(".gitignore")
            let existing = (try? String(contentsOf: gitignore, encoding: .utf8)) ?? ""
            let missing = result.gitignoreLines.filter { !existing.contains($0) }
            if !missing.isEmpty {
                let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
                try (existing + separator + missing.joined(separator: "\n") + "\n").write(to: gitignore, atomically: true, encoding: .utf8)
                Console.out("✓ .gitignore updated")
            }
        }
        Console.out("\n\(InitWizard.launchArgumentsSnippet)\n")
        Console.out("→ Next: screenshots run")
    }
}

/// Questions on the terminal; an empty answer takes the default.
struct TerminalPrompt: Prompting {
    func ask(_ question: String, default fallback: String?) -> String {
        FileHandle.standardOutput.write(Data((fallback.map { "\(question) [\($0)]: " } ?? "\(question): ").utf8))
        let answer = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        return answer.isEmpty ? (fallback ?? "") : answer
    }

    func choose(_ question: String, options: [String], preselected: Set<Int>) -> Set<Int> {
        Console.out(question)
        for (index, option) in options.enumerated() {
            Console.out("  \(index + 1)) [\(preselected.contains(index) ? "x" : " ")] \(option)")
        }
        FileHandle.standardOutput.write(Data("Numbers, comma separated (empty = keep the marked ones): ".utf8))
        let answer = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !answer.isEmpty else { return preselected }
        let picked = answer.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int($0) }.map { $0 - 1 }
        return Set(picked.filter { options.indices.contains($0) })
    }

    func confirm(_ question: String, default fallback: Bool) -> Bool {
        FileHandle.standardOutput.write(Data("\(question) [\(fallback ? "Y/n" : "y/N")]: ".utf8))
        let answer = (readLine() ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return answer.isEmpty ? fallback : answer.hasPrefix("y")
    }
}
