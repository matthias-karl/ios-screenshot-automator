import CoreGraphics
import Foundation
import ImageIO

public struct ValidationIssue: Equatable, Sendable, CustomStringConvertible {
    public enum Severity: Sendable { case error, warning }

    public var severity: Severity
    public var file: String?
    public var message: String

    public init(severity: Severity, file: String? = nil, message: String) {
        self.severity = severity
        self.file = file
        self.message = message
    }

    public var description: String {
        let label = severity == .error ? "error" : "warning"
        return "\(label): \(message)"
    }
}

/// Checks the configured size set and the finished images against Apple's rules.
public enum Validator {
    /// `<size>_<shot>.png`, or `<size>_<shot>_dark.png` for the dark appearance.
    public static func finalFileName(size: String, shot: String, appearance: Appearance) -> String {
        "\(size)_\(shot)\(appearance == .dark ? "_dark" : "").png"
    }

    // MARK: Without files

    /// Required sizes per family and the Apple Watch rule.
    public static func checkSet(config: Config) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var configured: [String] = []
        for id in config.targets.flatMap(\.sizes) where !configured.contains(id) { configured.append(id) }
        let known = configured.compactMap(StoreSizes.size(id:))
        let families = Set(known.map(\.family))

        for family in StoreSize.Family.allCases where families.contains(family) {
            for size in StoreSizes.all where size.family == family && size.requiredWithinFamily && !configured.contains(size.id) {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "\(size.label) (\"\(size.id)\") is required whenever other \(family.rawValue) sizes are delivered, but it is not in \"sizes\"."))
            }
        }

        let watchSizes = known.filter { $0.family == .watch }.map(\.id)
        if watchSizes.count > 1 {
            issues.append(ValidationIssue(
                severity: .error,
                message: "Apple Watch screenshots use exactly one size for all languages, but \(watchSizes.count) are configured (\(watchSizes.joined(separator: ", ")))."))
        }

        if families.contains(.iPhone) {
            let duo = ["iphone-duo-outer", "iphone-duo-inner"].filter { !configured.contains($0) }
            if !duo.isEmpty {
                issues.append(ValidationIssue(
                    severity: .warning,
                    message: "iPhone Duo size missing (\(duo.joined(separator: ", "))): required from April 2027 for apps built with the iOS 27.1 SDK."))
            }
        }
        return issues
    }

    // MARK: Files

    private struct Entry {
        var language: String
        var fileName: String
        var sizeID: String
    }

    /// Checks `finalDir/<language>/*.png`: pixel size, alpha channel, 1–10 images per size and language,
    /// and the same set of shots in every language.
    public static func checkOutput(finalDir: URL, config: Config) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var entries: [Entry] = []
        let fm = FileManager.default

        for language in config.languages {
            let dir = finalDir.appendingPathComponent(language)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else {
                issues.append(ValidationIssue(severity: .error, file: language, message: "No images for language \(language): folder \(language)/ is missing."))
                continue
            }
            for name in names.sorted() where name.lowercased().hasSuffix(".png") && !name.hasPrefix(".") {
                let relative = "\(language)/\(name)"
                guard let underscore = name.firstIndex(of: "_") else {
                    issues.append(ValidationIssue(severity: .error, file: relative, message: "\(relative): file name does not look like <size>_<shot>.png."))
                    continue
                }
                let sizeID = String(name[..<underscore])
                guard let size = StoreSizes.size(id: sizeID) else {
                    issues.append(ValidationIssue(severity: .error, file: relative, message: "\(relative): \"\(sizeID)\" is not a known size."))
                    continue
                }
                entries.append(Entry(language: language, fileName: name, sizeID: sizeID))
                issues += checkFile(dir.appendingPathComponent(name), relative: relative, size: size, macCanvas: config.macCanvas)
            }
        }

        var configured: [String] = []
        for id in config.targets.flatMap(\.sizes) where !configured.contains(id) { configured.append(id) }

        // 1–10 images per size and language.
        for language in config.languages where fm.fileExists(atPath: finalDir.appendingPathComponent(language).path) {
            for id in configured {
                let count = entries.filter { $0.language == language && $0.sizeID == id }.count
                if count == 0 {
                    issues.append(ValidationIssue(severity: .error, message: "No images for size \(id) in \(language)."))
                } else if count > 10 {
                    issues.append(ValidationIssue(severity: .error, message: "\(count) images for size \(id) in \(language); App Store Connect accepts at most 10."))
                }
            }
        }

        // Same shots in every language, per size.
        let present = config.languages.filter { language in entries.contains { $0.language == language } }
        for id in configured {
            let perLanguage = Dictionary(uniqueKeysWithValues: present.map { language in
                (language, Set(entries.filter { $0.language == language && $0.sizeID == id }.map(\.fileName)))
            })
            let union = perLanguage.values.reduce(into: Set<String>()) { $0.formUnion($1) }
            for language in present {
                let missing = union.subtracting(perLanguage[language] ?? []).sorted()
                guard !missing.isEmpty else { continue }
                let donor = present.first { !(perLanguage[$0] ?? []).isDisjoint(with: missing) } ?? language
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "\(language) is missing \(missing.joined(separator: ", ")) for size \(id) (present in \(donor)); all languages need the same shots."))
            }
        }
        return issues
    }

    private static func checkFile(_ url: URL, relative: String, size: StoreSize, macCanvas: PixelSize) -> [ValidationIssue] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return [ValidationIssue(severity: .error, file: relative, message: "\(relative): not a readable image.")]
        }
        var issues: [ValidationIssue] = []
        let actual = PixelSize(width: width, height: height)
        let allowed = size.family == .mac ? [macCanvas] : size.pixelSizes.flatMap { [$0, $0.swapped] }
        if !allowed.contains(actual) {
            let expected = allowed.map { "\($0.width)×\($0.height)" }.joined(separator: " or ")
            issues.append(ValidationIssue(
                severity: .error, file: relative,
                message: "\(relative): \(width)×\(height) px is not valid for \(size.id) (expected \(expected))."))
        }
        if properties[kCGImagePropertyHasAlpha] as? Bool == true {
            issues.append(ValidationIssue(
                severity: .error, file: relative,
                message: "\(relative): has an alpha channel; App Store Connect rejects screenshots with transparency."))
        }
        return issues
    }
}

