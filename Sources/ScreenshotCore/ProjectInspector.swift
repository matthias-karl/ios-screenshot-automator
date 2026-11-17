import Foundation

public struct ProjectInfo: Equatable, Sendable {
    /// File name relative to the inspected directory, e.g. `Demo.xcodeproj`.
    public var container: String
    public var isWorkspace: Bool
    public var schemes: [String]
    public var uiTestTargets: [String]

    public init(container: String, isWorkspace: Bool, schemes: [String], uiTestTargets: [String]) {
        self.container = container
        self.isWorkspace = isWorkspace
        self.schemes = schemes
        self.uiTestTargets = uiTestTargets
    }
}

public enum ProjectInspectorError: Error, Equatable, CustomStringConvertible {
    case noProject(String)
    case xcodebuildFailed(String)
    case unreadableOutput

    public var description: String {
        switch self {
        case .noProject(let directory): return "No .xcworkspace or .xcodeproj found in \(directory). Run this command in your app's folder."
        case .xcodebuildFailed(let message): return "xcodebuild -list failed: \(message)"
        case .unreadableOutput: return "Cannot read the output of xcodebuild -list."
        }
    }
}

/// Finds the Xcode project of an app and its schemes and UI test targets.
public enum ProjectInspector {
    /// Prefers a workspace over a project. UI test targets are targets whose name ends in `UITests`
    /// (a workspace does not list targets; the wizard then asks).
    public static func inspect(directory: URL, shell: CommandRunning) throws -> ProjectInfo {
        let entries = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        let workspace = entries.first { $0.hasSuffix(".xcworkspace") }
        let project = entries.first { $0.hasSuffix(".xcodeproj") }
        guard let container = workspace ?? project else { throw ProjectInspectorError.noProject(directory.path) }
        let isWorkspace = workspace != nil

        let result = try shell.run(
            "xcodebuild", ["-list", "-json", isWorkspace ? "-workspace" : "-project", directory.appendingPathComponent(container).path],
            environment: [:])
        guard result.exitCode == 0 else {
            throw ProjectInspectorError.xcodebuildFailed(result.stderrString.isEmpty ? result.stdoutString : result.stderrString)
        }
        guard let root = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
              let body = (root["workspace"] ?? root["project"]) as? [String: Any]
        else { throw ProjectInspectorError.unreadableOutput }

        let schemes = body["schemes"] as? [String] ?? []
        let targets = body["targets"] as? [String] ?? []
        return ProjectInfo(container: container, isWorkspace: isWorkspace, schemes: schemes,
                           uiTestTargets: targets.filter { $0.hasSuffix("UITests") })
    }
}
