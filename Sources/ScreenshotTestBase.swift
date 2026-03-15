//
//  ScreenshotTestBase.swift
//  ios-screenshot-automator
//
//  Generic base class for App Store screenshot automation.
//  Subclass this in your UITest target and override `captureAllScreens()`.
//
//  Requires: Swift 5.9+ / Xcode 15+ / iOS 16+ Simulator
//

import XCTest

// MARK: - Configuration

/// Configuration for screenshot tests.
/// Based on App Store Connect screenshot requirements:
/// https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
public struct ScreenshotTestConfig {

    /// App Store screenshot devices (grouped by display size).
    /// Only the latest devices per category are listed.
    public struct AppStoreDevices {

        // MARK: - iPhone (Required: 6.9" or 6.5")

        /// 6.9" Display – iPhone 17 Pro Max (1320 × 2868 px)
        public static let iPhone6_9: String = "iPhone 17 Pro Max"

        /// 6.5" Display – Fallback if 6.9" not available (1284 × 2778 px)
        public static let iPhone6_5: String = "iPhone 14 Plus"

        /// 6.3" Display – iPhone 17 Pro (1206 × 2622 px)
        public static let iPhone6_3: String = "iPhone 17 Pro"

        /// 6.1" Display – iPhone 16e (1080 × 2340 px)
        public static let iPhone6_1: String = "iPhone 16e"

        // MARK: - iPad (Required: 13")

        /// 13" Display – iPad Pro M5 (2064 × 2752 px)
        public static let iPad13: String = "iPad Pro 13-inch (M5)"

        /// 11" Display – iPad Air M3 (1668 × 2388 px)
        public static let iPad11: String = "iPad Air 13-inch (M3)"
    }

    /// Target simulators for App Store screenshots.
    /// Minimum required: 6.9" iPhone + 13" iPad.
    public static let targetDevices: [String] = [
        AppStoreDevices.iPhone6_9,  // 6.9" – Required
        AppStoreDevices.iPhone6_3,  // 6.3" – Optional but recommended
        AppStoreDevices.iPad13,     // 13"  – Required for iPad apps
    ]

    /// iPhone-only devices (for apps without iPad support).
    public static let iPhoneOnlyDevices: [String] = [
        AppStoreDevices.iPhone6_9,
        AppStoreDevices.iPhone6_3,
    ]

    /// Initial delay after app launch (seconds) – allows system notifications to appear.
    public static let initialDelay: TimeInterval = 3.0

    /// Delay after tab/screen navigation (seconds).
    public static let navigationDelay: TimeInterval = 1.5

    /// Delay for in-app animations (seconds).
    public static let animationDelay: TimeInterval = 0.5

    /// Delay after a sheet is opened (seconds).
    public static let sheetDelay: TimeInterval = 1.0
}

// MARK: - Base Class

/// Generic base class for App Store screenshot tests.
///
/// ## Usage
/// 1. Add `ScreenshotTestBase.swift` to your UITest target.
/// 2. Create a subclass and override `captureAllScreens()`.
/// 3. Call `navigateToTabByIndex`, `takeScreenshot`, etc. from your override.
///
/// See `Examples/ExampleScreenshotTest.swift` for a complete example.
open class ScreenshotTestBase: XCTestCase {

    // MARK: - Properties

    public var app: XCUIApplication!
    public var screenshotsURL: URL = URL(fileURLWithPath: "")
    public var deviceName: String = ""

    /// Set this to a non-nil value to compose screenshots with a gradient
    /// background and device frame. When `nil` (the default), raw screenshots
    /// are saved in their original form.
    ///
    /// ```swift
    /// override func setUp() {
    ///     super.setUp()
    ///     composerConfig = ScreenshotComposerConfig(
    ///         gradientColors: [.systemBlue, .systemPurple],
    ///         deviceFrameStyle: .automatic
    ///     )
    /// }
    /// ```
    open var composerConfig: ScreenshotComposerConfig?

    // MARK: - Overridable timing constants

    /// Initial delay after app launch (seconds).
    open class var initialDelay: TimeInterval { ScreenshotTestConfig.initialDelay }

    /// Delay after tab/screen navigation (seconds).
    open class var navigationDelay: TimeInterval { ScreenshotTestConfig.navigationDelay }

    /// Delay for in-app animations (seconds).
    open class var animationDelay: TimeInterval { ScreenshotTestConfig.animationDelay }

