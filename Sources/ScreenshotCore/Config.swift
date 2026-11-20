import Foundation
import ScreenshotProtocol

/// The contents of `screenshots.json`.
public struct Config: Codable, Equatable, Sendable {
    public var version: Int
    public var project: String?
    public var workspace: String?
    public var targets: [Target]
    public var languages: [String]
    public var appearances: [Appearance]
    public var permissions: [String]
    public var style: Style
    /// Replaces `style` completely for the given size ID.
    public var sizeStyles: [String: Style]
    public var shots: [String: Shot]
    public var macCanvas: PixelSize
    public var output: String

    public init(
        version: Int = 2,
        project: String? = nil,
        workspace: String? = nil,
        targets: [Target],
        languages: [String],
        appearances: [Appearance] = [.light],
        permissions: [String] = [],
        style: Style = Style(),
        sizeStyles: [String: Style] = [:],
        shots: [String: Shot] = [:],
        macCanvas: PixelSize = PixelSize(width: 2880, height: 1800),
        output: String = "screenshots"
    ) {
        self.version = version
        self.project = project
        self.workspace = workspace
        self.targets = targets
        self.languages = languages
        self.appearances = appearances
        self.permissions = permissions
        self.style = style
        self.sizeStyles = sizeStyles
        self.shots = shots
        self.macCanvas = macCanvas
        self.output = output
    }

    // MARK: Nested types

    public struct Target: Codable, Equatable, Sendable {
        public var platform: Platform
        public var scheme: String
        /// `<UITestTarget>/<TestClass>`, passed to `-only-testing:`.
        public var tests: String
        public var sizes: [String]
        /// Size IDs (subset of `sizes`) that are captured in landscape.
        public var landscape: [String]

        public init(platform: Platform, scheme: String, tests: String, sizes: [String], landscape: [String] = []) {
            self.platform = platform
            self.scheme = scheme
            self.tests = tests
            self.sizes = sizes
            self.landscape = landscape
        }

