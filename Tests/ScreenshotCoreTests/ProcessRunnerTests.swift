import Foundation
import Testing
@testable import ScreenshotCore

@Suite struct ProcessRunnerTests {
    @Test func capturesOutputAndExitCode() throws {
        let result = try ProcessRunner().run("sh", ["-c", "echo out; echo err 1>&2; exit 3"], environment: [:])
        #expect(result.exitCode == 3)
        #expect(result.stdoutString == "out\n")
        #expect(result.stderrString == "err\n")
    }

    @Test func passesEnvironmentAndKeepsArgumentsIntact() throws {
        let result = try ProcessRunner().run("sh", ["-c", "printf '%s|%s' \"$SA2_TEST\" \"$1\"", "sh", "a b  c"], environment: ["SA2_TEST": "yes"])
        #expect(result.stdoutString == "yes|a b  c")
    }

    @Test func largeOutputDoesNotBlock() throws {
        let result = try ProcessRunner().run("sh", ["-c", "head -c 3000000 /dev/zero | tr '\\0' x"], environment: [:])
        #expect(result.stdout.count == 3_000_000)
    }

    @Test func timeoutKillsAHungProcess() throws {
        let started = Date()
        let result = try ProcessRunner(timeout: 0.5).run("sleep", ["30"], environment: [:])
        #expect(Date().timeIntervalSince(started) < 10)
        #expect(result.exitCode != 0)
        #expect(result.stderrString.contains("timed out"))
    }
}
