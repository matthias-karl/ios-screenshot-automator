import Foundation
@testable import ScreenshotCore

/// Records every command and answers from stubs (longest matching prefix wins).
/// Unstubbed commands succeed with empty output.
final class FakeRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    private var _environments: [[String: String]] = []
    private var stubs: [(prefix: [String], handler: @Sendable ([String]) throws -> CommandResult)] = []

    /// Every call as one argv: `[executable] + arguments`.
    var calls: [[String]] { lock.withLock { _calls } }
    var environments: [[String: String]] { lock.withLock { _environments } }

    func stub(prefix: [String], result: CommandResult) {
        stub(prefix: prefix) { _ in result }
    }

    func stub(prefix: [String], handler: @escaping @Sendable ([String]) throws -> CommandResult) {
        lock.withLock { stubs.append((prefix, handler)) }
    }

    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult {
        let argv = [executable] + arguments
        let handler: (@Sendable ([String]) throws -> CommandResult)? = lock.withLock {
            _calls.append(argv)
            _environments.append(environment)
            return stubs
                .filter { argv.starts(with: $0.prefix) }
                .max { $0.prefix.count < $1.prefix.count }?
                .handler
        }
        return try handler?(argv) ?? CommandResult.ok()
    }
}

extension CommandResult {
    static func ok(_ text: String = "") -> CommandResult {
        CommandResult(exitCode: 0, stdout: Data(text.utf8), stderr: Data())
    }

    static func failure(_ code: Int32 = 1, stderr: String = "") -> CommandResult {
        CommandResult(exitCode: code, stdout: Data(), stderr: Data(stderr.utf8))
    }
}
