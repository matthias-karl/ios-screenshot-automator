import Foundation

public protocol Prompting {
    /// Free text; an empty answer means `default`.
    func ask(_ question: String, default: String?) -> String
    /// Multiple choice; returns the selected option indices.
    func choose(_ question: String, options: [String], preselected: Set<Int>) -> Set<Int>
}

public struct InitResult: Equatable {
    public var config: Config
    public var testFilePath: String
    public var testFileContents: String
    public var gitignoreLines: [String]
}

/// Turns a few answers into `screenshots.json` and a UI-test scaffold.
public enum InitWizard {
    /// The questions in the order they are asked. `PresetAnswers` matches on these.
    public enum Question {
        public static let scheme = "Scheme"
        public static let uiTestTarget = "UI test target"
        public static let sizes = "Which sizes do you want?"
        public static let languages = "Languages (App Store codes, comma separated)"
        public static let frame = "Frame style (outline, bezel, image, none)"
        public static let frameImage = "Frame image (PNG with transparent screen), path relative to screenshots.json"
        public static let gradientStart = "Gradient start color (#RRGGBB)"
        public static let gradientEnd = "Gradient end color (#RRGGBB)"
    }

    public static let launchArgumentsSnippet = """
    // In your app, react to these launch arguments (set by ScreenshotTestCase):
    //   -UITEST              use mock data, no network, no real accounts
    //   -LOAD_MOCK_DATA      load deterministic sample content
    //   -DISABLE_ANIMATIONS  turn animations off
    //   -SKIP_ONBOARDING     skip welcome screens and permission prompts
    //
    // let arguments = CommandLine.arguments
    // let isUITest = arguments.contains("-UITEST")
    """

    public static func run(info: ProjectInfo, catalog: DeviceCatalog, prompt: Prompting) -> InitResult {
        // 1. Scheme and UI test target.
        let schemeQuestion = info.schemes.isEmpty ? Question.scheme : "\(Question.scheme) (\(info.schemes.joined(separator: ", ")))"
        let scheme = nonEmpty(prompt.ask(schemeQuestion, default: info.schemes.first)) ?? info.schemes.first ?? "App"
        let uiDefault = info.uiTestTargets.first ?? "\(scheme)UITests"
        let uiTarget = nonEmpty(prompt.ask(Question.uiTestTarget, default: uiDefault)) ?? uiDefault

        // 2. Sizes: required ones plus every size with an installed simulator (iOS sizes; other platforms are separate targets).
        let sizes = StoreSizes.all.filter { $0.platform == .iOS }
        let options = sizes.map { "\($0.id) — \($0.label)\($0.requiredWithinFamily ? " (required)" : "")" }
        var preselected = Set<Int>()
        for (index, size) in sizes.enumerated() where size.requiredWithinFamily || ((try? Planner.pick(size: size, catalog: catalog)) ?? nil) != nil {
            preselected.insert(index)
        }
        let chosen = prompt.choose(Question.sizes, options: options, preselected: preselected)
        let chosenSizes = chosen.sorted().filter { sizes.indices.contains($0) }.map { sizes[$0].id }

        // 3. Languages, frame, colors.
        let languageAnswer = prompt.ask(Question.languages, default: "en-US")
        var languages = languageAnswer.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if languages.isEmpty { languages = ["en-US"] }

        var frame = Config.Frame.outline
        for _ in 0..<3 {
            let answer = prompt.ask(Question.frame, default: "outline").trimmingCharacters(in: .whitespaces)
            if let parsed = Config.Frame(rawValue: answer.isEmpty ? "outline" : answer) { frame = parsed; break }
        }
        var frameImage: String?
        if frame == .image { frameImage = nonEmpty(prompt.ask(Question.frameImage, default: nil)) }

        let start = askColor(Question.gradientStart, default: "#2B2B2F", prompt: prompt)
        let end = askColor(Question.gradientEnd, default: "#5A5A63", prompt: prompt)

        // 4. Result.
        let config = Config(
            project: info.isWorkspace ? nil : info.container,
            workspace: info.isWorkspace ? info.container : nil,
            targets: [Config.Target(platform: .iOS, scheme: scheme, tests: "\(uiTarget)/Screenshots", sizes: chosenSizes)],
            languages: languages,
            style: Config.Style(background: .gradient([start, end], angle: 135), frame: frame, frameImage: frameImage),
            shots: ["01_Start": Config.Shot(title: Dictionary(uniqueKeysWithValues: languages.map { ($0, "Your headline") }))])

        let testFile = """
        import XCTest
        import ScreenshotAutomator

        final class Screenshots: ScreenshotTestCase {

            func testScreens() {
                launch()
                shot("01_Start")
                // tap(id: "button.add")      // elements with an accessibilityIdentifier
                // shot("02_Next")
            }
        }

        """
        return InitResult(
            config: config, testFilePath: "\(uiTarget)/Screenshots.swift", testFileContents: testFile,
            gitignoreLines: ["\(config.output)/raw/", "\(config.output)/.work/"])
    }

