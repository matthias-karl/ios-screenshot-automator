import Foundation
import Testing
@testable import ScreenshotCore

/// Keeps the documentation honest: complete config examples must load, the size table must match `StoreSizes`.
@Suite struct DocsTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func read(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Fenced code blocks with the given info string (```json … ```).
    func blocks(_ language: String, in text: String) -> [String] {
        var result: [String] = []
        var current: [String]?
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if let lines = current { result.append(lines.joined(separator: "\n")); current = nil }
                else if line.dropFirst(3).trimmingCharacters(in: .whitespaces) == language { current = [] }
            } else if current != nil {
                current?.append(line)
            }
        }
        return result
    }

    @Test func readmeIsShort() throws {
        let lines = try read("README.md").components(separatedBy: "\n").count
        #expect(lines <= 150, "README has \(lines) lines")
    }

    @Test(arguments: ["README.md", "Docs/Reference.md"])
    func completeConfigExamplesLoad(file: String) throws {
        let configs = blocks("json", in: try read(file))
        for (index, json) in configs.enumerated() {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("docs-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: url) }
            try Data(json.utf8).write(to: url)
            do { _ = try Config.load(from: url) } catch { Issue.record("\(file): json block \(index + 1) does not load: \(error)") }
        }
    }

    @Test func referenceHasAtLeastOneCompleteExample() throws {
        #expect(!blocks("json", in: try read("Docs/Reference.md")).isEmpty)
        #expect(!blocks("json", in: try read("README.md")).isEmpty)
    }

    @Test func referenceSizeTableMatchesTheCode() throws {
        let reference = try read("Docs/Reference.md")
        #expect(reference.contains(StoreSizes.lastVerified))
        #expect(reference.contains(StoreSizes.source))
        for size in StoreSizes.all {
            #expect(reference.contains("`\(size.id)`"), "size id \(size.id) missing")
            for pixels in size.pixelSizes {
                #expect(reference.contains("\(pixels.width)×\(pixels.height)"), "\(size.id): \(pixels.width)×\(pixels.height) missing")
            }
        }
    }

    @Test func referenceDocumentsEveryConfigKey() throws {
        let reference = try read("Docs/Reference.md")
        let keys = ["version", "project", "workspace", "targets", "languages", "appearances", "permissions", "style", "sizeStyles",
                    "shots", "macCanvas", "output", "platform", "scheme", "tests", "sizes", "landscape", "background", "frame",
                    "frameColor", "frameImage", "caption", "title", "subtitle", "position", "font", "gradient", "angle"]
        for key in keys { #expect(reference.contains("`\(key)`"), "config key \(key) not documented") }
    }

    @Test func referenceDocumentsCommandsAndExitCodes() throws {
        let reference = try read("Docs/Reference.md")
        for command in ["screenshots init", "screenshots run", "screenshots compose", "screenshots check", "screenshots sizes"] {
            #expect(reference.contains(command), "\(command) not documented")
        }
        #expect(reference.contains("SCREENSHOTS_COMMAND_TIMEOUT"))
    }

    @Test func macAndWatchAreMarkedUnverified() throws {
        for file in ["README.md", "Docs/Reference.md"] {
            #expect(try read(file).contains("issues/6"), "\(file) should point to issue 6 for Mac and Watch")
        }
    }

    @Test func agentSkillIsWellFormed() throws {
        let skill = try read("skills/ios-screenshots/SKILL.md")
        #expect(skill.hasPrefix("---\nname: ios-screenshots\n"), "frontmatter must start with the folder name")
        #expect(skill.contains("\ndescription: "))
        for command in ["screenshots init", "screenshots run", "screenshots compose", "screenshots check", "screenshots sizes"] {
            #expect(skill.contains(command), "skill should mention \(command)")
        }
        #expect(skill.contains("--yes"), "skill should show the non-interactive init")
        #expect(skill.components(separatedBy: "\n").count <= 200, "keep the skill short; details belong in Docs/Reference.md")
    }

    @Test func oldDocumentsAreGone() {
        for file in ["Docs/QuickStart.md", "Docs/DeveloperHowto.md", "Docs/ScreenshotPipeline.md"] {
            #expect(!FileManager.default.fileExists(atPath: Self.root.appendingPathComponent(file).path), "\(file) should be deleted")
        }
    }
}
