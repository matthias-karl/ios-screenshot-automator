import ArgumentParser
import ScreenshotCore

@main
struct Screenshots: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshots",
        abstract: "Create App Store screenshots from XCUITest runs."
    )
}