    // MARK: JSON

    /// `screenshots.json` as written by `init` (compact, in the order of the documentation).
    /// Renders configurations the wizard produces: one target, color or gradient background.
    public static func configJSON(_ config: Config) -> String {
        func q(_ value: String) -> String {
            String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data(), as: UTF8.self)
        }
        func list(_ values: [String]) -> String { "[" + values.map(q).joined(separator: ", ") + "]" }

        var lines: [String] = ["{", "  \"version\": \(config.version),"]
        if let project = config.project { lines.append("  \"project\": \(q(project)),") }
        if let workspace = config.workspace { lines.append("  \"workspace\": \(q(workspace)),") }

        lines.append("  \"targets\": [")
        for (index, target) in config.targets.enumerated() {
            lines.append("    {")
            lines.append("      \"platform\": \(q(target.platform.rawValue)),")
            lines.append("      \"scheme\": \(q(target.scheme)),")
            lines.append("      \"tests\": \(q(target.tests)),")
            if !target.landscape.isEmpty { lines.append("      \"sizes\": \(list(target.sizes)),"); lines.append("      \"landscape\": \(list(target.landscape))") }
            else { lines.append("      \"sizes\": \(list(target.sizes))") }
            lines.append("    }\(index < config.targets.count - 1 ? "," : "")")
        }
        lines.append("  ],")
        lines.append("  \"languages\": \(list(config.languages)),")
        lines.append("  \"appearances\": \(list(config.appearances.map(\.rawValue))),")
        if !config.permissions.isEmpty { lines.append("  \"permissions\": \(list(config.permissions)),") }

        lines.append("  \"style\": {")
        switch config.style.background {
        case .color(let color): lines.append("    \"background\": { \"color\": \(q(color)) },")
        case .gradient(let stops, let angle): lines.append("    \"background\": { \"gradient\": \(list(stops)), \"angle\": \(Int(angle)) },")
        }
        lines.append("    \"frame\": \(q(config.style.frame.rawValue))\(config.style.frameImage != nil || config.style.caption != nil ? "," : "")")
        if let image = config.style.frameImage { lines.append("    \"frameImage\": \(q(image))\(config.style.caption != nil ? "," : "")") }
        if let caption = config.style.caption {
            lines.append("    \"caption\": { \"color\": \(q(caption.color)), \"position\": \(q(caption.position.rawValue)) }")
        }
        lines.append("  },")