        enum CodingKeys: String, CodingKey { case platform, scheme, tests, sizes, landscape }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            platform = try c.decode(Platform.self, forKey: .platform)
            scheme = try c.decode(String.self, forKey: .scheme)
            tests = try c.decode(String.self, forKey: .tests)
            sizes = try c.decode([String].self, forKey: .sizes)
            landscape = try c.decodeIfPresent([String].self, forKey: .landscape) ?? []
        }
    }

    public struct Style: Codable, Equatable, Sendable {
        public var background: Background
        public var frame: Frame
        public var frameColor: String
        public var frameImage: String?
        public var caption: Caption?

        public static let defaultBackground = Background.gradient(["#2B2B2F", "#5A5A63"], angle: 135)

        public init(
            background: Background = Style.defaultBackground,
            frame: Frame = .outline,
            frameColor: String = "#000000",
            frameImage: String? = nil,
            caption: Caption? = Caption()
        ) {
            self.background = background
            self.frame = frame
            self.frameColor = frameColor
            self.frameImage = frameImage
            self.caption = caption
        }

        enum CodingKeys: String, CodingKey { case background, frame, frameColor, frameImage, caption }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            background = try c.decodeIfPresent(Background.self, forKey: .background) ?? Style.defaultBackground
            frame = try c.decodeIfPresent(Frame.self, forKey: .frame) ?? .outline
            frameColor = try c.decodeIfPresent(String.self, forKey: .frameColor) ?? "#000000"
            frameImage = try c.decodeIfPresent(String.self, forKey: .frameImage)
            // Absent → default caption; explicit `null` → no caption.
            if c.contains(.caption) {
                caption = try c.decodeNil(forKey: .caption) ? nil : try c.decode(Caption.self, forKey: .caption)
            } else {
                caption = Caption()
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(background, forKey: .background)
            try c.encode(frame, forKey: .frame)
            try c.encode(frameColor, forKey: .frameColor)
            try c.encodeIfPresent(frameImage, forKey: .frameImage)
            if let caption { try c.encode(caption, forKey: .caption) } else { try c.encodeNil(forKey: .caption) }
        }
    }

    public enum Frame: String, Codable, Sendable {
        case outline, bezel, image, none
    }

    /// JSON: `{"color": "#fff"}` or `{"gradient": ["#000", "#fff"], "angle": 135}`.
    public enum Background: Codable, Equatable, Sendable {
        case color(String)
        case gradient([String], angle: Double)

        enum CodingKeys: String, CodingKey { case color, gradient, angle }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let color = try c.decodeIfPresent(String.self, forKey: .color) {
                self = .color(color)
            } else if let stops = try c.decodeIfPresent([String].self, forKey: .gradient) {
                self = .gradient(stops, angle: try c.decodeIfPresent(Double.self, forKey: .angle) ?? 135)
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .color, in: c,
                    debugDescription: "expected \"color\" or \"gradient\""
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .color(let value):
                try c.encode(value, forKey: .color)
            case .gradient(let stops, let angle):
                try c.encode(stops, forKey: .gradient)
                try c.encode(angle, forKey: .angle)
            }
        }
    }

    public struct Caption: Codable, Equatable, Sendable {
        public var color: String
        public var position: Position
        public var font: String?

        public enum Position: String, Codable, Sendable { case top, bottom }

        public init(color: String = "#FFFFFF", position: Position = .top, font: String? = nil) {
            self.color = color
            self.position = position
            self.font = font
        }

        enum CodingKeys: String, CodingKey { case color, position, font }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#FFFFFF"
            position = try c.decodeIfPresent(Position.self, forKey: .position) ?? .top
            font = try c.decodeIfPresent(String.self, forKey: .font)
        }
    }

    public struct Shot: Codable, Equatable, Sendable {
        public var title: [String: String]?
        public var subtitle: [String: String]?

        public init(title: [String: String]? = nil, subtitle: [String: String]? = nil) {
            self.title = title
            self.subtitle = subtitle
        }
    }

    // MARK: Decoding with defaults

    enum CodingKeys: String, CodingKey {
        case version, project, workspace, targets, languages, appearances, permissions
        case style, sizeStyles, shots, macCanvas, output
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        workspace = try c.decodeIfPresent(String.self, forKey: .workspace)
        targets = try c.decode([Target].self, forKey: .targets)
        languages = try c.decode([String].self, forKey: .languages)
        appearances = try c.decodeIfPresent([Appearance].self, forKey: .appearances) ?? [.light]
        permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        style = try c.decodeIfPresent(Style.self, forKey: .style) ?? Style()
        sizeStyles = try c.decodeIfPresent([String: Style].self, forKey: .sizeStyles) ?? [:]
        shots = try c.decodeIfPresent([String: Shot].self, forKey: .shots) ?? [:]
        macCanvas = try c.decodeIfPresent(PixelSize.self, forKey: .macCanvas) ?? PixelSize(width: 2880, height: 1800)
        output = try c.decodeIfPresent(String.self, forKey: .output) ?? "screenshots"
    }

    // MARK: Loading

    public static func load(from url: URL) throws -> Config {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError.unreadable("\(url.path): \(error.localizedDescription)")
        }
        let config: Config
        do {
            config = try JSONDecoder().decode(Config.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError.invalid([ConfigIssue(error)])
        } catch {
            throw ConfigError.unreadable("\(url.path): \(error.localizedDescription)")
        }
        let found = config.issues()
        guard found.isEmpty else { throw ConfigError.invalid(found) }
        return config
    }

    public func style(forSize id: String) -> Style {
        sizeStyles[id] ?? style
    }

    // MARK: Validation

    public func issues() -> [ConfigIssue] {
        var found: [ConfigIssue] = []
        func add(_ path: String, _ message: String) { found.append(ConfigIssue(path: path, message: message)) }

        if version != 2 { add("version", "must be 2 (found \(version))") }

        switch (project, workspace) {
        case (nil, nil): add("project", "set exactly one of \"project\" or \"workspace\"")
        case (.some, .some): add("project", "\"project\" and \"workspace\" are both set; keep only one")
        default: break
        }

        if languages.isEmpty { add("languages", "list at least one language, for example [\"en-US\"]") }
        if appearances.isEmpty { add("appearances", "list at least one of \"light\", \"dark\"") }
        if targets.isEmpty { add("targets", "list at least one target") }

        for (index, target) in targets.enumerated() {
            let base = "targets[\(index)]"
            if target.tests.split(separator: "/").count != 2 || target.tests.hasPrefix("/") || target.tests.hasSuffix("/") {
                add("\(base).tests", "expected \"<UITestTarget>/<TestClass>\", found \"\(target.tests)\"")
            }
            if target.sizes.isEmpty { add("\(base).sizes", "list at least one size ID") }
            let stray = target.landscape.filter { !target.sizes.contains($0) }
            if !stray.isEmpty {
                add("\(base).landscape", "\(stray.joined(separator: ", ")) not listed in \"sizes\"")
            }
        }

        checkStyle(style, path: "style", add: add)
        for id in sizeStyles.keys.sorted() {
            checkStyle(sizeStyles[id]!, path: "sizeStyles.\(id)", add: add)
        }

        for name in shots.keys.sorted() {
            let shot = shots[name]!
            let base = "shots.\(name)"
            if !ShotProtocol.isValidShotName(name) {
                add(base, "shot names may only contain letters, digits, \"_\" and \"-\"")
            }
            checkTexts(shot.title, field: "title", base: base, add: add)
            checkTexts(shot.subtitle, field: "subtitle", base: base, add: add)
        }
        return found
    }

    private func checkStyle(_ style: Style, path: String, add: (String, String) -> Void) {
        switch style.background {
        case .color(let value):
            if RGBA(hex: value) == nil { add("\(path).background", "\"\(value)\" is not a color like #RRGGBB") }
        case .gradient(let stops, _):
            if stops.count < 2 { add("\(path).background", "a gradient needs at least two colors") }
            for value in stops where RGBA(hex: value) == nil {
                add("\(path).background", "\"\(value)\" is not a color like #RRGGBB")
            }
        }
        if RGBA(hex: style.frameColor) == nil {
            add("\(path).frameColor", "\"\(style.frameColor)\" is not a color like #RRGGBB")
        }
        if style.frame == .image, style.frameImage == nil {
            add("\(path).frameImage", "frame \"image\" needs a \"frameImage\" path")
        }
        if let caption = style.caption, RGBA(hex: caption.color) == nil {
            add("\(path).caption.color", "\"\(caption.color)\" is not a color like #RRGGBB")
        }
    }

    /// Every key must be a configured language; once a text exists, every language needs one.
    private func checkTexts(_ texts: [String: String]?, field: String, base: String, add: (String, String) -> Void) {
        guard let texts else { return }
        var explained = Set<String>()   // languages already covered by a "did you mean" message
        for key in texts.keys.sorted() where !languages.contains(key) {
            if let match = languages.first(where: { LocaleCode.split($0).language == key }) {
                add("\(base).\(field).\(key)", "\"\(key)\" is not in \"languages\"; use \"\(match)\"")
                explained.insert(match)
            } else {
                add("\(base).\(field).\(key)", "\"\(key)\" is not in \"languages\" (\(languages.joined(separator: ", ")))")
            }
        }
        for language in languages where texts[language] == nil && !explained.contains(language) {
            add("\(base).\(field).\(language)", "missing \(field) for \"\(language)\"")
        }
    }
}