    /// Delay after opening a sheet/modal (seconds).
    open class var sheetDelay: TimeInterval { ScreenshotTestConfig.sheetDelay }

    // MARK: - Overridable device lists

    /// Devices used when running in universal (iPhone + iPad) mode.
    open class var targetDevices: [String] { ScreenshotTestConfig.targetDevices }

    /// Devices used when running in iPhone-only mode.
    open class var iPhoneOnlyDevices: [String] { ScreenshotTestConfig.iPhoneOnlyDevices }

    // MARK: - Setup

    override open func setUp() {
        super.setUp()
        continueAfterFailure = false

        // Read device info
        deviceName = UIDevice.current.name
        let sanitizedDeviceName = deviceName.replacingOccurrences(of: " ", with: "_")

        print("📱 Test running on: \(deviceName)")
        print("📱 iOS Version: \(UIDevice.current.systemVersion)")

        // Derive project root from the location of this source file:
        //   <ProjectRoot>/…UITests/ScreenshotTestBase.swift
        // Two `.deletingLastPathComponent()` calls walk up two directory levels.
        let currentFile = URL(fileURLWithPath: #file)
        let projectURL = currentFile
            .deletingLastPathComponent() // Sources/
            .deletingLastPathComponent() // ios-screenshot-automator/ (or UITests/)

        screenshotsURL = projectURL
            .appendingPathComponent("Screenshots")
            .appendingPathComponent(sanitizedDeviceName)

        // Create folder if it doesn't exist
        do {
            try FileManager.default.createDirectory(
                at: screenshotsURL,
                withIntermediateDirectories: true
            )
            print("📁 Screenshot folder: \(screenshotsURL.path)")
        } catch {
            print("❌ Error creating folder: \(error)")
        }

        // Launch app with test configuration
        app = XCUIApplication()
        app.launchArguments = [
            "-UITEST",
            "-LOAD_MOCK_DATA",
            "-DISABLE_ANIMATIONS",
            "-SKIP_ONBOARDING"
        ]
        app.launch()
    }

    // MARK: - Main Test Entry Point

    /// XCTest entry point – calls `captureAllScreens()`.
    /// Do not override this method; override `captureAllScreens()` instead.
    public func testTakeAllScreenshots() throws {
        print("🚀 Starting screenshot capture for \(deviceName)")

        // Allow system notifications (permissions dialogs, etc.) to appear and settle
        print("⏳ Waiting for system notifications...")
        Thread.sleep(forTimeInterval: type(of: self).initialDelay)

        dismissSystemAlerts()

        try captureAllScreens()

        print("✅ All screenshots created for \(deviceName)")
    }

    // MARK: - Subclass Hook

    /// Override this method to navigate through your app and capture screenshots.
    ///
    /// Use the helper methods provided by this base class:
    /// `navigateToTabByIndex`, `takeScreenshot`, `tapFirstHittableCell`,
    /// `tapPlusButton`, `dismissSheet`, `ensureMainViewVisible`, etc.
    ///
    /// - Throws: Any error thrown by `takeScreenshot`.
    open func captureAllScreens() throws {
        fatalError(
            """
            ScreenshotTestBase.captureAllScreens() must be overridden by a subclass.
            Create a subclass of ScreenshotTestBase in your UITest target and override
            this method to navigate through your app and call takeScreenshot(name:).
            See Examples/ExampleScreenshotTest.swift for a complete example.
            """
        )
    }

    // MARK: - Screenshot Helper

    /// Save a screenshot to disk and attach it to the Xcode test results.
    /// - Parameter name: File-name suffix (e.g. "01_Home"). The final filename will be
    ///   `<DeviceName>_<name>.png`.
    /// - Parameter composerOverride: Optional per-screenshot overrides for the composer
    ///   configuration (e.g. different gradient colors for a specific screen).
    open func takeScreenshot(name: String, composerOverride: ScreenshotComposerOverride? = nil) throws {
        Thread.sleep(forTimeInterval: type(of: self).animationDelay)

        let screenshot = app.screenshot()
        let sanitizedDeviceName = deviceName.replacingOccurrences(of: " ", with: "_")
        let fileName = "\(sanitizedDeviceName)_\(name).png"
        let screenshotURL = screenshotsURL.appendingPathComponent(fileName)

        var imageData = screenshot.pngRepresentation

        // Compose the screenshot if a composer configuration is set
        if let config = composerConfig {
            imageData = ScreenshotComposer.compose(
                screenshotData: imageData,
                config: config,
                override: composerOverride
            )
        }

        try imageData.write(to: screenshotURL)

        print("📸 Screenshot saved: \(screenshotURL.path)")

        // Attach to Xcode Test Results for easy viewing in Xcode / CI
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(deviceName)_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Navigation Helpers

    /// Navigate to a tab by its index (language-independent).
    ///
    /// Automatically selects the correct strategy for iPhone vs iPad.
    /// - Parameter index: Zero-based tab index (0 = first tab, 1 = second tab, …).
    open func navigateToTabByIndex(_ index: Int) {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        if isIPad {
            print("📱 iPad detected – using iPad navigation strategy")
            navigateToTabOnIPad(index)
        } else {
            print("📱 iPhone detected – using standard tab bar navigation")
            navigateToTabOnIPhone(index)
        }
    }

    /// Standard iPhone tab bar navigation.
    open func navigateToTabOnIPhone(_ index: Int) {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 5) else {
            print("⚠️ TabBar not found")
            return
        }

        let tabButtons = tabBar.buttons
        guard tabButtons.count > index else {
            print("⚠️ Tab index \(index) not available (only \(tabButtons.count) tabs)")
            return
        }

        let targetTab = tabButtons.element(boundBy: index)
        if targetTab.exists && targetTab.isHittable {
            targetTab.tap()
            Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
            print("✅ Navigated to tab \(index)")
        } else {
            print("⚠️ Tab \(index) does not exist or is not hittable")
        }
    }

    /// iPad-specific navigation. Tries multiple strategies in order:
    ///
    /// 1. Standard tab bar (by index, then by label, then coordinate fallback)
    /// 2. `TabSection` container (iPadOS 18+ floating tab bar)
    /// 3. Direct button search by label anywhere in the app
    /// 4. Sidebar toggle + label search via `tabLabels(forIndex:)`
    /// 5. Broad button scan using partial label matching
    /// 6. Last-resort coordinate-based tap on the tab bar element
    open func navigateToTabOnIPad(_ index: Int) {
        let labels = tabLabels(forIndex: index)

        print("📊 iPad: Debugging UI elements...")
        print("   Tab bars count: \(app.tabBars.count)")
        print("   Navigation bars count: \(app.navigationBars.count)")
        print("   Tables count: \(app.tables.count)")
        print("   Collection views count: \(app.collectionViews.count)")
        print("   Buttons count: \(app.buttons.allElementsBoundByIndex.count)")

        // Ensure we're not in edit mode from a previous navigation
        exitEditModeIfNeeded()

        // Strategy 1: Standard tab bar (might be at bottom or floating)
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 3) {
            print("📊 iPad: Tab bar found, isHittable: \(tabBar.isHittable)")
            let tabButtons = tabBar.buttons
            print("📊 iPad: Tab bar has \(tabButtons.count) buttons")

            // 1a: Try by index
            if tabButtons.count > index {
                let targetTab = tabButtons.element(boundBy: index)
                print("📊 iPad: Target tab \(index) – exists: \(targetTab.exists), hittable: \(targetTab.isHittable), label: '\(targetTab.label)'")

                if targetTab.exists && targetTab.isHittable {
                    targetTab.tap()
                    Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                    exitEditModeIfNeeded()
                    print("✅ iPad: Navigated via tab bar to tab \(index)")
                    return
                } else if targetTab.exists {
                    // Coordinate-based tap for non-hittable elements
                    let coordinate = targetTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    coordinate.tap()
                    Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                    exitEditModeIfNeeded()
                    print("✅ iPad: Navigated via coordinate tap to tab \(index)")
                    return
                }
            }

            // 1b: Try by label within tab bar (handles localized labels)
            for label in labels {
                let tabButton = tabBar.buttons[label]
                if tabButton.exists && tabButton.isHittable {
                    tabButton.tap()
                    Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                    exitEditModeIfNeeded()
                    print("✅ iPad: Navigated via tab bar label '\(label)'")
                    return
                }
            }
        }

        // Strategy 2: TabSection (iPadOS 18+ floating tab bar)
        let tabSections = app.otherElements.matching(identifier: "TabSection")
        if tabSections.count > 0 {
            let tabSection = tabSections.firstMatch
            let buttons = tabSection.buttons
            if buttons.count > index {
                let targetButton = buttons.element(boundBy: index)
                if targetButton.exists {
                    targetButton.tap()
                    Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                    exitEditModeIfNeeded()
                    print("✅ iPad: Navigated via TabSection to tab \(index)")
                    return
                }
            }
        }

        // Strategy 3: Direct button search anywhere in the app (before sidebar toggle)
        for label in labels {
            let button = app.buttons[label]
            if button.exists && button.isHittable {
                button.tap()
                Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                exitEditModeIfNeeded()
                print("✅ iPad: Navigated via button '\(label)'")
                return
            }
        }

        // Strategy 4: Sidebar toggle, then label-based navigation
        let sidebarButton = app.buttons["ToggleSidebar"]
        if sidebarButton.exists && sidebarButton.isHittable {
            sidebarButton.tap()
            Thread.sleep(forTimeInterval: type(of: self).animationDelay)

            for label in labels {
                // Try static text (sidebar row) – use coordinate tap to avoid long press
                let staticText = app.staticTexts[label]
                if staticText.exists && staticText.isHittable {
                    let coordinate = staticText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    coordinate.tap()
                    Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                    exitEditModeIfNeeded()
                    print("✅ iPad: Navigated via sidebar text '\(label)'")
                    return
                }

                // Try button after sidebar toggle
                let button = app.buttons[label]
                if button.exists && button.isHittable {
                    button.tap()
                    Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                    exitEditModeIfNeeded()
                    print("✅ iPad: Navigated via sidebar button '\(label)'")
                    return
                }
            }
        }

        // Strategy 5: Broad button scan – search all buttons for partial label match
        let allKnownLabels: [String] = labels.isEmpty
            ? (0..<10).flatMap { tabLabels(forIndex: $0) }
            : labels
        guard !allKnownLabels.isEmpty else {
            print("⚠️ iPad: tabLabels(forIndex:) returned no labels. Override it in your subclass.")
            navigateToTabOnIPadFallback(index: index, tabBar: tabBar)
            return
        }

        let allButtons = app.buttons.allElementsBoundByIndex
        print("📊 iPad: Scanning \(allButtons.count) buttons for tab label matches...")

        for button in allButtons {
            if button.exists && button.isHittable {
                let btnLabel = button.label.lowercased()
                let btnID    = button.identifier.lowercased()
                let matchesAny = allKnownLabels.contains { known in
                    let k = known.lowercased()
                    return btnLabel.contains(k) || btnID.contains(k)
                }
                if matchesAny {
                    print("📊 iPad: Found matching button: '\(button.label)' (id: '\(button.identifier)')")
                    button.tap()
                    Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                    exitEditModeIfNeeded()
                    print("✅ iPad: Navigated via scanned button '\(button.label)'")
                    return
                }
            }
        }

        // Strategy 6: Last resort – coordinate tap on the tab bar
        navigateToTabOnIPadFallback(index: index, tabBar: tabBar)
    }

