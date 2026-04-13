# ios-screenshot-automator

A self-contained, drop-in toolkit for automating App Store screenshot capture across multiple iOS and tvOS simulators. Add the Swift package, subclass one class, copy the template script, and run — pixel-perfect screenshots for every device size required by App Store Connect, including Apple TV.

<p align="center">
  <img src="Icon/icon.png" alt="ios-screenshot-automator icon" width="128">
</p>

> **New here?** Jump straight to the [Quick Start Guide](Docs/QuickStart.md) — zero to screenshots in 5 minutes.

---

## Table of Contents

1. [What it is](#what-it-is)
2. [Features](#features)
3. [Requirements](#requirements)
4. [Installation](#installation)
5. [Quick Start](#quick-start)
6. [App Integration](#app-integration)
7. [Script Usage](#script-usage)
8. [Configuration Reference](#configuration-reference)
9. [Screenshot Composer](#screenshot-composer)
10. [Output Structure](#output-structure)
11. [Subclassing Guide](#subclassing-guide)
12. [iPad Navigation](#ipad-navigation)
13. [Mock Data Setup](#mock-data-setup)
14. [Reuse Across Apps](#reuse-across-apps)
15. [Troubleshooting](#troubleshooting)
16. [App Store Requirements Reference](#app-store-requirements-reference)

---

## What it is

`ios-screenshot-automator` is a generic XCUITest-based screenshot automation framework extracted from a production iOS app. It provides a reusable base class (`ScreenshotTestBase`) that handles device detection, tab navigation, sheet management, edit-mode recovery, and screenshot saving. You subclass it, describe your app's screens in `captureAllScreens()`, copy the included template script into your project, fill in your project-specific values, and run it — the template auto-discovers the package and drives `xcodebuild` across every simulator that App Store Connect requires, including the 6.9-inch iPhone, the 13-inch iPad mandatory sizes, and Apple TV.

---

## Features

- **Multi-device support** – captures screenshots for every required and optional App Store Connect screen size in a single command, including iPhone, iPad, and Apple TV
- **Automatic fallback devices** – if a primary simulator (e.g. iPhone 17 Pro Max) is not installed, the script transparently falls back to the next-closest model
- **Smart iPad navigation** – six escalating strategies to locate tab items on any iPadOS layout (bottom tab bar, floating tab bar, sidebar, TabSection, label scan, coordinate tap)
- **Edit-mode recovery** – automatically detects and exits SwiftUI list edit mode before navigating
- **Sheet/modal dismissal** – four-strategy cascade: close button → cancel button → swipe down → tap outside
- **Parameterised shell script** – every value (`--project`, `--scheme`, `--test-target`, `--test-class`, etc.) is a CLI argument with a sensible default
- **Screenshot composer** – embed screenshots in App Store-ready images with customizable gradient backgrounds and device frames
- **Xcode Test Results integration** – every screenshot is also attached to the Xcode test result bundle for CI review
- **Available as a Swift Package** – add via Swift Package Manager (SPM) or copy one `.swift` file into your UITest target
- **Swift 5.9+ / Xcode 15+ compatible**

---

## Requirements

| Requirement | Minimum version |
|-------------|-----------------|
| Xcode | 15.0 |
| Swift | 5.9 |
| iOS Simulator | iOS 16.0 |
| tvOS Simulator | tvOS 16.0 (for Apple TV screenshots) |
| macOS (host) | macOS 13 Ventura |
| Shell | bash 3.2+ (ships with macOS) |

### Device Frame PNGs (for mockup composition)

If you use `Scripts/compose_mockup.swift` to generate App Store mockups with device frames, you must provide the frame PNGs yourself. **Device frames are not included in this package** — you need to download them and place them into your own project's repository (e.g. in a `Files/` folder).

Sources for device frames:
- [Apple Design Resources](https://developer.apple.com/design/resources/) (official, free)
- Create your own in Figma / Sketch (export as PNG with a transparent screen area)

> **Note:** The frame PNG must have the screen area as fully transparent pixels (alpha = 0). The script auto-detects the screen area. Frames with a black screen area also work, but transparent is preferred.

---

## Installation

### Swift Package Manager (recommended)

Add `ios-screenshot-automator` as a dependency in your `Package.swift` or via Xcode's **File → Add Package Dependencies…**:

```swift
.package(url: "https://github.com/matthias-karl/ios-screenshot-automator.git", from: "1.0.0")
```

Then add `ScreenshotAutomator` to your UITest target's dependencies:

```swift
.testTarget(
    name: "MyAppUITests",
    dependencies: [
        .product(name: "ScreenshotAutomator", package: "ios-screenshot-automator")
    ]
)
```

### Manual (file copy)

If you prefer not to use SPM, you can copy the source file directly — see [Quick Start](#quick-start).

---

## Quick Start

### Step 1 – Copy the source files

```bash
# From inside your iOS project directory
cp path/to/ios-screenshot-automator/Sources/ScreenshotTestBase.swift \
   <YourApp>UITests/ScreenshotTestBase.swift
cp path/to/ios-screenshot-automator/Sources/ScreenshotComposer.swift \
   <YourApp>UITests/ScreenshotComposer.swift
```

Add both files to your **UITest target** in Xcode (File → Add Files, or drag into the target group). Make sure each file's Target Membership is set to the UITest target only.

### Step 2 – Create your screenshot test subclass

Create a new Swift file in your UITest target. Use `Examples/ExampleScreenshotTest.swift` as a starting point:

```swift
import XCTest
import ScreenshotAutomator

final class MyAppScreenshotTest: ScreenshotTestBase {

    override func setUp() {
        super.setUp()

        // Override screenshot output directory to your project root
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // MyAppUITests/
            .deletingLastPathComponent()  // Project root
        let sanitizedDevice = UIDevice.current.name
            .replacingOccurrences(of: " ", with: "_")
        screenshotsURL = projectRoot
            .appendingPathComponent("screenshots")
            .appendingPathComponent(sanitizedDevice)
        try? FileManager.default.createDirectory(
            at: screenshotsURL, withIntermediateDirectories: true
        )
    }

    override func tabLabels(forIndex index: Int) -> [String] {
        switch index {
        case 0: return ["Home"]
        case 1: return ["Items"]
        case 2: return ["Profile"]
        default: return []
        }
    }

    override func captureAllScreens() throws {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        navigateToTabByIndex(0)
        sleep(1)
        try takeScreenshot(name: "01_Home")

        navigateToTabByIndex(1)
        sleep(1)
        try takeScreenshot(name: "02_Items")

        // Tap first data cell (index 1, skipping "Add" button at index 0)
        let cells = app.cells.allElementsBoundByIndex
        if cells.count > 1, cells[1].exists {
            cells[1].tap()
            sleep(1)
            try takeScreenshot(name: "03_ItemDetail")
            if !isIPad { app.navigationBars.buttons.firstMatch.tap() }
        }

        navigateToTabByIndex(2)
        sleep(1)
        try takeScreenshot(name: "04_Profile")
    }
}
```

### Step 3 – Add launch arguments to your app

See [App Integration](#app-integration) for details on how to handle the four launch arguments that `ScreenshotTestBase` injects.

### Step 4 – Implement mock data (optional but recommended)

Copy `Templates/MockDataProviderExample.swift` into your **main app target** and fill in your data. See [Mock Data Setup](#mock-data-setup).

### Step 5 – Copy the template script and run

```bash
# Copy the template — don't copy run_screenshots.sh directly
mkdir -p scripts
cp path/to/ios-screenshot-automator/Templates/capture_screenshots_template.sh \
    scripts/capture_screenshots.sh
chmod +x scripts/capture_screenshots.sh

# Fill in the ← CHANGE fields, then run from your project root
./scripts/capture_screenshots.sh
```

The template auto-discovers the package in DerivedData and calls the bundled scripts for you. See the [template header](Templates/capture_screenshots_template.sh) for the full setup guide.

---

## App Integration

`ScreenshotTestBase.setUp()` launches the app with four launch arguments. Your app should react to each one:

| Launch Argument | Purpose | Recommended action |
|---|---|---|
| `-UITEST` | The app is running under a UI test | Skip production-only code paths (analytics, crash reporters, etc.) |
| `-LOAD_MOCK_DATA` | Inject screenshot mock data | Replace live data layer with deterministic mock objects |
| `-DISABLE_ANIMATIONS` | Remove animation delays | Call `UIView.setAnimationsEnabled(false)` |
| `-SKIP_ONBOARDING` | Skip first-launch screens | Set a `hasSeenOnboarding` flag to `true` |

### Example – SwiftUI `@main` struct

```swift
@main
struct MyApp: App {
    init() {
        let args = CommandLine.arguments

        if args.contains("-DISABLE_ANIMATIONS") {
            UIView.setAnimationsEnabled(false)
        }
        if args.contains("-LOAD_MOCK_DATA") {
            let mock = MyAppScreenshotMockData.createMockData()
            DataStore.shared.items      = mock.items
            DataStore.shared.categories = mock.categories
        }
        if args.contains("-SKIP_ONBOARDING") {
            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

---

## Script Usage

The recommended workflow uses the **template script** (`Templates/capture_screenshots_template.sh`). Copy it into your project, fill in the `← CHANGE` fields, and run it. The template auto-discovers `run_screenshots.sh` and `compose_mockup.swift` from the SPM checkout in DerivedData — you never copy those scripts directly.

```bash
./scripts/capture_screenshots.sh [OPTIONS]
```

### Template configuration (edit once)

| Field | Description |
|-------|-------------|
| `APP_NAME` | Your `.xcodeproj` name (without extension) |
| `SCHEME` | Xcode scheme to build |
| `TEST_TARGET` | UI test target name |
| `TEST_CLASS` | XCTestCase subclass name |
| `TEST_METHOD` | Test method (default: `testTakeAllScreenshots`) |
| `LANGUAGES` | Comma-separated language codes (e.g. `"en,de,fr"`) |
| `DEVICES` | Array of device entries (see format below) |
| `GRADIENT_START` / `GRADIENT_END` | Hex colours for mockup gradient background |
| `SCREENSHOTS_DIR` | Raw screenshot output folder (default: `screenshots`) |
| `MOCKUPS_DIR` | Mockup output folder (default: `Appstore Mockups`) |

### Device entry format

```
"SimulatorName|FramePath|DevicePreset|Margin"
```

| Part | Example |
|------|---------|
| `SimulatorName` | `iPhone 16 Pro Max` — as shown by `xcrun simctl list devices` |
| `FramePath` | `Files/iPhone16ProMax-Frame.png` — relative to project root |
| `DevicePreset` | `iphone69`, `iphone67`, `ipad13`, `appletv`, etc. (see template for full list) |
| `Margin` | `30` (iPhone) / `70` (iPad) — pixels between frame and canvas edge |

> **Device frame PNGs are not included.** Download from [Apple Design Resources](https://developer.apple.com/design/resources/) or similar and place them in your project repo. The frame must have a transparent screen area.

### Runtime flags

| Flag | Purpose |
|------|---------|
| *(no flags)* | Full pipeline — capture screenshots + generate mockups |
| `--mockups-only` | Skip capture, regenerate mockups from existing screenshots |
| `--iphone-only` | Skip iPad and Apple TV devices |

### Examples

```bash
# Full pipeline (capture + mockups)
./scripts/capture_screenshots.sh

# Re-generate mockups from existing screenshots
./scripts/capture_screenshots.sh --mockups-only

# iPhone devices only
./scripts/capture_screenshots.sh --iphone-only
```

### Internal scripts (for reference)

The template calls these automatically — you do **not** run them directly:

| Script | Purpose |
|--------|---------|
| `Scripts/run_screenshots.sh` | Boots simulators and runs `xcodebuild test` across devices/languages |
| `Scripts/compose_mockup.swift` | Overlays a screenshot onto a device frame with a gradient background |

---

## Configuration Reference

All properties in `ScreenshotTestConfig` are surfaced as `open class var` on `ScreenshotTestBase` so subclasses can override them.

| Property | Default | Description |
|----------|---------|-------------|
| `initialDelay` | `3.0 s` | Pause after app launch – lets system alerts appear |
| `navigationDelay` | `1.5 s` | Pause after navigating to a screen |
| `animationDelay` | `0.5 s` | Pause for in-app animations to finish |
| `sheetDelay` | `1.0 s` | Pause after a sheet/modal is opened |
| `targetDevices` | iPhone 17 Pro Max, iPhone 17 Pro, iPad Pro 13" (M5) | Device list for universal mode |
| `iPhoneOnlyDevices` | iPhone 17 Pro Max, iPhone 17 Pro | Device list for `--iphone-only` mode |
| `appleTVDevices` | Apple TV 4K (3rd generation) | Device list for Apple TV mode |

### Overriding timing in a subclass

```swift
class MyAppScreenshotTest: ScreenshotTestBase {
    // Slow down navigation for apps with complex transitions
    override class var navigationDelay: TimeInterval { 2.5 }
    override class var animationDelay:  TimeInterval { 1.0 }
}
```

---

## Screenshot Composer

The screenshot composer embeds raw device screenshots into App Store-ready images with customizable gradient backgrounds and device frames. The output image retains the original screenshot dimensions, ensuring compliance with App Store Connect size requirements.

### Enabling the composer

Set `composerConfig` on your `ScreenshotTestBase` subclass in `setUp()`:

```swift
class MyAppScreenshotTest: ScreenshotTestBase {
    override func setUp() {
        super.setUp()
        composerConfig = ScreenshotComposerConfig(
            gradientColors: [.systemBlue, .systemPurple],
            deviceFrameStyle: .automatic
        )
    }
}
```

When `composerConfig` is `nil` (the default), screenshots are saved as raw device captures—exactly as before.

### Configuration options

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `gradientColors` | `[UIColor]` | `[.systemBlue, .systemPurple]` | Two or more colors for the background gradient |
| `gradientDirection` | `GradientDirection` | `.topToBottom` | Direction of the gradient (see options below) |
| `deviceFrameStyle` | `DeviceFrameStyle` | `.automatic` | Frame style: `.none`, `.generic`, `.iPhone`, `.iPad`, `.tv`, or `.automatic` |
| `frameColor` | `UIColor` | `.black` | Color of the device bezel |
| `screenshotScale` | `CGFloat` | `0.75` | How much of the canvas the device occupies (0.1–1.0) |
| `frameCornerRadius` | `CGFloat?` | `nil` (auto) | Custom corner radius for the frame |
| `frameBezelWidth` | `CGFloat?` | `nil` (auto) | Custom bezel width |

### Gradient directions

| Value | Direction |
|-------|-----------|
| `.topToBottom` | Top → Bottom |
| `.bottomToTop` | Bottom → Top |
| `.leftToRight` | Left → Right |
| `.rightToLeft` | Right → Left |
| `.topLeftToBottomRight` | Top-left → Bottom-right |
| `.topRightToBottomLeft` | Top-right → Bottom-left |

### Device frame styles

| Value | Description |
|-------|-------------|
| `.none` | No frame – screenshot placed directly on the gradient |
| `.generic` | A generic rounded-rectangle frame |
| `.iPhone` | iPhone-shaped frame (narrower bezels, larger corner radius) |
| `.iPad` | iPad-shaped frame (wider bezels, smaller corner radius) |
| `.tv` | Apple TV-shaped frame (minimal bezels, very small corner radius) |
| `.automatic` | Auto-selects `.iPhone`, `.iPad`, or `.tv` based on the current device |

### Per-screenshot overrides

Pass a `ScreenshotComposerOverride` to `takeScreenshot(name:composerOverride:)` to use different gradient colors or direction for individual screens:

```swift
override func captureAllScreens() throws {
    navigateToTabByIndex(0)
    try takeScreenshot(name: "01_Home")  // Uses base config

    navigateToTabByIndex(1)
    try takeScreenshot(
        name: "02_Items",
        composerOverride: ScreenshotComposerOverride(
            gradientColors: [.systemTeal, .systemIndigo]
        )
    )
}
```

### Full example

```swift
class MyAppScreenshotTest: ScreenshotTestBase {
    override func setUp() {
        super.setUp()
        composerConfig = ScreenshotComposerConfig(
            gradientColors: [
                UIColor(red: 0.2, green: 0.1, blue: 0.5, alpha: 1),
                UIColor(red: 0.8, green: 0.3, blue: 0.6, alpha: 1)
            ],
            gradientDirection: .topLeftToBottomRight,
            deviceFrameStyle: .automatic,
            frameColor: .black,
            screenshotScale: 0.75
        )
    }

    override func captureAllScreens() throws {
        navigateToTabByIndex(0)
        try takeScreenshot(name: "01_Home")
    }
}
```

---

## Output Structure

Screenshots are saved to `<screenshots-dir>/<DeviceName>/` relative to the project root. The device name is derived from `UIDevice.current.name` with spaces replaced by underscores.

```
Screenshots/
├── iPhone_17_Pro_Max/
│   ├── iPhone_17_Pro_Max_01_Home.png
│   ├── iPhone_17_Pro_Max_02_Items.png
│   ├── iPhone_17_Pro_Max_03_ItemDetail.png
│   └── iPhone_17_Pro_Max_04_Profile.png
├── iPhone_17_Pro/
│   ├── iPhone_17_Pro_01_Home.png
│   └── …
└── iPad_Pro_13-inch_(M5)/
    ├── iPad_Pro_13-inch_(M5)_01_Home.png
    └── …
```

All screenshots are also attached to the Xcode test result bundle (`.xcresult`) and visible in Xcode's Test Navigator under **Attachments**.

---

## Subclassing Guide

All methods below are declared `open` and can be overridden in your subclass.

### Must override

| Method | Signature | Description |
|--------|-----------|-------------|
| `captureAllScreens` | `open func captureAllScreens() throws` | Navigate through your app and call `takeScreenshot(name:)` for each screen |

### Optional overrides

| Method | Signature | Description |
|--------|-----------|-------------|
| `tabLabels(forIndex:)` | `open func tabLabels(forIndex index: Int) -> [String]` | Return possible accessibility labels for each tab index – used by iPad strategies 3, 4 & 5 |
| `setUp` | `override open func setUp()` | Customise app launch arguments or screenshot directory |
| `takeScreenshot` | `open func takeScreenshot(name: String, composerOverride: ScreenshotComposerOverride?) throws` | Change file naming, format, or metadata |
| `navigateToTabByIndex` | `open func navigateToTabByIndex(_ index: Int)` | Replace the navigation strategy entirely |
| `navigateToTabOnIPhone` | `open func navigateToTabOnIPhone(_ index: Int)` | Customise iPhone tab navigation |
| `navigateToTabOnIPad` | `open func navigateToTabOnIPad(_ index: Int)` | Customise iPad tab navigation |
| `navigateToTabByLabel` | `open func navigateToTabByLabel(_ labels: [String]) -> Bool` | Navigate by accessibility label instead of index |
| `tapPlusButton` | `open func tapPlusButton() -> Bool` | Locate and tap the add/plus button |
| `dismissSheet` | `open func dismissSheet()` | Dismiss a presented sheet or modal |
| `ensureMainViewVisible` | `open func ensureMainViewVisible()` | Return to the main tab view |
| `exitEditModeIfNeeded` | `open func exitEditModeIfNeeded()` | Exit list edit mode |
| `tapFirstHittableCell` | `open func tapFirstHittableCell() -> Bool` | Tap the first visible list cell |
| `waitForHittable` | `open func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool` | Wait for an element to become tappable |
| `dismissSystemAlerts` | `open func dismissSystemAlerts()` | Dismiss system permission dialogs |

### Timing class vars

| Property | Signature |
|----------|-----------|
| `initialDelay` | `open class var initialDelay: TimeInterval` |
| `navigationDelay` | `open class var navigationDelay: TimeInterval` |
| `animationDelay` | `open class var animationDelay: TimeInterval` |
| `sheetDelay` | `open class var sheetDelay: TimeInterval` |

---

## iPad Navigation

`navigateToTabOnIPad(_:)` attempts six strategies in order, stopping as soon as one succeeds:

| # | Strategy | Description |
|---|----------|-------------|
| 1 | **Standard tab bar** | Looks for `app.tabBars.firstMatch` and taps by index. Falls back to label matching, then coordinate tap if the button exists but is not hittable (e.g. obscured by the floating tab bar overlay). |
| 2 | **TabSection** | Searches for `otherElements` with identifier `"TabSection"` – the iPadOS 18+ floating tab bar container. |
| 3 | **Direct button search** | Searches for buttons matching `tabLabels(forIndex:)` anywhere in the app. |
| 4 | **Sidebar toggle** | Taps the `"ToggleSidebar"` button (if present) to reveal a sidebar, then searches for matching static texts (using coordinate taps to avoid long-press edit mode) and buttons. |
| 5 | **Broad button scan** | Collects all hittable buttons across the entire app and filters those whose label or identifier matches any label returned by `tabLabels(forIndex:)`. |
| 6 | **Coordinate fallback** | Force-taps the tab bar button by its normalised coordinate `(0.5, 0.5)`. |

To get the best results on iPad, override `tabLabels(forIndex:)`:

```swift
override func tabLabels(forIndex index: Int) -> [String] {
    switch index {
    case 0: return ["Home"]
    case 1: return ["Items", "My Items"]   // include localized variants
    case 2: return ["Profile", "Account"]
    default: return []
    }
}
```

---

## Mock Data Setup

Screenshot tests look best with consistent, realistic data. Use `Templates/MockDataProviderExample.swift` as a starting point.

### How it works

1. `ScreenshotTestBase.setUp()` sets `-LOAD_MOCK_DATA` as a launch argument.
2. Your app checks `CommandLine.arguments.contains("-LOAD_MOCK_DATA")` at startup.
3. If true, the app injects mock objects instead of loading from the real database/network.

### Example

```swift
// In your main app target (e.g. ScreenshotMockData.swift)
struct MyAppScreenshotMockData {
    let items: [Item]

    static func createMockData() -> MyAppScreenshotMockData {
        MyAppScreenshotMockData(items: [
            Item(id: "1", title: "First Item"),
            Item(id: "2", title: "Second Item"),
        ])
    }
}
```

```swift
// In your @main App struct
if CommandLine.arguments.contains("-LOAD_MOCK_DATA") {
    let mock = MyAppScreenshotMockData.createMockData()
    DataStore.shared.items = mock.items
}
```

See `Templates/MockDataProviderExample.swift` for the full protocol and implementation scaffold.

---

## Reuse Across Apps

`ios-screenshot-automator` supports two integration models.

### Option A – Swift Package Manager

Add the package via SPM (see [Installation](#installation)). Import `ScreenshotAutomator` in your UITest target and subclass `ScreenshotTestBase` directly — no file copying required.

### Option B – File copy

1. Copy `Sources/ScreenshotTestBase.swift` and `Sources/ScreenshotComposer.swift` into your UITest target.
2. Copy `Templates/capture_screenshots_template.sh` into your project's `scripts/` folder and fill in the `← CHANGE` fields.
3. Copy `Templates/MockDataProviderExample.swift` into your main app target and fill it in.
4. Create a subclass of `ScreenshotTestBase` in your UITest target.

The single-file design means there are no dependency conflicts and the code is always easy to read and modify inline.

---

## Troubleshooting

### Simulator not found

```
⚠️  Simulator 'iPhone 17 Pro Max' not found and no fallback available – skipping
```

**Fix:** Install the required simulator runtime in Xcode → Settings → Platforms. Check that the `APP_NAME`, `SCHEME`, and `DEVICES` entries in your template script match your project.

### Tab not hittable on iPad

```
⚠️ iPad: Could not navigate to tab 1
```

**Fix:** Override `tabLabels(forIndex:)` in your subclass to return the correct accessibility labels for each tab. Also verify that your app sets `.accessibilityLabel` or `.accessibilityIdentifier` on tab items.

### App is stuck in edit mode

```
⚠️ List is in edit mode – tapping 'Done' to exit
```

This is expected behaviour – `exitEditModeIfNeeded()` handles it automatically. If it fires repeatedly, ensure your app does not enter edit mode on initial load.

### Sheet not dismissing

If `dismissSheet()` does not close your modal, check that:
- The close button has the accessibility identifier `"xmark"` (SF Symbol name), or
- The button label is one of: `Cancel`, `Abbrechen`, `Close`, `Schließen`, `Done`, `Fertig`, `Dismiss`

If your button uses a custom identifier, override `dismissSheet()` in your subclass.

### Screenshots saved to wrong location

`ScreenshotTestBase.setUp()` uses `#file` at compile time to locate the project root. The path calculation assumes the Swift file is two directory levels inside the project root:

```
<ProjectRoot>/<UITestsFolder>/ScreenshotTestBase.swift
                ^--- two .deletingLastPathComponent() calls
```

If your folder structure differs, override `setUp()` and set `screenshotsURL` manually:

```swift
override func setUp() {
    super.setUp()
    screenshotsURL = URL(fileURLWithPath: "/path/to/my/Screenshots/\(deviceName)")
    try? FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
}
```

### Build errors: `ScreenshotTestBase` not found

Ensure `ScreenshotTestBase.swift` is added to the UITest target, **not** the main app target. Check Target Membership in the File Inspector (⌥⌘1) in Xcode.

---

## App Store Requirements Reference

Apple documentation: [Screenshot specifications – App Store Connect Help](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications)

### Required screenshot sizes

| Device | Display | Resolution | Status |
|--------|---------|------------|--------|
| iPhone 17 Pro Max (or similar) | 6.9" | 1320 × 2868 px | **Required** |
| iPad Pro 13-inch (or similar) | 13" | 2064 × 2752 px | **Required for iPad apps** |

### Optional (but recommended) sizes

| Device | Display | Resolution |
|--------|---------|------------|
| iPhone 17 Pro | 6.3" | 1206 × 2622 px |
| iPhone 16e | 6.1" | 1080 × 2340 px |
| iPhone 14 Plus | 6.5" | 1284 × 2778 px (legacy 6.5" slot) |
| iPad Air 13-inch (M3) | 11" | 1668 × 2388 px |

### Apple TV screenshot sizes

| Device | Resolution | Status |
|--------|------------|--------|
| Apple TV 4K (3rd generation) | 1920 × 1080 px | **Required for tvOS apps** |

> **Note:** If you submit screenshots for the 6.9" slot, App Store Connect will automatically scale them for the 6.5" slot. Submitting both is still recommended for the sharpest display on older devices.

`ScreenshotTestConfig.AppStoreDevices` maps every relevant simulator name to its display size, and `ScreenshotTestConfig.targetDevices` provides a ready-made list covering all required sizes. Use `ScreenshotTestConfig.appleTVDevices` for Apple TV.
