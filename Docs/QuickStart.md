# Quick Start Guide

Get from zero to automated App Store screenshots in **5 minutes**.

---

## 1. Add the package

In Xcode: **File → Add Package Dependencies…** → paste:

```
https://github.com/matthias-karl/ios-screenshot-automator.git
```

Add **`ScreenshotAutomator`** to your **UITest target** (not the main app target).

---

## 2. Create your screenshot test

Add a new Swift file to your UITest target (e.g. `MyAppScreenshotTest.swift`):

```swift
import XCTest
import ScreenshotAutomator

final class MyAppScreenshotTest: ScreenshotTestBase {

    override func setUp() {
        super.setUp()

        // Save screenshots relative to your project root
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()   // MyAppUITests/
            .deletingLastPathComponent()   // project root
        let device = UIDevice.current.name.replacingOccurrences(of: " ", with: "_")

        screenshotsURL = projectRoot
            .appendingPathComponent("screenshots")
            .appendingPathComponent(device)
        try? FileManager.default.createDirectory(
            at: screenshotsURL, withIntermediateDirectories: true
        )
    }

    // Required for iPad — return tab labels for each index
    override func tabLabels(forIndex index: Int) -> [String] {
        switch index {
        case 0: return ["Home"]
        case 1: return ["Items"]
        case 2: return ["Settings"]
        default: return []
        }
    }

    override func captureAllScreens() throws {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        // Tab 0
        navigateToTabByIndex(0)
        sleep(1)
        try takeScreenshot(name: "01_Home")

        // Tab 1 — list
        navigateToTabByIndex(1)
        sleep(1)
        try takeScreenshot(name: "02_Items")

        // Tap first data cell (skip "Add" button at index 0 if you have one)
        let cells = app.cells.allElementsBoundByIndex
        if cells.count > 1, cells[1].exists {
            cells[1].tap()
            sleep(1)
            try takeScreenshot(name: "03_Detail")

            // iPhone: go back; iPad: split-view, no back needed
            if !isIPad {
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }
        }

        // Tab 2
        navigateToTabByIndex(2)
        sleep(1)
        try takeScreenshot(name: "04_Settings")
    }
}
```

---

## 3. Handle launch arguments in your app

`ScreenshotTestBase` launches your app with four arguments. React to them in your `@main` struct or `AppDelegate`:

```swift
init() {
    if CommandLine.arguments.contains("-DISABLE_ANIMATIONS") {
        UIView.setAnimationsEnabled(false)
    }
    if CommandLine.arguments.contains("-LOAD_MOCK_DATA") {
        // inject mock data so screenshots look filled and consistent
    }
    if CommandLine.arguments.contains("-SKIP_ONBOARDING") {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
    }
    // "-UITEST" — skip analytics, crash reporters, etc.
}
```

---

## 4. Copy and run the script

```bash
# Copy the runner script into your project
mkdir -p scripts
cp ios-screenshot-automator/Scripts/run_screenshots.sh scripts/
chmod +x scripts/run_screenshots.sh

# Run it
./scripts/run_screenshots.sh \
    --project MyApp.xcodeproj \
    --scheme MyApp \
    --test-target MyAppUITests \
    --test-class MyAppScreenshotTest \
    --output screenshots
```

Screenshots land in `screenshots/<Device_Name>/`.

---

## 5. (Optional) Generate App Store mockups

If you want device-frame mockups with gradient backgrounds, you also need:

1. **Device frame PNGs** — download from [Apple Design Resources](https://developer.apple.com/design/resources/) and place them in your project repo (e.g. `Files/`). These are **not** included in the package.
2. **The compose script** — already included at `Scripts/compose_mockup.swift`.

Run it for a single screenshot:

```bash
swift ios-screenshot-automator/Scripts/compose_mockup.swift \
    --frame "Files/iPhone 17 Pro - Silver - Portrait.png" \
    --screenshot screenshots/iPhone_17_Pro/iPhone_17_Pro_01_Home.png \
    --output mockups/01_Home.png \
    --device iphone69 \
    --gradient-start '#667EEA' \
    --gradient-end '#764BA2'
```

Or create a wrapper script to batch all screenshots — see [`Docs/DeveloperHowto.md` § Wrapper Script Template](DeveloperHowto.md#8-wrapper-script-template).

---

## Cheat sheet

| What | Where |
|------|-------|
| Base class to subclass | `ScreenshotTestBase` (in `Sources/ScreenshotTestBase.swift`) |
| Override this method | `captureAllScreens()` |
| Override for iPad | `tabLabels(forIndex:)` |
| Shell runner | `Scripts/run_screenshots.sh` |
| Mockup composer | `Scripts/compose_mockup.swift` |
| Example test | `Examples/ExampleScreenshotTest.swift` |
| Mock data template | `Templates/MockDataProviderExample.swift` |
| Full docs | `Docs/DeveloperHowto.md` · `Docs/ScreenshotPipeline.md` |

### Launch arguments set by the base class

| Argument | Purpose |
|----------|---------|
| `-UITEST` | App is running under UI test |
| `-LOAD_MOCK_DATA` | Inject screenshot mock data |
| `-DISABLE_ANIMATIONS` | Turn off Core Animation |
| `-SKIP_ONBOARDING` | Skip onboarding / tutorial |

### Key script flags

| Flag | Example |
|------|---------|
| `--project` | `--project MyApp.xcodeproj` |
| `--scheme` | `--scheme MyApp` |
| `--test-target` | `--test-target MyAppUITests` |
| `--test-class` | `--test-class MyAppScreenshotTest` |
| `--output` | `--output screenshots` |
| `--devices` | `--devices "iPhone 17 Pro Max,iPad Pro 13-inch (M5)"` |
| `--languages` | `--languages "en,de"` |
| `--iphone-only` | skip iPad devices |

---

**That's it.** For customisation (gradients, timing, composer config, CI/CD) see the full [Developer How-To](DeveloperHowto.md).