    /// Returns the possible accessibility labels for the tab at `index`.
    ///
    /// Override in your subclass to enable label-based iPad navigation (strategies 3, 4 & 5).
    ///
    /// Example:
    /// ```swift
    /// override func tabLabels(forIndex index: Int) -> [String] {
    ///     switch index {
    ///     case 0: return ["Home"]
    ///     case 1: return ["Items"]
    ///     case 2: return ["Profile"]
    ///     default: return []
    ///     }
    /// }
    /// ```
    open func tabLabels(forIndex index: Int) -> [String] {
        return []
    }

    /// Navigate to a tab by providing an array of possible accessibility labels.
    /// Tries buttons, then static texts, then coordinate-based taps.
    /// - Parameter labels: Possible labels for the desired tab.
    @discardableResult
    open func navigateToTabByLabel(_ labels: [String]) -> Bool {
        for label in labels {
            let button = app.buttons[label]
            if button.exists && button.isHittable {
                button.tap()
                Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                exitEditModeIfNeeded()
                print("✅ Navigated via label '\(label)'")
                return true
            }

            let staticText = app.staticTexts[label]
            if staticText.exists && staticText.isHittable {
                let coordinate = staticText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                coordinate.tap()
                Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                exitEditModeIfNeeded()
                print("✅ Navigated via static text label '\(label)'")
                return true
            }
        }
        print("⚠️ Could not navigate to tab with labels: \(labels)")
        return false
    }

