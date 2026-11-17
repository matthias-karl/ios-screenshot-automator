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
        subcommands: [Run.self, Compose.self, Check.self, Sizes.self]
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
