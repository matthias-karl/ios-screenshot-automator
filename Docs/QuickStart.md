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

## 4. Copy the template script and configure it

Copy the **template** into your project — do **not** copy `run_screenshots.sh` or `compose_mockup.swift` directly. The template auto-discovers the package in your Xcode DerivedData and calls the bundled scripts for you.

```bash
mkdir -p scripts
cp path/to/ios-screenshot-automator/Templates/capture_screenshots_template.sh \
    scripts/capture_screenshots.sh
chmod +x scripts/capture_screenshots.sh
```

Open `scripts/capture_screenshots.sh` and fill in every field marked `← CHANGE`:

```bash
APP_NAME="MyApp"                        # ← your .xcodeproj name (without extension)
SCHEME="MyApp"                          # ← Xcode scheme
TEST_TARGET="MyAppUITests"              # ← UI test target name
TEST_CLASS="MyAppScreenshotTest"        # ← your XCTestCase subclass
TEST_METHOD="testTakeAllScreenshots"    # ← test method (usually keep as-is)
LANGUAGES="en"                          # ← comma-separated, e.g. "en,de,fr"

GRADIENT_START="#667EEA"                # ← mockup gradient top color
GRADIENT_END="#764BA2"                  # ← mockup gradient bottom color

DEVICES=(
    "iPhone 16 Pro Max|Files/iPhone16ProMax-Frame.png|iphone69|30"
    "iPhone 16 Pro|Files/iPhone16Pro-Frame.png|iphone67|30"
    # "iPad Pro 13-inch (M4)|Files/iPadPro13-Frame.png|ipad13|70"
)
```

> **Device frame PNGs are not included.** Download them from
> [Apple Design Resources](https://developer.apple.com/design/resources/),
> [Figma Community](https://www.figma.com/community) or similar, and place
> them in your project repo (e.g. `Files/`). The frame must have a
> transparent screen area.

Then run:

```bash
./scripts/capture_screenshots.sh               # full pipeline: capture + mockups
./scripts/capture_screenshots.sh --mockups-only # re-generate mockups from existing screenshots
./scripts/capture_screenshots.sh --iphone-only  # skip iPad devices
```

Screenshots land in `screenshots/<Device_Name>/`, mockups in `Appstore Mockups/<Device_Name>/`.

See the [template header](../Templates/capture_screenshots_template.sh) for the full device-entry format, preset list, and setup guide.

---

## Cheat sheet

| What | Where |
|------|-------|
| Base class to subclass | `ScreenshotTestBase` (in `Sources/ScreenshotTestBase.swift`) |
| Override this method | `captureAllScreens()` |
| Override for iPad | `tabLabels(forIndex:)` |
| Template script | `Templates/capture_screenshots_template.sh` — copy into your project |
| Shell runner (internal) | `Scripts/run_screenshots.sh` — called by the template, don't copy |
| Mockup composer (internal) | `Scripts/compose_mockup.swift` — called by the template, don't copy |
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

### Template script flags

| Flag | Purpose |
|------|---------|
| *(no flags)* | Full pipeline — capture screenshots + generate mockups |
| `--mockups-only` | Skip capture, regenerate mockups from existing screenshots |
| `--iphone-only` | Skip iPad devices |

---

**That's it.** For customisation (timing, composer config, CI/CD) see the full [Developer How-To](DeveloperHowto.md). For the complete device-entry format and preset list, see the [template header](../Templates/capture_screenshots_template.sh).