        lines.append("  \"shots\": {")
        let names = config.shots.keys.sorted()
        for (index, name) in names.enumerated() {
            var parts: [String] = []
            if let title = config.shots[name]?.title { parts.append("\"title\": " + dictionary(title, languages: config.languages, q: q)) }
            if let subtitle = config.shots[name]?.subtitle { parts.append("\"subtitle\": " + dictionary(subtitle, languages: config.languages, q: q)) }
            lines.append("    \(q(name)): { \(parts.joined(separator: ", ")) }\(index < names.count - 1 ? "," : "")")
        }
        lines.append("  },")
        lines.append("  \"output\": \(q(config.output))")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func dictionary(_ values: [String: String], languages: [String], q: (String) -> String) -> String {
        "{ " + languages.compactMap { language in values[language].map { "\(q(language)): \(q($0))" } }.joined(separator: ", ") + " }"
    }

    // MARK: Helpers

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Asks up to three times for a valid `#RRGGBB`, then takes the default.
    private static func askColor(_ question: String, default fallback: String, prompt: Prompting) -> String {
        for _ in 0..<3 {
            let answer = prompt.ask(question, default: fallback).trimmingCharacters(in: .whitespaces)
            if RGBA(hex: answer) != nil { return answer }
        }
        return fallback
    }
}

/// Answers for `InitWizard` without a terminal (coding agents, scripts, CI).
/// Every value that is given wins; everything else takes the wizard's default.
public struct PresetAnswers: Prompting {
    public var scheme: String?
    public var uiTestTarget: String?
    public var sizes: [String]?
    public var languages: [String]?
    public var frame: String?
    public var frameImage: String?
    public var gradient: [String]?

    public init(
        scheme: String? = nil, uiTestTarget: String? = nil, sizes: [String]? = nil, languages: [String]? = nil,
        frame: String? = nil, frameImage: String? = nil, gradient: [String]? = nil
    ) {
        self.scheme = scheme
        self.uiTestTarget = uiTestTarget
        self.sizes = sizes
        self.languages = languages
        self.frame = frame
        self.frameImage = frameImage
        self.gradient = gradient
    }

    /// Values that cannot be used; empty when everything is fine. Check before running the wizard.
    public var problems: [String] {
        var found: [String] = []
        for id in sizes ?? [] {
            guard let size = StoreSizes.size(id: id) else {
                found.append("unknown size \"\(id)\" (see `screenshots sizes`)")
                continue
            }
            if size.platform != .iOS {
                found.append("size \"\(id)\" is not an iOS size; add tvOS, macOS and watchOS targets by hand")
            }
        }
        if let frame {
            if Config.Frame(rawValue: frame) == nil {
                found.append("frame must be one of outline, bezel, image, none")
            } else if frame == "image", (frameImage ?? "").isEmpty {
                found.append("frame image needs --frame-image <path>")
            }
        }
        if let gradient {
            if gradient.count != 2 {
                found.append("--gradient needs exactly two colors")
            } else {
                for color in gradient where RGBA(hex: color) == nil { found.append("\"\(color)\" is not a color like #RRGGBB") }
            }
        }
        return found
    }

    public func ask(_ question: String, default fallback: String?) -> String {
        let answer: String?
        switch question {
        case let q where q.hasPrefix(InitWizard.Question.scheme): answer = scheme
        case InitWizard.Question.uiTestTarget: answer = uiTestTarget
        case InitWizard.Question.languages: answer = (languages?.isEmpty ?? true) ? nil : languages!.joined(separator: ", ")
        case InitWizard.Question.frame: answer = frame
        case InitWizard.Question.frameImage: answer = frameImage
        case InitWizard.Question.gradientStart: answer = gradient?.first
        case InitWizard.Question.gradientEnd: answer = gradient?.dropFirst().first
        default: answer = nil
        }
        return answer ?? fallback ?? ""
    }

    public func choose(_ question: String, options: [String], preselected: Set<Int>) -> Set<Int> {
        guard question == InitWizard.Question.sizes, let sizes, !sizes.isEmpty else { return preselected }
        // Options read "<size id> — <label>".
        return Set(options.indices.filter { index in
            sizes.contains { options[index].hasPrefix("\($0) —") }
        })
    }
}
