import Foundation
import Testing
@testable import ScreenshotCore

/// Answers questions from a script and records what was asked.
final class ScriptedPrompt: Prompting, @unchecked Sendable {
    var answers: [String]
    var choices: [Set<Int>]
    private(set) var questions: [String] = []
    private(set) var defaults: [String?] = []
    private(set) var options: [[String]] = []
    private(set) var preselections: [Set<Int>] = []

    init(answers: [String], choices: [Set<Int>]) {
        self.answers = answers
        self.choices = choices
    }

    func ask(_ question: String, default: String?) -> String {
        questions.append(question)
        defaults.append(`default`)
        return answers.isEmpty ? (`default` ?? "") : answers.removeFirst()
    }

    func choose(_ question: String, options: [String], preselected: Set<Int>) -> Set<Int> {
        questions.append(question)
        self.options.append(options)
        preselections.append(preselected)
        return choices.isEmpty ? preselected : choices.removeFirst()
    }
}

@Suite struct InitWizardTests {
    let info = ProjectInfo(container: "Demo.xcodeproj", isWorkspace: false, schemes: ["Demo", "DemoWidget"], uiTestTargets: ["DemoUITests"])

    /// Scheme, UI test target, languages, frame, color 1, color 2 (sizes come from `choices`).
    func prompt(sizes: Set<Int>? = nil) -> ScriptedPrompt {
        ScriptedPrompt(
            answers: ["Demo", "DemoUITests", "de-DE, en-US", "outline", "#1f881b", "#79b474"],
            choices: sizes.map { [$0] } ?? [])
    }

    func catalog() -> DeviceCatalog { PlannerTests.catalog(ipad13: false) }

    @Test func answersBecomeAValidConfig() {
        let result = InitWizard.run(info: info, catalog: catalog(), prompt: prompt())
        #expect(result.config.issues().isEmpty, "\(result.config.issues())")
        #expect(result.config.project == "Demo.xcodeproj" && result.config.workspace == nil)
        #expect(result.config.targets[0].tests == "DemoUITests/Screenshots")
        #expect(result.config.targets[0].scheme == "Demo")
        #expect(result.config.languages == ["de-DE", "en-US"])
        #expect(result.config.style.frame == .outline)
        #expect(result.config.style.background == .gradient(["#1f881b", "#79b474"], angle: 135))
    }

    @Test func questionsComeInTheDocumentedOrder() {
        let scripted = prompt()
        _ = InitWizard.run(info: info, catalog: catalog(), prompt: scripted)
        let keywords = ["Scheme", "UI test", "sizes", "anguages", "rame", "color", "color"]
        #expect(scripted.questions.count == keywords.count)
        for (question, keyword) in zip(scripted.questions, keywords) {
            #expect(question.contains(keyword), "\"\(question)\" should mention \(keyword)")
        }
    }

