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

        #if os(macOS)
        let screenshot = app.windows.firstMatch.screenshot()
        #elseif os(watchOS)
        let screenshot = app.screenshot()
        #else
        guard let screen = targetScreen(file: file, line: line) else { return }
        let screenshot = screen.screenshot()
        #endif

        #if os(iOS) || os(tvOS)
        let png = Self.uprightPNG(screenshot)
        #else
        let png = screenshot.pngRepresentation
        #endif
        let attachment = XCTAttachment(uniformTypeIdentifier: "public.png",
                                       name: ShotProtocol.attachmentName(for: name),
                                       payload: png)
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

    #if os(iOS) || os(tvOS)
    /// `pngRepresentation` is the raw framebuffer. The inner display of an opened iPhone Duo is a portrait panel
    /// that shows landscape content: the `UIImage` then reports a landscape size for a portrait bitmap and carries
    /// the rotation as its orientation. Only in that case the image is redrawn upright; every other screenshot
    /// is the framebuffer as it is.
    private static func uprightPNG(_ screenshot: XCUIScreenshot) -> Data {
        let image = screenshot.image
        guard let bitmap = image.cgImage, (bitmap.width > bitmap.height) != (image.size.width > image.size.height) else {
            return screenshot.pngRepresentation
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.pngData { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }
    #endif

    #if !os(macOS) && !os(watchOS)
    /// The screen to capture: the one named by `SA2_DISPLAY` (`primary` = first screen, `primary-1` = second …).
    /// Devices with two displays (iPhone Duo) list both in `XCUIScreen.screens`.
    private func targetScreen(file: StaticString, line: UInt) -> XCUIScreen? {
        let screens = XCUIScreen.screens
        let name = ProcessInfo.processInfo.environment[ShotProtocol.Env.display] ?? "primary"
        guard let index = ShotProtocol.screenIndex(forDisplay: name) else {
            XCTFail("Unknown display \"\(name)\" in \(ShotProtocol.Env.display).", file: file, line: line)
            return nil
        }
        guard index < screens.count else {
            XCTFail("Display \"\(name)\" requested, but the device has only \(screens.count) screen(s).", file: file, line: line)
            return nil
        }
        if index > 0 {
            // A second display is dark unless the app runs on it (e.g. a closed iPhone Duo): refuse a black image.
            let screenSize = screens[index].screenshot().image.size
            let window = app.windows.firstMatch.frame.size
            let sameShape = abs(window.width - screenSize.width) < 2 && abs(window.height - screenSize.height) < 2
            guard sameShape else {
                XCTFail("The app is not running on display \"\(name)\" (window \(Int(window.width))×\(Int(window.height)) pt, "
                        + "that display \(Int(screenSize.width))×\(Int(screenSize.height)) pt). Is the device open?",
                        file: file, line: line)
                return nil
            }
        }
        return screens[index]
    }
    #endif

    // MARK: - System dialogs

    /// Language-independent: taps the last button of any system dialog.
    private func installInterruptionMonitor() {
        guard !interruptionMonitorInstalled else { return }
        interruptionMonitorInstalled = true
        addUIInterruptionMonitor(withDescription: "System dialog") { alert in
            #if os(tvOS)
            XCUIRemote.shared.press(.select)       // tvOS has no touch; the focused button is confirmed
            return true
            #else
            let buttons = alert.buttons
            guard buttons.count > 0 else { return false }
            buttons.element(boundBy: buttons.count - 1).tap()
            return true
            #endif
        }
    }
}
#endif
