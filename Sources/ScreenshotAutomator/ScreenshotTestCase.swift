#if canImport(XCTest)
import XCTest
import ScreenshotProtocol

/// Base class for screenshot UI tests.
///
/// It only launches the app and attaches screenshots to the test result
/// (`shot(_:)` writes nothing to disk). The `screenshots` tool picks the attachments
/// up, composes the final images and validates them.
open class ScreenshotTestCase: XCTestCase {
    public private(set) var app: XCUIApplication!

    /// Launch arguments every run starts with. `launch(extraArguments:)` appends to these.
    open class var launchArguments: [String] {
        ["-UITEST", "-LOAD_MOCK_DATA", "-DISABLE_ANIMATIONS", "-SKIP_ONBOARDING"]
    }

    /// Seconds to wait before each screenshot so transitions can settle.
    open class var settleDelay: TimeInterval { 0.5 }

    private var interruptionMonitorInstalled = false

    open override func setUp() {
        super.setUp()
        // One failing test must not stop the remaining shots of the same test method.
        continueAfterFailure = true
    }

    /// Launches the app with the standard arguments plus `extraArguments`.
    public func launch(extraArguments: [String] = [], environment: [String: String] = [:]) {
        let app = XCUIApplication()
        app.launchArguments = Self.launchArguments + extraArguments
        app.launchEnvironment.merge(environment) { _, new in new }

        let env = ProcessInfo.processInfo.environment
        #if os(iOS)
        if env[ShotProtocol.Env.landscape] == "1" {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        #endif
        #if os(macOS)
        if env[ShotProtocol.Env.appearance] == "dark" {
            app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
        }
        #endif

        installInterruptionMonitor()
        app.launch()
        self.app = app
    }

    /// Takes a screenshot and attaches it as `sa2v2__<name>`.
    /// Names may only contain letters, digits, `_` and `-`.
    public func shot(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        guard ShotProtocol.isValidShotName(name) else {
            XCTFail("Invalid shot name \"\(name)\": use only letters, digits, \"_\" and \"-\".", file: file, line: line)
            return
        }
        guard let app else {
            XCTFail("shot(\"\(name)\") called before launch().", file: file, line: line)
            return
        }
        Thread.sleep(forTimeInterval: Self.settleDelay)

        #if os(macOS) || os(watchOS)
        let screenshot: XCUIScreenshot
        #if os(macOS)
        screenshot = app.windows.firstMatch.screenshot()
        #else
        screenshot = app.screenshot()
        #endif
        #else
        let screenshot = XCUIScreen.main.screenshot()
        #endif

        let attachment = XCTAttachment(uniformTypeIdentifier: "public.png",
                                       name: ShotProtocol.attachmentName(for: name),
                                       payload: screenshot.pngRepresentation)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Taps the element with the given `accessibilityIdentifier`.
    public func tap(id: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        #if os(tvOS)
        XCTFail("tap(id: \"\(id)\") is not available on tvOS; navigate with XCUIRemote.shared.press(...).",
                file: file, line: line)
        #else
        guard let app else {
            XCTFail("tap(id: \"\(id)\") called before launch().", file: file, line: line)
            return
        }
        let element = app.descendants(matching: .any)[id]
        guard waitFor(element, timeout: timeout) else {
            XCTFail("No element with accessibilityIdentifier \"\(id)\" appeared within \(timeout) s.", file: file, line: line)
            return
        }
        element.tap()
        #endif
    }

    @discardableResult
    public func waitFor(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    // MARK: - System dialogs

    /// Language-independent: taps the last button of any system dialog.
    private func installInterruptionMonitor() {
        guard !interruptionMonitorInstalled else { return }
        interruptionMonitorInstalled = true
        addUIInterruptionMonitor(withDescription: "System dialog") { alert in
            let buttons = alert.buttons
            guard buttons.count > 0 else { return false }
            buttons.element(boundBy: buttons.count - 1).tap()
            return true
        }
    }
}
#endif
