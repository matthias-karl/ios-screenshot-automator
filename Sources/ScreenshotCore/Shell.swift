import Foundation

public struct CommandResult: Sendable {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: Data

    public init(exitCode: Int32, stdout: Data, stderr: Data) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

/// Runs external programs. Always called with an argument array, never a shell string.
public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult
}

extension CommandRunning {
    public func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        try run(executable, arguments, environment: [:])
    }
}

/// Starts real processes via `/usr/bin/env` (so `xcrun`, `xcodebuild` are found on `PATH`).
public struct ProcessRunner: CommandRunning {
    private let echo: Bool

    /// - Parameter echo: print each command line to stderr before running it.
    public init(echo: Bool = false) {
        self.echo = echo
    }

    public func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult {
        if echo {
            let line = ([executable] + arguments).joined(separator: " ")
            FileHandle.standardError.write(Data("$ \(line)\n".utf8))
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        // Drain both pipes concurrently so a chatty child never blocks on a full pipe.
        let group = DispatchGroup()
        let outBox = DataBox(), errBox = DataBox()
        for (pipe, box) in [(outPipe, outBox), (errPipe, errBox)] {
            group.enter()
            DispatchQueue.global().async {
                box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
        }
        try process.run()
        process.waitUntilExit()
        group.wait()
        return CommandResult(exitCode: process.terminationStatus, stdout: outBox.data, stderr: errBox.data)
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
