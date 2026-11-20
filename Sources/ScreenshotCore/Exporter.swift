import Foundation
import ScreenshotProtocol

public struct RawShot: Equatable, Sendable {
    public var name: String
    public var file: URL

    public init(name: String, file: URL) {
        self.name = name
        self.file = file
    }
}

public enum ExportError: Error, Equatable, CustomStringConvertible {
    case toolFailed(String)
    case noShots(slug: String)
    case duplicateShot(slug: String, name: String)
    case protocolMismatch(found: Int, expected: Int)

    public var description: String {
        switch self {
        case .toolFailed(let message):
            return "xcresulttool failed: \(message)"
        case .noShots(let slug):
            return "Run \(slug) finished without any screenshot attachment. Does the test call shot(\"…\")?"
        case .duplicateShot(let slug, let name):
            return "Run \(slug) produced the shot \"\(name)\" more than once. Shot names must be unique per run."
        case .protocolMismatch(let found, let expected):
            return "The tests use screenshot protocol version \(found), but this tool speaks version \(expected). "
                + "Update the ScreenshotAutomator package and the screenshots tool to the same release."
        }
    }
}

/// Exports the screenshot attachments of a `.xcresult` into `raw/`.
public enum Exporter {
    /// Writes `rawRoot/<size.id>/<language>-<appearance>/<name>.png` and returns the shots sorted by name.
    /// The target folder is emptied first, so images of earlier runs never survive a failed run.
    public static func export(xcresult: URL, run: CaptureRun, rawRoot: URL, shell: CommandRunning) throws -> [RawShot] {
        let fm = FileManager.default
        let destination = rawRoot
            .appendingPathComponent(run.size.id)
            .appendingPathComponent("\(run.language)-\(run.appearance.rawValue)")
        try? fm.removeItem(at: destination)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let scratch = fm.temporaryDirectory.appendingPathComponent("sa2-export-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: scratch) }

        let result = try shell.run(
            "xcrun", ["xcresulttool", "export", "attachments", "--path", xcresult.path, "--output-path", scratch.path],
            environment: [:])
        guard result.exitCode == 0 else {
            throw ExportError.toolFailed(result.stderrString.isEmpty ? result.stdoutString : result.stderrString)
        }

        struct Entry: Decodable {
            struct Attachment: Decodable { var exportedFileName: String; var suggestedHumanReadableName: String }
            var attachments: [Attachment]
        }
        let entries: [Entry]
        do {
            entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: scratch.appendingPathComponent("manifest.json")))
        } catch {
            throw ExportError.toolFailed("unreadable manifest.json: \(error.localizedDescription)")
        }

        var shots: [String: URL] = [:]
        for attachment in entries.flatMap(\.attachments) {
            switch ShotProtocol.parse(attachmentName: attachment.suggestedHumanReadableName) {
            case nil:
                continue
            case .otherVersion(let found):
                throw ExportError.protocolMismatch(found: found, expected: ShotProtocol.version)
            case .shot(let name):
                guard shots[name] == nil else { throw ExportError.duplicateShot(slug: run.slug, name: name) }
                shots[name] = scratch.appendingPathComponent(attachment.exportedFileName)
            }
        }
        guard !shots.isEmpty else { throw ExportError.noShots(slug: run.slug) }

        var exported: [RawShot] = []
        for name in shots.keys.sorted() {
            let target = destination.appendingPathComponent("\(name).png")
            do {
                try fm.copyItem(at: shots[name]!, to: target)
            } catch {
                throw ExportError.toolFailed("missing exported file for \"\(name)\": \(error.localizedDescription)")
            }
            exported.append(RawShot(name: name, file: target))
        }
        return exported
    }
}