    // MARK: - Interaction Helpers

    /// Tap the "+" / add button in the navigation bar.
    /// - Returns: `true` if the button was found and tapped.
    @discardableResult
    open func tapPlusButton() -> Bool {
        // Exit edit mode first to avoid accidental list-reordering
        exitEditModeIfNeeded()

        let navBar = app.navigationBars.firstMatch
        if navBar.waitForExistence(timeout: 3) {
            // SF Symbol "plus"
            let plusButton = navBar.buttons["plus"]
            if plusButton.exists && plusButton.isHittable {
                let coordinate = plusButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                coordinate.tap()
                Thread.sleep(forTimeInterval: type(of: self).sheetDelay)
                return true
            }

            // "Add" label
            let addButton = navBar.buttons["Add"]
            if addButton.exists && addButton.isHittable {
                let coordinate = addButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                coordinate.tap()
                Thread.sleep(forTimeInterval: type(of: self).sheetDelay)
                return true
            }

            // Scan all nav bar buttons for add/plus semantics
            let buttons = navBar.buttons.allElementsBoundByIndex
            for button in buttons {
                let label = button.label.lowercased()
                let identifier = button.identifier.lowercased()
                if label.contains("add") || label.contains("plus") ||
                   label.contains("hinzufügen") || label.contains("neu") ||
                   identifier.contains("add") || identifier.contains("plus") {
                    if button.exists && button.isHittable {
                        let coordinate = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                        coordinate.tap()
                        Thread.sleep(forTimeInterval: type(of: self).sheetDelay)
                        return true
                    }
                }
            }
        }

        // Fallback: search anywhere in the app
        let plusButton = app.buttons["plus"]
        if plusButton.waitForExistence(timeout: 3) && plusButton.isHittable {
            let coordinate = plusButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            coordinate.tap()
            Thread.sleep(forTimeInterval: type(of: self).sheetDelay)
            return true
        }

        print("⚠️ Plus button not found")
        return false
    }