public struct ConfigIssue: Equatable, Sendable, CustomStringConvertible {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }

    public var description: String { "\(path): \(message)" }

    init(_ error: DecodingError) {
        func render(_ path: [CodingKey]) -> String {
            var result = ""
            for key in path {
                if let index = key.intValue { result += "[\(index)]" } else {
                    result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
                }
            }
            return result.isEmpty ? "(root)" : result
        }
        switch error {
        case .keyNotFound(let key, let context):
            self.init(path: render(context.codingPath + [key]), message: "missing required field")
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            self.init(path: render(context.codingPath), message: context.debugDescription)
        @unknown default:
            self.init(path: "(root)", message: error.localizedDescription)
        }
    }
}

public enum ConfigError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    case invalid([ConfigIssue])

    public var description: String {
        switch self {
        case .unreadable(let message): return message
        case .invalid(let issues): return issues.map(\.description).joined(separator: "\n")
        }
    }
}

public struct RGBA: Equatable, Sendable {
    public var red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Accepts `#RGB` and `#RRGGBB`.
    public init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        var digits = Array(hex.dropFirst())
        guard digits.count == 3 || digits.count == 6 else { return nil }
        if digits.count == 3 { digits = digits.flatMap { [$0, $0] } }
        guard let value = UInt32(String(digits), radix: 16), digits.allSatisfy(\.isHexDigit) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }
}
