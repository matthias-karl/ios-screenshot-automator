# Screenshot & Mockup Generation Pipeline

## Complete Documentation for `ios-screenshot-automator`

> **Version:** 1.0  
> **Last Updated:** March 2026  
> **Package:** `ios-screenshot-automator`  
> **Platform:** iOS 16+ / macOS 13+ / Xcode 15+ / Swift 5.9+

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Pipeline Stages](#3-pipeline-stages)
4. [Stage 1 — Screenshot Capture](#4-stage-1--screenshot-capture)
   - [ScreenshotTestBase](#41-screenshottestbase)
   - [Subclassing](#42-subclassing)
   - [Navigation System](#43-navigation-system)
   - [Screenshot Helpers](#44-screenshot-helpers)
   - [App Integration](#45-app-integration)
   - [Mock Data](#46-mock-data)
5. [Stage 2 — Test Execution](#5-stage-2--test-execution)
   - [run_screenshots.sh](#51-run_screenshotssh)
   - [CLI Options](#52-cli-options)
   - [Simulator Management](#53-simulator-management)
   - [Fallback Devices](#54-fallback-devices)
6. [Stage 3 — Mockup Composition](#6-stage-3--mockup-composition)
   - [compose_mockup.swift](#61-compose_mockupswift)
   - [Device Frame Requirements](#62-device-frame-requirements)
   - [Screen Area Detection](#63-screen-area-detection)
   - [Compositing Pipeline](#64-compositing-pipeline)
   - [Apple Device Presets](#65-apple-device-presets)
   - [CLI Reference](#66-cli-reference)
7. [Stage 4 — Wrapper Script](#7-stage-4--wrapper-script)
8. [Integration Example (Plantner)](#8-integration-example-plantner)
9. [Apple App Store Requirements](#9-apple-app-store-requirements)
10. [File Reference](#10-file-reference)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Overview

`ios-screenshot-automator` is a complete pipeline for generating App Store-ready screenshots and device mockups for iOS apps. It automates the entire process from capturing raw screenshots on simulators to compositing them into polished mockup images with device frames and gradient backgrounds.

### What it produces

```
Raw Screenshots (PNG)          →    App Store Mockups (PNG)
┌─────────────────────┐            ┌─────────────────────┐
│                     │            │ ░░░░░░░░░░░░░░░░░░░ │  ← Gradient background
│   App Screenshot    │  compose   │ ░░┌─────────────┐░░ │
│   (1206×2622 px)    │  ───────→  │ ░░│  ┌───────┐  │░░ │  ← Device frame
│                     │  mockup    │ ░░│  │       │  │░░ │
│                     │            │ ░░│  │ App   │  │░░ │  ← Screenshot inside
│                     │            │ ░░│  │       │  │░░ │
└─────────────────────┘            │ ░░│  └───────┘  │░░ │
                                   │ ░░└─────────────┘░░ │
                                   │ ░░░░░░░░░░░░░░░░░░░ │
                                   └─────────────────────┘
                                     (1320×2868 px)
```

### Key features

- **Automated screenshot capture** across multiple iOS simulators (iPhone + iPad)
- **Smart iPad navigation** with 6 escalating strategies for tab/sidebar navigation
- **Automatic screen area detection** in device frames (transparent or black)
- **Device-specific corner radius** clipping (15% for iPhones, 2% for iPads)
- **Apple-compliant output** at exact App Store Connect pixel dimensions
- **Gradient backgrounds** with configurable colors and angle
- **Aspect-fit frame scaling** with configurable minimum margin
- **Multi-language support** for localized screenshots
- **Fallback simulator devices** when primary devices are unavailable
- **Single-command execution** from capture to final mockup

---

## 2. Architecture

### Package Structure

```
ios-screenshot-automator/
├── Package.swift                          # SPM package definition
├── README.md                              # Quick-start guide
├── Docs/
│   ├── QuickStart.md                      # 5-minute quick start guide
│   ├── DeveloperHowto.md                  # Developer integration guide
│   └── ScreenshotPipeline.md              # This file
├── Sources/
│   ├── ScreenshotTestBase.swift           # XCUITest base class (768 lines)
│   └── ScreenshotComposer.swift           # Screenshot composition (363 lines)
├── Scripts/
│   ├── run_screenshots.sh                 # Simulator orchestration script
│   └── compose_mockup.swift               # Mockup composition script
├── Examples/
│   └── ExampleScreenshotTest.swift        # Example subclass
├── Templates/
│   └── MockDataProviderExample.swift      # Mock data scaffold
├── Screenshots/                           # Default screenshot output
└── LICENSE
```

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    capture_app_screenshots.sh                    │
│              (Project-specific wrapper script)                   │
├─────────────────────────┬───────────────────────────────────────┤
│                         │                                       │
│  ┌──────────────────────▼──────────────────────┐                │
│  │         run_screenshots.sh                   │                │
│  │  • Boot simulators                           │                │
│  │  • Run xcodebuild test                       │                │
│  │  • Collect screenshots per device/language    │                │
│  │                                              │                │
│  │  ┌────────────────────────────────────────┐  │                │
│  │  │     ScreenshotTestBase (XCUITest)      │  │                │
│  │  │  • Launch app with mock data           │  │                │
│  │  │  • Navigate tabs (iPhone/iPad)         │  │                │
│  │  │  • Capture & save PNGs                 │  │                │
│  │  │  • Dismiss sheets, exit edit mode      │  │                │
│  │  └────────────────────────────────────────┘  │                │
│  └──────────────────────┬──────────────────────┘                │
│                         │  Raw PNGs                              │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────┐               │
│  │         compose_mockup.swift                  │               │
│  │  • Load device frame + screenshot             │               │
│  │  • Auto-detect screen area in frame           │               │
│  │  • Scale frame to fit canvas with margin      │               │
│  │  • Draw gradient → screenshot → frame         │               │
│  │  • Export opaque PNG at Apple dimensions       │               │
│  └──────────────────────┬───────────────────────┘               │
│                         │  Final Mockups                         │
│                         ▼                                       │
│              Appstore Mockups/<Device>/                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Pipeline Stages

The generation pipeline consists of four stages:

| Stage | Component | Input | Output |
|-------|-----------|-------|--------|
| **1** | `ScreenshotTestBase` | Running app on simulator | Raw PNG screenshots |
| **2** | `run_screenshots.sh` | Xcode project + test class | Screenshots per device/language |
| **3** | `compose_mockup.swift` | Screenshot PNG + device frame PNG | App Store mockup PNG |
| **4** | Wrapper script | Configuration | Orchestrates stages 1–3 |

---

## 4. Stage 1 — Screenshot Capture

### 4.1 ScreenshotTestBase

`ScreenshotTestBase` is an `open` XCUITest base class that provides the core screenshot infrastructure. It lives in `Sources/ScreenshotTestBase.swift` and is distributed as the `ScreenshotAutomator` Swift Package library.

#### Class Hierarchy

```
XCTestCase
  └── ScreenshotTestBase (open)
        └── YourAppScreenshotTest (final)
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `app` | `XCUIApplication!` | The launched application under test |
| `screenshotsURL` | `URL` | Directory where screenshots are saved |
| `deviceName` | `String` | Current simulator device name (e.g. "iPhone 17 Pro") |

#### Lifecycle

```
setUp()
  │
  ├── Read device name from UIDevice.current
  ├── Calculate screenshotsURL from #file location
  ├── Create screenshot directory
  ├── Configure XCUIApplication with launch arguments:
  │     -UITEST
  │     -LOAD_MOCK_DATA
  │     -DISABLE_ANIMATIONS
  │     -SKIP_ONBOARDING
  └── Launch the app
          │
testTakeAllScreenshots()
  │
  ├── Wait for system notifications (initialDelay)
  ├── Dismiss system alerts (permission dialogs)
  └── Call captureAllScreens()  ← YOUR CODE
```

#### Timing Constants

All timing values are declared as `open class var` and can be overridden per subclass:

| Constant | Default | Purpose |
|----------|---------|---------|
| `initialDelay` | 3.0s | Wait after app launch for system dialogs |
| `navigationDelay` | 1.5s | Wait after tab navigation |
| `animationDelay` | 0.5s | Wait for in-app animations |
| `sheetDelay` | 1.0s | Wait after opening a sheet/modal |

```swift
// Override in your subclass for slower transitions:
override class var navigationDelay: TimeInterval { 2.5 }
```

### 4.2 Subclassing

#### Minimal Subclass

```swift
import XCTest
import ScreenshotAutomator

final class MyAppScreenshotTest: ScreenshotTestBase {

    override func captureAllScreens() throws {
        navigateToTabByIndex(0)
        try takeScreenshot(name: "01_Home")

        navigateToTabByIndex(1)
        try takeScreenshot(name: "02_Items")

        navigateToTabByIndex(2)
        try takeScreenshot(name: "03_Profile")
    }
}
```

#### Full-Featured Subclass

```swift
import XCTest
import ScreenshotAutomator

final class MyAppScreenshotTest: ScreenshotTestBase {

    override func setUp() {
        super.setUp()
        // Custom screenshot directory
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()   // UITests/
            .deletingLastPathComponent()   // Project root
        let sanitizedDevice = UIDevice.current.name
            .replacingOccurrences(of: " ", with: "_")
        screenshotsURL = projectRoot
            .appendingPathComponent("screenshots")
            .appendingPathComponent(sanitizedDevice)
        try? FileManager.default.createDirectory(
            at: screenshotsURL, withIntermediateDirectories: true
        )
    }

    // Required for iPad sidebar/tab navigation
    override func tabLabels(forIndex index: Int) -> [String] {
        switch index {
        case 0: return ["Home"]
        case 1: return ["Items", "Einträge"]     // Include localized labels
        case 2: return ["Profile", "Profil"]
        default: return []
        }
    }

    override func captureAllScreens() throws {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        // Tab 0 – Home
        navigateToTabByIndex(0)
        sleep(1)
        try takeScreenshot(name: "01_Home")

        // Tab 1 – Items list
        navigateToTabByIndex(1)
        sleep(1)
        try takeScreenshot(name: "02_Items")

        // Item detail – tap first data cell (index 1, skipping "Add" at index 0)
        let cells = app.cells.allElementsBoundByIndex
        if cells.count > 1, cells[1].exists {
            cells[1].tap()
            sleep(1)
            try takeScreenshot(name: "03_ItemDetail")

            // iPhone: navigate back from detail
            // iPad: detail is shown in split view, no back needed
            if !isIPad {
                let navBar = app.navigationBars.firstMatch
                if navBar.waitForExistence(timeout: 3) {
                    navBar.buttons.firstMatch.tap()
                    Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                }
            }
        }

        // Tab 2 – Profile
        navigateToTabByIndex(2)
        sleep(1)
        try takeScreenshot(name: "04_Profile")
    }
}
```

### 4.3 Navigation System

#### iPhone Navigation

On iPhone, navigation uses the standard tab bar:

```swift
navigateToTabOnIPhone(_ index: Int)
```

1. Finds `app.tabBars.firstMatch`
2. Gets the button at `index`
3. Taps if hittable

#### iPad Navigation — 6 Strategies

iPadOS renders tabs differently depending on the OS version and `.tabViewStyle`. The base class implements 6 escalating strategies:

```
navigateToTabOnIPad(_ index: Int)
  │
  ├── Strategy 1: Standard tab bar
  │   ├── 1a: By index (direct button tap or coordinate fallback)
  │   └── 1b: By label (searches tab bar buttons by accessibility label)
  │
  ├── Strategy 2: TabSection container (iPadOS 18+ floating tab bar)
  │   └── Searches otherElements with identifier "TabSection"
  │
  ├── Strategy 3: Direct button search
  │   └── Searches all app.buttons by tabLabels(forIndex:)
  │
  ├── Strategy 4: Sidebar toggle + label search
  │   ├── Taps "ToggleSidebar" button
  │   ├── Searches static texts (coordinate tap to avoid edit mode)
  │   └── Searches buttons by label
  │
  ├── Strategy 5: Broad button scan
  │   └── Iterates ALL buttons, partial-matches against known labels
  │
  └── Strategy 6: Coordinate fallback
      └── Force-taps tab bar button at normalized offset (0.5, 0.5)
```

**Important:** Override `tabLabels(forIndex:)` in your subclass for reliable iPad navigation. Include all localized variants:

```swift
override func tabLabels(forIndex index: Int) -> [String] {
    switch index {
    case 0: return ["Home"]
    case 1: return ["Patches", "Beete"]      // English + German
    case 2: return ["Plants", "Pflanzen"]
    case 3: return ["About", "Über"]
    default: return []
    }
}
```

#### Automatic Edit Mode Recovery

Before every navigation attempt on iPad, `exitEditModeIfNeeded()` is called. This detects if a SwiftUI List is in edit mode (looking for "Done"/"Fertig" buttons) and exits it to prevent accidental reordering.

### 4.4 Screenshot Helpers

| Method | Returns | Description |
|--------|---------|-------------|
| `takeScreenshot(name:)` | `throws` | Save screenshot to disk + attach to Xcode test results |
| `navigateToTabByIndex(_:)` | `Void` | Auto-selects iPhone or iPad strategy |
| `navigateToTabByLabel(_:)` | `Bool` | Navigate by accessibility label array |
| `tapFirstHittableCell()` | `Bool` | Tap the first visible cell in a list |
| `tapPlusButton()` | `Bool` | Find and tap the add/plus button |
| `dismissSheet()` | `Void` | Dismiss current sheet/modal (4 strategies) |
| `ensureMainViewVisible()` | `Void` | Return to main tab view (dismiss modals) |
| `exitEditModeIfNeeded()` | `Void` | Exit list edit mode if active |
| `waitForHittable(_:timeout:)` | `Bool` | Wait for element to become tappable |
| `dismissSystemAlerts()` | `Void` | Dismiss OS permission dialogs |

#### Sheet Dismissal Strategies

`dismissSheet()` tries four approaches in order:

1. **xmark/close/cancel** button in the navigation bar
2. **Cancel/Close/Done** buttons anywhere (supports German: Abbrechen, Schließen, Fertig)
3. **Swipe-down gesture** (aggressive, from 15% to 99% of screen height)
4. **Tap outside** the sheet (on the dimmed background area)

### 4.5 App Integration

The test base injects four launch arguments. Your app must handle them:

| Argument | Purpose | Example Implementation |
|----------|---------|----------------------|
| `-UITEST` | App is running under UI test | Skip analytics, crash reporters |
| `-LOAD_MOCK_DATA` | Use screenshot mock data | Inject deterministic test data |
| `-DISABLE_ANIMATIONS` | Disable all animations | `UIView.setAnimationsEnabled(false)` |
| `-SKIP_ONBOARDING` | Skip onboarding flow | `UserDefaults.set(true, forKey: "hasSeenOnboarding")` |

```swift
// In your @main App struct:
init() {
    if CommandLine.arguments.contains("-DISABLE_ANIMATIONS") {
        UIView.setAnimationsEnabled(false)
    }
    if CommandLine.arguments.contains("-LOAD_MOCK_DATA") {
        ScreenshotMockDataProvider.loadMockData()
    }
    if CommandLine.arguments.contains("-SKIP_ONBOARDING") {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
    }
}
```

### 4.6 Mock Data

Use the template at `Templates/MockDataProviderExample.swift`:

1. Copy into your **main app target** (not UITest target)
2. Replace placeholder types with your data models
3. Fill in realistic, visually appealing sample data
4. Load the mock data when `-LOAD_MOCK_DATA` is detected

**Best practices:**
- Use realistic names, dates, and images
- Include enough items to fill the screen but not scroll endlessly
- Delete existing data before inserting mocks (prevents duplicates on re-runs)
- Set a default app theme that looks good in screenshots

---

## 5. Stage 2 — Test Execution

### 5.1 run_screenshots.sh

The shell script `Scripts/run_screenshots.sh` orchestrates the entire screenshot capture process. It boots simulators, runs `xcodebuild test` for each device/language combination, and collects the results.

#### Execution Flow

```
run_screenshots.sh
  │
  ├── Parse CLI arguments
  ├── Print banner with configuration
  │
  ├── For each DEVICE in devices:
  │   ├── For each LANG in languages:
  │   │   ├── Check if simulator is available
  │   │   ├── Try fallback devices if not found
  │   │   ├── Boot simulator
  │   │   ├── Remove existing .xcresult bundle
  │   │   ├── Run xcodebuild test
  │   │   │     -project <project>
  │   │   │     -scheme <scheme>
  │   │   │     -destination "platform=iOS Simulator,name=<device>,OS=latest"
  │   │   │     -testLanguage <lang>
  │   │   │     -only-testing:<target>/<class>/testTakeAllScreenshots
  │   │   │     -resultBundlePath <output>/<device>_<lang>.xcresult
  │   │   ├── Filter noisy build output (codesign, CompileC, etc.)
  │   │   ├── Show only test results
  │   │   └── Shutdown simulator
  │   │
  │   └── Track success/failure count
  │
  └── Print summary (successful/failed/output directory)
```

#### Build Output Filtering

The script pipes `xcodebuild` output through two `grep` stages:

1. **Exclude** noisy build lines: `codesign`, `CodeSign`, `CompileC`, `SwiftCompile`, `Ld`, `clang`, `MergeSwiftModule`, `Copy`, `Ditto`, etc.
2. **Include** only test-relevant output: `Test`, `Screenshot`, `Error`, `BUILD`, `FAIL`, `Passed`, and emoji markers (`📸`, `📱`, `✅`, `❌`)

### 5.2 CLI Options

| Flag | Default | Description |
|------|---------|-------------|
| `--project <path>` | `Plantner.xcodeproj` | Path to `.xcodeproj` |
| `--scheme <name>` | `Plantner` | Xcode scheme to build |
| `--test-target <name>` | `PlantnerUITests` | UITest bundle target |
| `--test-class <name>` | `PlantnerScreenshotTest` | XCTest class name |
| `--output <path>` | `screenshots/` | Output directory |
| `--devices <d1,d2,...>` | iPhone 17 Pro Max, iPhone 17 Pro, iPad Pro 13-inch (M5) | Comma-separated device list |
| `--languages <l1,l2,...>` | `en` | Comma-separated language codes |
| `--iphone-only` | — | Only iPhone devices |
| `--help`, `-h` | — | Show help |

### 5.3 Simulator Management

For each device/language combination, the script:

1. **Shuts down** any running instance of the simulator
2. **Waits** 2 seconds for clean shutdown
3. **Boots** the simulator
4. **Waits** 3 seconds for the simulator to be ready
5. **Runs** the test via `xcodebuild`
6. **Shuts down** the simulator after the test

### 5.4 Fallback Devices

If a requested simulator is not installed, the script automatically tries these fallbacks:

| Primary | Fallback |
|---------|----------|
| iPhone 17 Pro Max | iPhone 16 Pro Max → iPhone 14 Plus |
| iPhone 17 Pro | iPhone 16 Pro |
| iPad Pro 13-inch (M5) | iPad Pro 13-inch (M4) → iPad Pro (12.9-inch) (6th gen) |

### Output Structure

```
screenshots/
├── iPhone_17_Pro/
│   ├── iPhone_17_Pro_01_Home.png
│   ├── iPhone_17_Pro_02_Patches.png
│   ├── iPhone_17_Pro_03_PatchDetail.png
│   ├── iPhone_17_Pro_04_Plants.png
│   ├── iPhone_17_Pro_05_PlantDetail.png
│   └── iPhone_17_Pro_06_About.png
├── iPhone_17_Pro_Max/
│   └── ... (same naming pattern)
├── iPad_Pro_13-inch_(M5)/
│   └── ... (same naming pattern)
├── iPhone_17_Pro_en.xcresult        # Xcode test result bundle
├── iPhone_17_Pro_Max_en.xcresult
└── iPad_Pro_13-inch_(M5)_en.xcresult
```

---

## 6. Stage 3 — Mockup Composition

### 6.1 compose_mockup.swift

`Scripts/compose_mockup.swift` is a standalone Swift script (no dependencies beyond macOS system frameworks) that composites a screenshot into a device frame on a gradient background, producing an App Store-ready PNG.

#### Frameworks Used

- `Foundation` — File I/O, URL handling
- `AppKit` — NSImage loading, NSColor
- `CoreGraphics` — CGContext rendering, CGImage manipulation
- `UniformTypeIdentifiers` — UTType.png for image export

### 6.2 Device Frame Requirements

> **Important:** Device frame PNGs are **not included** in this package. You must obtain them yourself and place them into **your project's repository** (e.g. in a `Files/` folder). Download them from [Apple Design Resources](https://developer.apple.com/design/resources/) (official, free) or create your own in Figma/Sketch.

The script supports two types of device frame PNGs:

#### Type A: Frame with transparent screen area (recommended)

The screen area in the frame is fully transparent (alpha = 0). The device bezel, buttons, notch/Dynamic Island are opaque.

```
┌──────────────────────┐
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│  ← Opaque bezel (outer)
│▓▓┌────────────────┐▓▓│
│▓▓│                │▓▓│  ← Transparent screen area (alpha = 0)
│▓▓│   (alpha = 0)  │▓▓│
│▓▓│                │▓▓│
│▓▓└────────────────┘▓▓│
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
└──────────────────────┘
```

**Detection method:** Edge-scan from outside inward, looking for the transition pattern `transparent → opaque bezel → transparent screen`. Scans at x = width/4 to avoid the notch/Dynamic Island.

#### Type B: Frame with black screen area

The screen area is filled with opaque black pixels (R=0, G=0, B=0, A=255).

**Detection method:** Center-scan outward, looking for where non-black pixels start.

### 6.3 Screen Area Detection

The `detectScreenRect(in:)` function finds the screen area within the device frame:

```
detectScreenRect(in: CGImage) → CGRect?
  │
  ├── Strategy 1: Transparent screen area (edge-scan)
  │   │
  │   ├── Scan from TOP at x = w/4:
  │   │     transparent pixels → opaque bezel → transparent screen (= screenTop)
  │   │
  │   ├── Scan from BOTTOM at x = w/4:
  │   │     transparent → opaque → transparent (= screenBottom)
  │   │
  │   ├── Scan from LEFT at y = h/2:
  │   │     transparent → opaque → transparent (= screenLeft)
  │   │
  │   ├── Scan from RIGHT at y = h/2:
  │   │     transparent → opaque → transparent (= screenRight)
  │   │
  │   └── Validate: width > w/3 AND height > h/3
  │
  └── Strategy 2: Black screen area (center-scan)
      │
      ├── Check if center pixel is black (R,G,B < 10)
      ├── Scan outward in all 4 directions until non-black pixel found
      └── Validate: width > w/3 AND height > h/3
```

**Why scan at x = w/4?**  
Modern iPhones have a notch or Dynamic Island in the center-top of the frame. Scanning at the center (x = w/2) would hit the notch's opaque pixels and incorrectly shrink the detected screen area. Scanning at x = w/4 (left quarter) avoids the notch entirely.

### 6.4 Compositing Pipeline

```
composeMockup(config:)
  │
  ├── Load frame PNG and screenshot PNG
  │
  ├── Calculate frame rect on canvas:
  │   │  frameRect(frameSize, canvasSize, minMargin)
  │   │
  │   │  Available area = canvas - 2×margin
  │   │  Scale = min(availableW/frameW, availableH/frameH)  ← aspect-fit
  │   │  Center horizontally and vertically
  │   └── Result: CGRect for where the frame goes on the canvas
  │
  ├── Detect screen area in frame (native pixels):
  │   │  detectScreenRect(in: frameCGImage)
  │   └── Result: CGRect in frame-local coordinates
  │
  ├── Map screen rect from frame space to canvas space:
  │   │  mapRectToCanvas(screenRect, frameNativeSize, frameRectOnCanvas)
  │   │
  │   │  scaleX = canvasFrameW / nativeFrameW
  │   │  scaleY = canvasFrameH / nativeFrameH
  │   │  canvasX = frameOriginX + screenX × scaleX
  │   │  canvasY = frameOriginY + screenY × scaleY
  │   └── Result: CGRect for where the screenshot goes on the canvas
  │
  ├── Create CGContext (premultiplied alpha, sRGB)
  │
  ├── Convert rects from top-left to bottom-left origin:
  │   │  flipY(rect) → CGRect(x, canvasHeight - y - height, w, h)
  │   │
  │   │  CGContext uses bottom-left origin (Core Graphics convention)
  │   │  detectScreenRect returns top-left origin (image scanning convention)
  │   └── Both the frame rect and screen rect must be flipped
  │
  ├── Calculate corner radius:
  │   │  iPhone: screenWidth × 0.15 (15%)
  │   └── iPad:  screenWidth × 0.02 (2%)
  │
  ├── Draw layers (back to front):
  │   │
  │   │  1. GRADIENT BACKGROUND
  │   │     Linear gradient fills entire canvas
  │   │     Angle-based start/end points calculated from canvas diagonal
  │   │
  │   │  2. SCREENSHOT (with rounded corner clipping)
  │   │     saveGState()
  │   │     Create CGPath(roundedRect:) with device-specific corner radius
  │   │     Clip to rounded rect
  │   │     Draw screenshot into screen rect
  │   │     restoreGState()
  │   │
  │   └── 3. DEVICE FRAME
  │         Draw frame on top — transparency lets screenshot show through
  │         Frame covers the screenshot edges with its bezel
  │
  ├── Flatten to opaque PNG:
  │   │  Create second CGContext (noneSkipLast = no alpha)
  │   │  Draw composited image into opaque context
  │   └── App Store requires opaque PNGs (no alpha channel)
  │
  └── Export via CGImageDestination (UTType.png)
```

#### Why two CGContexts?

1. **First context** (premultiplied alpha): Needed for correct compositing of the transparent frame over the screenshot and gradient. Without alpha, the frame's transparent areas would show as black.

2. **Second context** (opaque): App Store Connect rejects PNGs with an alpha channel. The final image is re-rendered into an opaque context to strip the alpha.

### 6.5 Apple Device Presets

The script includes built-in presets for all App Store Connect screenshot sizes:

| Preset | Display | Resolution (portrait) | Status |
|--------|---------|----------------------|--------|
| `iphone69` | 6.9" (iPhone 16 Plus/Pro Max) | 1320 × 2868 | ⭐ **Required** |
| `iphone65` | 6.5" (iPhone 14 Plus/13 Pro Max) | 1242 × 2688 | Optional |
| `iphone61` | 6.1" (iPhone 16/15/14) | 1179 × 2556 | Optional |
| `iphone55` | 5.5" (iPhone 8 Plus) | 1242 × 2208 | Legacy |
| `iphone47` | 4.7" (iPhone SE 3rd gen) | 750 × 1334 | Legacy |
| `ipad13` | 13" (iPad Pro 13") | 2064 × 2752 | ⭐ **Required** |
| `ipad11` | 11" (iPad Pro 11"/Air 11") | 1668 × 2388 | Optional |
| `ipad105` | 10.5" (iPad Pro 10.5") | 1668 × 2224 | Legacy |
| `ipad97` | 9.7" (iPad/mini) | 1536 × 2048 | Legacy |

### 6.6 CLI Reference

```
swift compose_mockup.swift --frame <frame.png> --screenshot <screen.png> --output <out.png> [options]
```

#### Required Arguments

| Flag | Description |
|------|-------------|
| `--frame` | Device frame PNG (with transparent or black screen area) |
| `--screenshot` | App screenshot PNG |
| `--output` | Output file path (.png) |

#### Optional Arguments

| Flag | Default | Description |
|------|---------|-------------|
| `--device` | `iphone69` | Device preset (determines canvas size) |
| `--landscape` | — | Use landscape orientation |
| `--gradient-start` | `#667EEA` | Start color (hex) |
| `--gradient-end` | `#764BA2` | End color (hex) |
| `--angle` | `135` | Gradient angle in degrees |
| `--margin` | `30` | Minimum margin around frame in pixels |
| `--screen-rect` | auto-detect | Manual x,y,w,h in canvas pixels |
| `--canvas-size` | from preset | Override w,h pixels |

#### Examples

```bash
# iPhone mockup (default preset)
swift compose_mockup.swift \
  --frame "iPhone 17 Pro - Silver - Portrait.png" \
  --screenshot screenshots/iPhone_17_Pro/iPhone_17_Pro_01_Home.png \
  --output mockup.png

# iPad mockup
swift compose_mockup.swift \
  --frame "iPad Pro 13 - M4 - Silver - Portrait.png" \
  --screenshot "screenshots/iPad_Pro_13-inch_(M5)/iPad_Pro_13-inch_(M5)_01_Home.png" \
  --output mockup_ipad.png \
  --device ipad13 \
  --margin 70

# Custom gradient
swift compose_mockup.swift \
  --frame frame.png \
  --screenshot screen.png \
  --output mockup.png \
  --gradient-start '#79b474' \
  --gradient-end '#1f881b' \
  --angle 135
```

---

## 7. Stage 4 — Wrapper Script

The wrapper script (`capture_app_screenshots.sh`) combines stages 2 and 3 into a single command. It is project-specific and configured with all paths, device mappings, and design settings.

### Configuration

```bash
# Device frames
IPHONE_FRAME="$PROJECT_ROOT/Files/iPhone 17 Pro - Silver - Portrait.png"
IPAD_FRAME="$PROJECT_ROOT/Files/iPad Pro 13 - M4 - Silver - Portrait.png"

# Gradient colors
GRADIENT_START="#79b474"
GRADIENT_END="#1f881b"

# Device mapping: folder_name | compose_preset | frame_path | margin
DEVICES=(
    "iPhone_17_Pro|iphone69|$IPHONE_FRAME|30"
    "iPad_Pro_13-inch_(M5)|ipad13|$IPAD_FRAME|70"
)
```

### Execution Modes

```bash
# Full pipeline: capture screenshots + generate mockups
./scripts/capture_app_screenshots.sh

# Only generate mockups from existing screenshots
./scripts/capture_app_screenshots.sh --mockups-only

# iPhone only
./scripts/capture_app_screenshots.sh --iphone-only

# Multiple languages
./scripts/capture_app_screenshots.sh --languages "en,de"
```

### Mockup Generation Loop

The wrapper iterates over every device configuration and every screenshot:

```
For each DEVICE in DEVICES:
  │
  ├── Parse: folder_name | preset | frame_path | margin
  ├── Find all *.png in screenshots/<folder_name>/
  │
  └── For each screenshot:
      └── swift compose_mockup.swift \
            --frame <frame_path> \
            --screenshot <screenshot_path> \
            --output "Appstore Mockups/<folder_name>/<filename>" \
            --device <preset> \
            --margin <margin> \
            --gradient-start "#79b474" \
            --gradient-end "#1f881b"
```

---

## 8. Integration Example (Plantner)

### Project Structure

```
Plantner/
├── Plantner.xcodeproj
├── Plantner/                          # Main app target
│   ├── PlantnerApp.swift              # Handles launch arguments
│   └── Domain/MockObjects/            # Mock data provider
├── PlantnerUITests/
│   └── PlantnerScreenshotTest.swift   # Subclass of ScreenshotTestBase
├── Files/
│   ├── iPhone 17 Pro - Silver - Portrait.png   # iPhone device frame
│   └── iPad Pro 13 - M4 - Silver - Portrait.png # iPad device frame
├── scripts/
│   └── capture_plantner_screenshots.sh  # Wrapper script
├── screenshots/                        # Raw screenshots (auto-generated)
├── Appstore Mockups/                   # Final mockups (auto-generated)
│   ├── iPhone_17_Pro/
│   └── iPad_Pro_13-inch_(M5)/
└── ios-screenshot-automator/           # Package dependency
```

### PlantnerScreenshotTest

Key implementation details:

- **Custom `setUp()`**: Overrides `screenshotsURL` to save screenshots to `<project_root>/screenshots/<device>/` instead of the package's default location
- **`tabLabels(forIndex:)`**: Returns both English and German labels for each tab (`["Patches", "Beete"]`, `["Plants", "Pflanzen"]`, etc.)
- **`captureAllScreens()`**: Captures 6 screenshots per device (Home, Patches, PatchDetail, Plants, PlantDetail, About)
- **`tapFirstDataCell()`**: Custom helper that skips the "Add" button at index 0 and taps the first actual data cell at index 1
- **iPad awareness**: Skips back-button navigation on iPad (detail shown in split view)

### Generated Output

```
Appstore Mockups/
├── iPhone_17_Pro/
│   ├── iPhone_17_Pro_01_Home.png          (1320×2868)
│   ├── iPhone_17_Pro_02_Patches.png       (1320×2868)
│   ├── iPhone_17_Pro_03_PatchDetail.png   (1320×2868)
│   ├── iPhone_17_Pro_04_Plants.png        (1320×2868)
│   ├── iPhone_17_Pro_05_PlantDetail.png   (1320×2868)
│   └── iPhone_17_Pro_06_About.png         (1320×2868)
└── iPad_Pro_13-inch_(M5)/
    ├── iPad_Pro_13-inch_(M5)_01_Home.png          (2064×2752)
    ├── iPad_Pro_13-inch_(M5)_02_Patches.png       (2064×2752)
    ├── iPad_Pro_13-inch_(M5)_03_PatchDetail.png   (2064×2752)
    ├── iPad_Pro_13-inch_(M5)_04_Plants.png        (2064×2752)
    ├── iPad_Pro_13-inch_(M5)_05_PlantDetail.png   (2064×2752)
    └── iPad_Pro_13-inch_(M5)_06_About.png         (2064×2752)
```

---

## 9. Apple App Store Requirements

> Source: [App Store Connect — Screenshot Specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications)

### Mandatory Screenshots

| Device Category | Display Size | Resolution | Minimum |
|----------------|--------------|------------|---------|
| iPhone | 6.9" or 6.5" | 1320×2868 or 1242×2688 | **1 required** |
| iPad (if iPad app) | 13" or 12.9" | 2064×2752 or 2048×2732 | **1 required** |

### Screenshot Rules

- **Format:** PNG or JPEG (PNG recommended for quality)
- **Alpha channel:** Not allowed — must be opaque
- **Minimum:** 1 screenshot per mandatory size
- **Maximum:** 10 screenshots per size per localization
- **Orientation:** Portrait or landscape (must match the submitted resolution)
- **Scaling:** Apple auto-scales 6.9" screenshots for the 6.5" slot (submitting both is recommended)

### Recommended Sizes (Optional)

| Device | Display | Resolution |
|--------|---------|------------|
| iPhone 17 Pro | 6.3" | 1206×2622 |
| iPhone 16e | 6.1" | 1080×2340 |
| iPhone 14 Plus | 6.5" | 1284×2778 |
| iPad Air 13" (M3) | 11" | 1668×2388 |

---

## 10. File Reference

### Source Files

| File | Location | Description |
|------|----------|-------------|
| `ScreenshotTestBase.swift` | `Sources/` | XCUITest base class with navigation, screenshots, and helpers (768 lines) |
| `ScreenshotComposer.swift` | `Sources/` | Screenshot composition with gradient backgrounds and device frames (363 lines) |
| `compose_mockup.swift` | `Scripts/` | Standalone Swift script for mockup composition (~490 lines) |
| `run_screenshots.sh` | `Scripts/` | Shell script for multi-device test orchestration (298 lines) |
| `Package.swift` | Root | SPM package definition |

### Support Files

| File | Location | Description |
|------|----------|-------------|
| `ExampleScreenshotTest.swift` | `Examples/` | Example subclass for a fictional 3-tab app |
| `MockDataProviderExample.swift` | `Templates/` | Template for mock data injection |

### Generated Artifacts

| Directory | Contents |
|-----------|----------|
| `screenshots/<device>/` | Raw PNG screenshots from simulators |
| `screenshots/<device>_<lang>.xcresult` | Xcode test result bundles |
| `Appstore Mockups/<device>/` | Final composited mockup PNGs |

---

## 11. Troubleshooting

### Screenshot Capture Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| Simulator not found | Simulator runtime not installed | Install via Xcode → Settings → Platforms, or rely on fallback devices |
| Tab not hittable on iPad | Missing `tabLabels(forIndex:)` | Override in your subclass with all localized tab names |
| Screenshots saved to wrong location | `#file` path mismatch | Override `setUp()` and set `screenshotsURL` manually |
| Stuck in edit mode | SwiftUI list enters edit mode on navigation | `exitEditModeIfNeeded()` handles this automatically |
| Sheet not dismissing | Custom close button not recognized | Override `dismissSheet()` in your subclass |
| `ScreenshotTestBase` not found | File not in UITest target | Check Target Membership in Xcode's File Inspector (⌥⌘1) |
| Mock data duplicated | Mock data added on every launch | Delete existing data before inserting mocks |

### Mockup Composition Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| Image upside down | Coordinate system mismatch | Rects are flipped from top-left to bottom-left via `flipY()` |
| Screenshot corners visible | Corner radius too small | Increase `cornerRadiusFactor` (default: 15% iPhone, 2% iPad) |
| Screen area not detected | Frame has no transparent or black area | Use `--screen-rect` to specify manually |
| Transparent gap around notch | Detection stopped at notch pixels | Edge-scan at x=w/4 avoids the notch area |
| Wrong canvas size | Missing `--device` flag | Always specify `--device ipad13` for iPad frames |
| Alpha channel in output | — | Script automatically flattens to opaque PNG in second pass |
| `kUTTypePNG` deprecated | macOS 12+ | Use `UTType.png.identifier` with `import UniformTypeIdentifiers` |
| Compiler type-check timeout | Complex expression in `hexToNSColor` | Break into sub-expressions with explicit type annotations |

### Script Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| `xcodebuild: error: project does not exist` | Wrong relative path | Script resolves `PROJECT_ROOT` from its own location via `$SCRIPT_DIR/..` |
| `Existing file at -resultBundlePath` | Previous result bundle exists | Script deletes existing `.xcresult` with `rm -rf` before each run |
| `scheme not found` | Wrong scheme name | Use `xcodebuild -list` to find correct scheme names |
| Noisy build output | xcodebuild verbose logging | Build output is filtered via `grep -v` (excludes codesign, CompileC, etc.) |