    /// Dismiss the currently visible sheet or modal.
    ///
    /// Tries four strategies in order:
    /// 1. xmark / close / cancel button in the navigation bar
    /// 2. Cancel / Close / Done buttons anywhere in the view
    /// 3. Aggressive swipe-down gesture
    /// 4. Tap on the dimmed area outside the sheet
    open func dismissSheet() {
        print("🔄 Attempting to dismiss sheet...")

        // Strategy 1: Navigation bar close/cancel button
        let navBar = app.navigationBars.firstMatch
        if navBar.exists {
            let xmarkButton = navBar.buttons["xmark"]
            if xmarkButton.exists && xmarkButton.isHittable {
                print("✅ Found xmark button")
                xmarkButton.tap()
                Thread.sleep(forTimeInterval: type(of: self).animationDelay * 2)
                return
            }

            let buttons = navBar.buttons.allElementsBoundByIndex
            for button in buttons {
                if button.exists && button.isHittable {
                    let label = button.label.lowercased()
                    let identifier = button.identifier.lowercased()
                    if label.contains("close") || label.contains("cancel") ||
                       label.contains("abbrechen") || label.contains("schließen") ||
                       label == "x" || identifier.contains("close") || identifier.contains("xmark") {
                        print("✅ Found close button: \(button.label)")
                        button.tap()
                        Thread.sleep(forTimeInterval: type(of: self).animationDelay * 2)
                        return
                    }
                }
            }

            // Try the first button in the nav bar (often the close button for modals)
            if buttons.count > 0 {
                let firstButton = buttons[0]
                if firstButton.exists && firstButton.isHittable {
                    print("✅ Tapping first nav bar button: \(firstButton.label)")
                    firstButton.tap()
                    Thread.sleep(forTimeInterval: type(of: self).animationDelay * 2)
                    return
                }
            }
        }

        // Strategy 2: Cancel/Close/Done buttons anywhere
        let cancelButtonNames = ["Cancel", "Abbrechen", "Close", "Schließen", "Done", "Fertig", "Dismiss"]
        for buttonName in cancelButtonNames {
            let button = app.buttons[buttonName]
            if button.exists && button.isHittable {
                print("✅ Found button: \(buttonName)")
                button.tap()
                Thread.sleep(forTimeInterval: type(of: self).animationDelay * 2)
                return
            }
        }

        // Strategy 3: Aggressive swipe-down to close sheet
        print("⚠️ No close button found – trying swipe down...")
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end   = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
        start.press(forDuration: 0.2, thenDragTo: end)
        Thread.sleep(forTimeInterval: type(of: self).animationDelay * 2)

        // Strategy 4: Tap outside the sheet (on the dimmed background)
        if !app.tabBars.firstMatch.isHittable {
            print("⚠️ Still in modal – trying tap outside...")
            let outsideTap = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
            outsideTap.tap()
            Thread.sleep(forTimeInterval: type(of: self).animationDelay * 2)
        }
    }