    @Test func sizesPreselectRequiredAndInstalled() throws {
        let scripted = prompt()
        _ = InitWizard.run(info: info, catalog: catalog(), prompt: scripted)
        let options = try #require(scripted.options.first)
        let selected = Set(try #require(scripted.preselections.first).map { options[$0] })
        func chosen(_ id: String) -> Bool { selected.contains { $0.contains(id) } }
        #expect(chosen("iphone-6.3") && chosen("iphone-6.9") && chosen("iphone-duo-outer"))
        #expect(chosen("ipad-13"))             // required, even though no simulator is installed
        #expect(chosen("ipad-11"))             // installed
        #expect(!options.contains { $0.contains("appletv") || $0.contains("mac") || $0.contains("watch") })
    }

    @Test func chosenSizesEndUpInTheTarget() {
        let scripted = prompt(sizes: [0, 4])
        let result = InitWizard.run(info: info, catalog: catalog(), prompt: scripted)
        #expect(result.config.targets[0].sizes == ["iphone-6.3", "ipad-13"])
    }

    @Test func invalidColorIsAskedAgain() {
        let scripted = ScriptedPrompt(
            answers: ["Demo", "DemoUITests", "en-US", "outline", "green", "#1f881b", "#79b474"], choices: [])
        let result = InitWizard.run(info: info, catalog: catalog(), prompt: scripted)
        #expect(result.config.style.background == .gradient(["#1f881b", "#79b474"], angle: 135))
    }

    @Test func testScaffoldMatchesTheConfig() {
        let result = InitWizard.run(info: info, catalog: catalog(), prompt: prompt())
        #expect(result.testFilePath == "DemoUITests/Screenshots.swift")
        #expect(result.testFileContents.contains("import ScreenshotAutomator"))
        #expect(result.testFileContents.contains("final class Screenshots: ScreenshotTestCase"))
        #expect(result.testFileContents.contains("func testScreens()"))
        #expect(result.testFileContents.contains("shot(\"01_Start\")"))
        #expect(result.config.shots.keys.contains("01_Start"))
    }

    @Test func gitignoreCoversGeneratedFolders() {
        let result = InitWizard.run(info: info, catalog: catalog(), prompt: prompt())
        #expect(result.gitignoreLines == ["screenshots/raw/", "screenshots/.work/"])
    }

    @Test func writtenJSONLoadsBackToTheSameConfig() throws {
        let result = InitWizard.run(info: info, catalog: catalog(), prompt: prompt(sizes: [0, 4]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("init-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(InitWizard.configJSON(result.config).utf8).write(to: url)
        #expect(try Config.load(from: url) == result.config)
    }

    @Test func launchArgumentSnippetListsTheFourDefaults() {
        for argument in ["-UITEST", "-LOAD_MOCK_DATA", "-DISABLE_ANIMATIONS", "-SKIP_ONBOARDING"] {
            #expect(InitWizard.launchArgumentsSnippet.contains(argument))
        }
    }

    // MARK: Preset answers (agents, scripts: no terminal)

    @Test func presetAnswersOverrideTheWizardDefaults() {
        let answers = PresetAnswers(
            scheme: "DemoWidget", uiTestTarget: "DemoUITests", sizes: ["iphone-6.3", "ipad-13"],
            languages: ["de-DE", "en-US"], frame: "bezel", gradient: ["#000000", "#FFFFFF"])
        let result = InitWizard.run(info: info, catalog: catalog(), prompt: answers)
        #expect(result.config.targets[0].scheme == "DemoWidget")
        #expect(result.config.targets[0].tests == "DemoUITests/Screenshots")
        #expect(result.config.targets[0].sizes == ["iphone-6.3", "ipad-13"])
        #expect(result.config.languages == ["de-DE", "en-US"])
        #expect(result.config.style.frame == .bezel)
        #expect(result.config.style.background == .gradient(["#000000", "#FFFFFF"], angle: 135))
        #expect(result.config.issues().isEmpty)
    }

    @Test func presetAnswersWithoutValuesTakeTheDefaults() {
        let result = InitWizard.run(info: info, catalog: catalog(), prompt: PresetAnswers())
        #expect(result.config.targets[0].scheme == "Demo")
        #expect(result.config.targets[0].tests == "DemoUITests/Screenshots")
        #expect(result.config.targets[0].sizes.contains("iphone-6.3") && result.config.targets[0].sizes.contains("ipad-13"))
        #expect(result.config.languages == ["en-US"])
        #expect(result.config.style.frame == .outline)
        #expect(result.config.issues().isEmpty)
    }

    @Test func presetAnswersCheckTheirValues() {
        #expect(PresetAnswers(sizes: ["iphone-6.7"]).problems == ["unknown size \"iphone-6.7\" (see `screenshots sizes`)"])
        #expect(PresetAnswers(sizes: ["appletv"]).problems == ["size \"appletv\" is not an iOS size; add tvOS, macOS and watchOS targets by hand"])
        #expect(PresetAnswers(frame: "round").problems == ["frame must be one of outline, bezel, image, none"])
        #expect(PresetAnswers(frame: "image").problems == ["frame image needs --frame-image <path>"])
        #expect(PresetAnswers(gradient: ["#000000"]).problems == ["--gradient needs exactly two colors"])
        #expect(PresetAnswers(gradient: ["#000000", "red"]).problems == ["\"red\" is not a color like #RRGGBB"])
        #expect(PresetAnswers(languages: []).problems.isEmpty)
        #expect(PresetAnswers().problems.isEmpty)
    }

    // MARK: ProjectInspector

    func projectDir(_ entries: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("inspect-\(UUID().uuidString)")
        for entry in entries { try FileManager.default.createDirectory(at: dir.appendingPathComponent(entry), withIntermediateDirectories: true) }
        return dir
    }

    @Test func inspectorReadsSchemesAndUITestTargets() throws {
        let dir = try projectDir(["Demo.xcodeproj"])
        let fake = FakeRunner()
        fake.stub(prefix: ["xcodebuild", "-list", "-json"], result: .ok(String(decoding: try Fixtures.data("xcodebuild-list.json"), as: UTF8.self)))
        let found = try ProjectInspector.inspect(directory: dir, shell: fake)
        #expect(found == ProjectInfo(container: "Demo.xcodeproj", isWorkspace: false, schemes: ["Demo", "DemoWidget"], uiTestTargets: ["DemoUITests"]))
        #expect(fake.calls[0] == ["xcodebuild", "-list", "-json", "-project", dir.appendingPathComponent("Demo.xcodeproj").path])
    }

    @Test func inspectorPrefersAWorkspace() throws {
        let dir = try projectDir(["Demo.xcodeproj", "Demo.xcworkspace"])
        let fake = FakeRunner()
        fake.stub(prefix: ["xcodebuild", "-list", "-json"], result: .ok(#"{"workspace":{"name":"Demo","schemes":["Demo"]}}"#))
        let found = try ProjectInspector.inspect(directory: dir, shell: fake)
        #expect(found.isWorkspace && found.container == "Demo.xcworkspace")
        #expect(found.schemes == ["Demo"])
        #expect(found.uiTestTargets.isEmpty)
    }

    @Test func inspectorFailsWithoutProject() throws {
        let dir = try projectDir([])
        #expect(throws: ProjectInspectorError.self) { try ProjectInspector.inspect(directory: dir, shell: FakeRunner()) }
    }

    @Test func inspectorReportsXcodebuildFailure() throws {
        let dir = try projectDir(["Demo.xcodeproj"])
        let fake = FakeRunner()
        fake.stub(prefix: ["xcodebuild"], result: .failure(66, stderr: "broken project"))
        #expect(throws: ProjectInspectorError.self) { try ProjectInspector.inspect(directory: dir, shell: fake) }
    }
}
