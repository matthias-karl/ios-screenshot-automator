//
//  ExampleScreenshotTest.swift
//  ios-screenshot-automator / Examples
//
//  Shows how to subclass ScreenshotTestBase for a fictional 3-tab app called "MyApp".
//  Copy this file into your UITest target, rename the class, and adapt the
//  screen list and navigation to match your own app.
//

import XCTest
import ScreenshotAutomator

// MARK: - Example: MyApp screenshot tests

/// Concrete example showing how to use `ScreenshotTestBase`.
///
/// This example assumes an app with three tabs: Home, Items, and Profile.
///
/// ## Integration steps
/// 1. Add the `ScreenshotAutomator` package to your UITest target.
/// 2. Copy (and rename) this file into your UITest target.
/// 3. Override `captureAllScreens()` to navigate your specific app screens.
/// 4. Override `tabLabels(forIndex:)` for reliable iPad navigation.
/// 5. Optionally override `setUp()` to customise the screenshot output directory.
/// 6. Run the tests via `Scripts/run_screenshots.sh --scheme MyApp`.
final class MyAppScreenshotTest: ScreenshotTestBase {

    // MARK: - Setup

    override func setUp() {
        // Always call super first – it reads the device name, creates the
        // default screenshot directory, and launches the app.
        super.setUp()

        // Override the screenshot output directory so images are saved
        // relative to your project root (not the package's Sources/ folder).
        // #file points to <ProjectRoot>/MyAppUITests/MyAppScreenshotTest.swift
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // MyAppUITests/
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

    // MARK: - iPad label hints (optional – improves Strategy 3, 4 & 5 reliability)

    /// Provide tab labels for iPad sidebar / floating-tab navigation.
    /// These must match the accessibility labels used in your TabView.
    /// Include all localised variants so navigation works in every language.
    override func tabLabels(forIndex index: Int) -> [String] {
        switch index {
        case 0: return ["Home"]
        case 1: return ["Items"]
        case 2: return ["Profile"]
        default: return []
        }
    }

    // MARK: - Screen capture

    override func captureAllScreens() throws {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        // 1. Home screen
        navigateToTabByIndex(0)
        sleep(1)
        try takeScreenshot(name: "01_Home")

        // 2. Items list
        navigateToTabByIndex(1)
        sleep(1)
        try takeScreenshot(name: "02_Items")

        // 3. Item detail – tap first data cell and capture
        tapFirstDataCell()
        sleep(1)
        try takeScreenshot(name: "03_ItemDetail")

        // On iPhone navigate back; on iPad the detail shows in split view
        if !isIPad {
            tapBackButton()
        }

        // 4. Profile
        navigateToTabByIndex(2)
        sleep(1)
        try takeScreenshot(name: "04_Profile")
    }

    // MARK: - Private helpers

    /// Tap the first *data* cell in a list, skipping any action buttons
    /// (e.g. an "Add item" row) that may sit at index 0.
    ///
    /// Adjust `dataStartIndex` if your list has a different layout.
    private func tapFirstDataCell() {
        let cells = app.cells.allElementsBoundByIndex

        // Wait for cells to appear
        let firstCell = app.cells.firstMatch
        guard firstCell.waitForExistence(timeout: 5) else {
            print("⚠️ No cells found")
            return
        }

        // Skip index 0 if it is an "Add" button; set to 0 if your list
        // starts with real data.
        let dataStartIndex = 1
        guard cells.count > dataStartIndex else {
            print("⚠️ Not enough cells – only \(cells.count) found")
            return
        }

        let targetCell = cells[dataStartIndex]
        if targetCell.exists && targetCell.isHittable {
            targetCell.tap()
            print("✅ Tapped data cell at index \(dataStartIndex): '\(targetCell.label)'")
        } else if targetCell.exists {
            // Coordinate-based fallback for non-hittable cells
            let coordinate = targetCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            coordinate.tap()
            print("✅ Tapped data cell via coordinates at index \(dataStartIndex)")
        } else {
            print("⚠️ Cell at index \(dataStartIndex) does not exist")
        }
    }

    /// Tap the navigation-bar back button (iPhone only).
    ///
    /// On iPad with split view the detail is shown inline, so calling this
    /// is usually unnecessary – guard with `if !isIPad`.
    private func tapBackButton() {
        let navBar = app.navigationBars.firstMatch
        if navBar.waitForExistence(timeout: 3) {
            let backButton = navBar.buttons.firstMatch
            if backButton.exists && backButton.isHittable {
                backButton.tap()
                Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
            }
        }
    }
}