    /// Ensure the main tab view is visible (no sheets or modals open).
    open func ensureMainViewVisible() {
        let tabBar = app.tabBars.firstMatch
        var attempts = 0

        while !tabBar.isHittable && attempts < 3 {
            print("⚠️ Tab bar not hittable – attempting to dismiss modal (attempt \(attempts + 1))")
            dismissSheet()
            attempts += 1
        }

        if tabBar.isHittable {
            print("✅ Main view visible")
        } else {
            print("⚠️ Could not return to main view after \(attempts) attempts")
        }
    }

    /// Exit list edit mode if it is currently active.
    open func exitEditModeIfNeeded() {
        let doneButtons = ["Done", "Fertig"]

        for buttonName in doneButtons {
            let button = app.navigationBars.buttons[buttonName]
            if button.exists && button.isHittable {
                print("⚠️ List is in edit mode – tapping '\(buttonName)' to exit")
                button.tap()
                Thread.sleep(forTimeInterval: type(of: self).animationDelay)
                return
            }
        }

        // Also check for delete/remove buttons visible in the list (sign of edit mode)
        let deleteButton = app.buttons["Remove"]
        if deleteButton.exists {
            print("⚠️ Edit mode detected via Remove button – looking for Done button...")
            let allButtons = app.buttons.allElementsBoundByIndex
            for button in allButtons {
                let label = button.label.lowercased()
                if (label == "done" || label == "fertig") && button.isHittable {
                    button.tap()
                    Thread.sleep(forTimeInterval: type(of: self).animationDelay)
                    return
                }
            }
        }
    }

    /// Find and tap the first hittable cell in the current list view.
    /// - Returns: `true` if a cell was found and tapped.
    @discardableResult
    open func tapFirstHittableCell() -> Bool {
        exitEditModeIfNeeded()

        let cells = app.cells.allElementsBoundByIndex

        for cell in cells {
            if cell.exists && cell.isHittable {
                cell.tap()
                Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                return true
            }
        }

        // Fallback: wait for the first cell and tap it
        let firstCell = app.cells.firstMatch
        if firstCell.waitForExistence(timeout: 3) {
            if waitForHittable(firstCell, timeout: 3) {
                firstCell.tap()
                Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                return true
            }
        }

        return false
    }

    /// Wait for a UI element to become hittable.
    /// - Parameters:
    ///   - element: The element to wait for.
    ///   - timeout: Maximum wait time in seconds.
    /// - Returns: `true` if the element became hittable within `timeout`.
    @discardableResult
    open func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Dismiss any pending system alert dialogs (e.g. permission prompts).
    open func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 1) {
            allowButton.tap()
        }

        let okButton = springboard.buttons["OK"]
        if okButton.waitForExistence(timeout: 1) {
            okButton.tap()
        }
    }

    // MARK: - Private Helpers

    /// Last-resort iPad navigation: force a coordinate-based tap on the tab bar.
    private func navigateToTabOnIPadFallback(index: Int, tabBar: XCUIElement) {
        if tabBar.exists {
            let tabButtons = tabBar.buttons.allElementsBoundByIndex
            print("📊 iPad: Final attempt – Found \(tabButtons.count) tab bar buttons")
            for (i, button) in tabButtons.enumerated() {
                print("   Tab \(i): '\(button.label)' – exists: \(button.exists), hittable: \(button.isHittable)")
            }

            if tabButtons.count > index {
                let targetTab = tabButtons[index]
                if targetTab.exists {
                    let coordinate = targetTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    coordinate.tap()
                    Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                    exitEditModeIfNeeded()
                    print("✅ iPad: Force-navigated via coordinates to tab \(index)")
                    return
                }
            }
        }

        print("⚠️ iPad: Could not navigate to tab \(index)")
    }
}
