import Foundation

/// The contract between the UI-test library (`ScreenshotAutomator`) and the
/// command-line tool (`ScreenshotCore`). Both sides must agree on these values.
public enum ShotProtocol {
    /// Bumped whenever the attachment naming or environment contract changes.
    public static let version = 2

    /// Every screenshot attachment name starts with this prefix.
    public static let attachmentPrefix = "sa2v2__"

    /// Environment variables the tool passes to the test run
    /// (the `TEST_RUNNER_` prefix is added by `xcodebuild`).
    public enum Env {
        public static let display = "SA2_DISPLAY"
        public static let landscape = "SA2_LANDSCAPE"
        public static let appearance = "SA2_APPEARANCE"
    }

    public enum Parsed: Equatable, Sendable {
        case shot(String)
        case otherVersion(Int)
    }

    /// Shot names: `^[A-Za-z0-9][A-Za-z0-9_-]*$` (ASCII only).
    public static func isValidShotName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, isAlphanumeric(first) else { return false }
        return name.unicodeScalars.allSatisfy { isAlphanumeric($0) || $0 == "_" || $0 == "-" }
    }

    public static func attachmentName(for shot: String) -> String {
        attachmentPrefix + shot
    }

    /// Reads a shot name from an attachment name. Accepts the bare name as well as
    /// the file-like form Xcode exports (`<name>_<index>_<UUID>.<ext>`).
    /// Returns `nil` for attachments that are not ours.
    public static func parse(attachmentName: String) -> Parsed? {
        // "sa2v<digits>__<rest>"
        let scalars = Array(attachmentName.unicodeScalars)
        guard attachmentName.hasPrefix("sa2v") else { return nil }
        var index = 4
        var digits = ""
        while index < scalars.count, scalars[index].properties.numericType != nil, scalars[index].isASCII {
            digits.unicodeScalars.append(scalars[index])
            index += 1
        }
        guard let version = Int(digits), attachmentName.dropFirst(4 + digits.count).hasPrefix("__") else {
            return nil
        }
        guard version == Self.version else { return .otherVersion(version) }

        var rest = String(attachmentName.dropFirst(4 + digits.count + 2))
        if rest.lowercased().hasSuffix(".png") { rest.removeLast(4) }
        rest = strippingExportSuffix(rest)
        return isValidShotName(rest) ? .shot(rest) : nil
    }

    // MARK: - Helpers

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        (scalar >= "0" && scalar <= "9") || (scalar >= "A" && scalar <= "Z") || (scalar >= "a" && scalar <= "z")
    }

    /// Removes a trailing `_<digits>_<UUID>` (36 hex/dash characters) if present.
    private static func strippingExportSuffix(_ name: String) -> String {
        let parts = name.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return name }
        let uuid = parts[parts.count - 1]
        let counter = parts[parts.count - 2]
        let looksLikeUUID = uuid.count == 36 && uuid.unicodeScalars.allSatisfy {
            $0 == "-" || ($0 >= "0" && $0 <= "9") || ($0 >= "A" && $0 <= "F") || ($0 >= "a" && $0 <= "f")
        }
        let looksLikeCounter = !counter.isEmpty && counter.unicodeScalars.allSatisfy { $0 >= "0" && $0 <= "9" }
        guard looksLikeUUID, looksLikeCounter else { return name }
        return parts.dropLast(2).joined(separator: "_")
    }
}
