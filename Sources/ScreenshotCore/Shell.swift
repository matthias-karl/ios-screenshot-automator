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
    private let timeout: TimeInterval?

    /// - Parameters:
    ///   - echo: print each command line to stderr before running it.
    ///   - timeout: terminate a command that runs longer (result: exit code 124); `nil` waits forever.
    public init(echo: Bool = false, timeout: TimeInterval? = nil) {
        self.echo = echo
        self.timeout = timeout
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
                let handle = pipe.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    box.append(chunk)
                }
                group.leave()
            }
        }
        try process.run()

        let timedOut = Flag()
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                timedOut.set()
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        process.waitUntilExit()
        if timedOut.isSet {
            // Grandchildren may keep the pipes open; do not wait for them forever.
            _ = group.wait(timeout: .now() + 3)
            var stderr = errBox.snapshot()
            stderr.append(Data("\ncommand timed out after \(Int(timeout ?? 0)) s and was terminated\n".utf8))
            return CommandResult(exitCode: 124, stdout: outBox.snapshot(), stderr: stderr)
        }
        group.wait()
        return CommandResult(exitCode: process.terminationStatus, stdout: outBox.snapshot(), stderr: errBox.snapshot())
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    func snapshot() -> Data { lock.withLock { data } }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
