//
//  ExampleAppleTVScreenshotTest.swift
//  ios-screenshot-automator / Examples
//
//  Shows how to subclass ScreenshotTestBase for an Apple TV (tvOS) app.
//  Copy this file into your tvOS UITest target, rename the class, and adapt the
//  screen list and navigation to match your own tvOS app.
//

import XCTest
import ScreenshotAutomator

// MARK: - Example: Apple TV screenshot tests

/// Concrete example showing how to use `ScreenshotTestBase` for an Apple TV app.
///
/// This example assumes a tvOS app with three top-level tabs: Home, Browse, and Settings.
///
/// ## Integration steps
/// 1. Add the `ScreenshotAutomator` package to your tvOS UITest target.
/// 2. Copy (and rename) this file into your tvOS UITest target.
/// 3. Override `captureAllScreens()` to navigate your specific tvOS app screens.
/// 4. Run the tests via `Scripts/run_screenshots.sh --devices "Apple TV 4K (3rd generation) (at 1080p)"`.
final class MyTVAppScreenshotTest: ScreenshotTestBase {

    // MARK: - Setup

    override func setUp() {
        super.setUp()

        // Override the screenshot output directory so images are saved
        // relative to your project root.
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // MyTVAppUITests/
            .deletingLastPathComponent()  // Project root

        let sanitizedDeviceName = UIDevice.current.name
            .replacingOccurrences(of: " ", with: "_")

        screenshotsURL = projectRoot
            .appendingPathComponent("screenshots")
            .appendingPathComponent(sanitizedDeviceName)

        try? FileManager.default.createDirectory(
            at: screenshotsURL,
            withIntermediateDirectories: true
        )
        print("📁 Screenshot folder: \(screenshotsURL.path)")
    }

    // MARK: - Screen capture

    override func captureAllScreens() throws {
        // 1. Home screen
        navigateToTabByIndex(0)
        sleep(1)
        try takeScreenshot(name: "01_Home")

        // 2. Browse screen
        navigateToTabByIndex(1)
        sleep(1)
        try takeScreenshot(name: "02_Browse")

        // 3. Settings screen
        navigateToTabByIndex(2)
        sleep(1)
        try takeScreenshot(name: "03_Settings")
    }
}
