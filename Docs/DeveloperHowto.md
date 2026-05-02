# Developer How-To Guide

## Getting Started with `ios-screenshot-automator`

This guide walks you through integrating the screenshot & mockup pipeline into your own iOS project — from zero to fully automated App Store screenshots.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Installation](#2-installation)
3. [Step-by-Step Setup](#3-step-by-step-setup)
   - [Step 1: Add the Package](#step-1-add-the-package)
   - [Step 2: Create Your Screenshot Test](#step-2-create-your-screenshot-test)
   - [Step 3: Prepare Your App for Testing](#step-3-prepare-your-app-for-testing)
   - [Step 4: Add Mock Data](#step-4-add-mock-data)
   - [Step 5: Add Device Frames](#step-5-add-device-frames)
   - [Step 6: Copy the Template Script](#step-6-copy-the-template-script)
   - [Step 7: Run It](#step-7-run-it)
4. [Usage Modes](#4-usage-modes)
5. [Customization](#5-customization)
   - [Gradient Background](#gradient-background)
   - [Device Frames & Margins](#device-frames--margins)
   - [Corner Radius](#corner-radius)
   - [Timing & Delays](#timing--delays)
   - [Languages](#languages)
   - [Screenshot Directory](#screenshot-directory)
6. [Adding More Screens](#6-adding-more-screens)
7. [iPad Support](#7-ipad-support)
8. [Template Script Reference](#8-template-script-reference)
9. [CI/CD Integration](#9-cicd-integration)
10. [FAQ](#10-faq)

---

## 1. Prerequisites

Before you start, make sure you have:

| Requirement | Minimum | Check with |
|-------------|---------|------------|
| Xcode | 15.0 | `xcodebuild -version` |
| Swift | 5.9 | `swift --version` |
| macOS | 13 Ventura | Apple menu → About This Mac |
| iOS Simulators | iOS 16+ | Xcode → Settings → Platforms |
| bash | 3.2+ (ships with macOS) | `bash --version` |

### Required Simulators

Install at least the **mandatory** simulators for App Store Connect:

| Simulator | Display Size | Status |
|-----------|-------------|--------|
| iPhone 17 Pro Max (or iPhone 16 Pro Max) | 6.9" | ⭐ **Required** |
| iPad Pro 13-inch (M5 or M4) | 13" | ⭐ **Required** (if iPad app) |
| Apple TV 4K (3rd generation) (at 1080p) | 1920×1080 | ⭐ **Required** (if tvOS app) |

**Optional but recommended:**
- iPhone 17 Pro (6.3") — for the secondary iPhone slot
- iPad Air 13-inch (11") — for the secondary iPad slot

### Device Frame PNGs

You need device frame images with a **transparent screen area**. Download them from:

- [Apple Design Resources](https://developer.apple.com/design/resources/) (official, free)
- Create your own in Figma/Sketch (export as PNG with transparency)

> **Important:** The frame PNG must have the screen area as fully transparent pixels (alpha = 0). The script auto-detects this area. Frames with a black screen area also work but transparent is preferred.

---

## 2. Installation

### Option A: Swift Package Manager (recommended)

Add the package to your Xcode project:

1. In Xcode, go to **File → Add Package Dependencies…**
2. Enter the repository URL:
   ```
   https://github.com/matthias-karl/ios-screenshot-automator.git
   ```
3. Select version rule (e.g., **Up to Next Major Version** from `1.0.0`)
4. Add **`ScreenshotAutomator`** to your **UITest target** (not the main app target)

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/matthias-karl/ios-screenshot-automator.git", from: "1.0.0")
],
targets: [
    .testTarget(
        name: "MyAppUITests",
        dependencies: [
            .product(name: "ScreenshotAutomator", package: "ios-screenshot-automator")
        ]
    )
]
```

### Option B: Local Package (for development)

Clone the repository into your project directory:

```bash
cd /path/to/MyApp
git clone https://github.com/matthias-karl/ios-screenshot-automator.git
```

Then add it as a local package in Xcode:
1. **File → Add Package Dependencies… → Add Local…**
2. Select the `ios-screenshot-automator` folder
3. Add `ScreenshotAutomator` to your UITest target

### Option C: File Copy (no package manager)

Copy the single source file directly:

```bash
cp ios-screenshot-automator/Sources/ScreenshotTestBase.swift MyAppUITests/
```

Add it to your UITest target in Xcode (File Inspector → Target Membership).

---

## 3. Step-by-Step Setup

### Step 1: Add the Package

Follow the [Installation](#2-installation) instructions above.

Verify the import works in your UITest target:

```swift
import XCTest
import ScreenshotAutomator  // ← This should compile without errors

class TestImport: XCTestCase {
    func testPackageAvailable() {
        // If this compiles, the package is correctly linked
        let _ = ScreenshotTestConfig.targetDevices
        XCTAssertTrue(true)
    }
}
```

### Step 2: Create Your Screenshot Test

Create a new Swift file in your UITest target (e.g., `MyAppScreenshotTest.swift`):

```swift
import XCTest
import ScreenshotAutomator

final class MyAppScreenshotTest: ScreenshotTestBase {

    // MARK: - Setup (optional)

    override func setUp() {
        super.setUp()

        // Override screenshot output directory (recommended)
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()   // MyAppUITests/
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

    // MARK: - Tab Labels (required for iPad)

    override func tabLabels(forIndex index: Int) -> [String] {
        switch index {
        case 0: return ["Home"]
        case 1: return ["Items", "Einträge"]       // Add all localizations
        case 2: return ["Settings", "Einstellungen"]
        default: return []
        }
    }

    // MARK: - Screenshot Capture

    override func captureAllScreens() throws {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        // Screen 1: Home
        navigateToTabByIndex(0)
        sleep(1)
        try takeScreenshot(name: "01_Home")

        // Screen 2: Items list
        navigateToTabByIndex(1)
        sleep(1)
        try takeScreenshot(name: "02_Items")

        // Screen 3: Item detail — tap first data cell (skip "Add" button at index 0)
        let cells = app.cells.allElementsBoundByIndex
        if cells.count > 1, cells[1].exists {
            cells[1].tap()
            sleep(1)
            try takeScreenshot(name: "03_ItemDetail")

            // Navigate back (iPhone only — iPad shows detail in split view)
            if !isIPad {
                let navBar = app.navigationBars.firstMatch
                if navBar.waitForExistence(timeout: 3) {
                    navBar.buttons.firstMatch.tap()
                    Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
                }
            }
        }

        // Screen 4: Settings
        navigateToTabByIndex(2)
        sleep(1)
        try takeScreenshot(name: "04_Settings")
    }
}
```

### Step 3: Prepare Your App for Testing

In your app's entry point (e.g., `MyApp.swift` or `AppDelegate.swift`), handle the launch arguments:

```swift
import SwiftUI

@main
struct MyApp: App {

    init() {
        let args = CommandLine.arguments

        // Disable animations for stable screenshots
        if args.contains("-DISABLE_ANIMATIONS") {
            UIView.setAnimationsEnabled(false)
        }

        // Load mock data instead of real data
        if args.contains("-LOAD_MOCK_DATA") {
            MyMockDataProvider.loadMockData()
        }

        // Skip onboarding/tutorial screens
        if args.contains("-SKIP_ONBOARDING") {
            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Step 4: Add Mock Data

Create a mock data provider in your **main app target**:

```swift
// MyMockDataProvider.swift (in main app target, NOT UITest target)

import Foundation

struct MyMockDataProvider {

    static func loadMockData() {
        // Delete existing data first (prevents duplicates on re-runs)
        DataStore.shared.deleteAll()

        // Insert realistic-looking mock data
        DataStore.shared.items = [
            Item(name: "Tomatoes",  description: "Fresh cherry tomatoes", icon: "🍅"),
            Item(name: "Basil",     description: "Sweet Genovese basil",  icon: "🌿"),
            Item(name: "Peppers",   description: "Mixed bell peppers",    icon: "🫑"),
        ]

        DataStore.shared.categories = [
            Category(name: "Vegetables", color: .green),
            Category(name: "Herbs",      color: .mint),
        ]
    }
}
```

> **Tip:** Use data that looks realistic and fills the screen nicely. 3–5 items per list is usually ideal for screenshots.

### Step 5: Add Device Frames

1. Download device frame PNGs (see [Prerequisites](#1-prerequisites))
2. Place them in a folder in your project (e.g., `Files/`):

```
MyApp/
├── Files/
│   ├── iPhone 17 Pro - Silver - Portrait.png
│   └── iPad Pro 13 - M4 - Silver - Portrait.png
```

> **Requirements for frame PNGs:**
> - Must have a **transparent screen area** (alpha = 0)
> - Should include the device bezel, buttons, notch/Dynamic Island
> - Any resolution works — the script scales automatically

### Step 6: Copy the Template Script

Copy the template script into your project and fill in the `← CHANGE` fields:

```bash
mkdir -p scripts
cp path/to/ios-screenshot-automator/Templates/capture_screenshots_template.sh \
    scripts/capture_screenshots.sh
chmod +x scripts/capture_screenshots.sh
```

See the [template header](../Templates/capture_screenshots_template.sh) for the full field reference, or the [inline template below](#8-template-script-reference).

### Step 7: Run It

```bash
# Full pipeline: capture screenshots + generate mockups
./scripts/capture_screenshots.sh

# Only generate mockups from existing screenshots (much faster)
./scripts/capture_screenshots.sh --mockups-only

# iPhone screenshots only (skip iPad)
./scripts/capture_screenshots.sh --iphone-only
```

**Expected output:**

```
╔══════════════════════════════════════════════════════════╗
║  📸  Step 1: Capturing Screenshots                      ║
╚══════════════════════════════════════════════════════════╝

📱 iPhone 17 Pro  |  🌐 en
✅ Done: iPhone 17 Pro (en)

📱 iPad Pro 13-inch (M5)  |  🌐 en
✅ Done: iPad Pro 13-inch (M5) (en)

╔══════════════════════════════════════════════════════════╗
║  🖼️  Step 2: Generating App Store Mockups                ║
╚══════════════════════════════════════════════════════════╝

📱 Processing: iPhone_17_Pro (preset: iphone69, margin: 30px)
   🖼️  iPhone_17_Pro_01_Home.png → ✅ Saved  [1320×2868 px]
   🖼️  iPhone_17_Pro_02_Items.png → ✅ Saved  [1320×2868 px]
   ...

╔══════════════════════════════════════════════════════════╗
║  ✅  Done!                                               ║
║  📸  Mockups generated: 12                              ║
║  📂  Output folder:     Appstore Mockups/               ║
╚══════════════════════════════════════════════════════════╝
```

---

## 4. Usage Modes

The template script (your local `scripts/capture_screenshots.sh`) supports several execution modes:

### Full Pipeline (default)

Captures screenshots on simulators, then generates mockups:

```bash
./scripts/capture_screenshots.sh
```

### Mockups Only

Skip screenshot capture, generate mockups from existing screenshots. Useful when you've already captured screenshots and want to tweak the gradient, margin, or frame:

```bash
./scripts/capture_screenshots.sh --mockups-only
```

### iPhone Only

Skip iPad simulators (faster for iPhone-only apps):

```bash
./scripts/capture_screenshots.sh --iphone-only
```

### Multiple Languages

Generate screenshots in multiple languages:

```bash
./scripts/capture_screenshots.sh --languages "en,de,fr,es"
```

### Compose Single Mockup

Use `compose_mockup.swift` directly for a single image:

```bash
swift ios-screenshot-automator/Scripts/compose_mockup.swift \
    --frame "Files/iPhone 17 Pro - Silver - Portrait.png" \
    --screenshot screenshots/iPhone_17_Pro/iPhone_17_Pro_01_Home.png \
    --output single_mockup.png \
    --gradient-start '#FF6B6B' \
    --gradient-end '#4ECDC4' \
    --margin 50
```

### Run Screenshot Tests Directly (advanced)

If you only need raw screenshots without mockups, you can call `run_screenshots.sh` directly from the SPM checkout. Normally the template script handles this for you — use this only for debugging or CI customisation:

```bash
ios-screenshot-automator/Scripts/run_screenshots.sh \
    --project MyApp.xcodeproj \
    --scheme MyApp \
    --test-target MyAppUITests \
    --test-class MyAppScreenshotTest \
    --output screenshots \
    --devices "iPhone 17 Pro,iPad Pro 13-inch (M5)" \
    --languages "en"
```

---

## 5. Customization

### Gradient Background

Set gradient colors and angle in the template script:

```bash
GRADIENT_START="#667EEA"    # Top/left color (hex)
GRADIENT_END="#764BA2"      # Bottom/right color (hex)
```

Or pass to `compose_mockup.swift` directly:

```bash
--gradient-start '#FF6B6B' --gradient-end '#4ECDC4' --angle 120
```

**Popular gradient combinations:**

| Name | Start | End | Preview |
|------|-------|-----|---------|
| Purple Haze | `#667EEA` | `#764BA2` | Purple → Deep Purple |
| Meadow | `#79b474` | `#1f881b` | Light Green → Dark Green |
| Sunset | `#FF6B6B` | `#FFA500` | Coral → Orange |
| Ocean | `#2193b0` | `#6dd5ed` | Deep Blue → Light Blue |
| Midnight | `#232526` | `#414345` | Dark Gray → Gray |
| Coral Reef | `#FF6B6B` | `#4ECDC4` | Coral → Teal |

The gradient angle (default: `135°`) controls the direction:
- `0°` → left to right
- `90°` → bottom to top
- `135°` → top-left to bottom-right (default)
- `180°` → right to left

### Device Frames & Margins

Each device entry in the template script has four fields:

```bash
# Format: folder_name | device_preset | frame_path | margin_px
DEVICES=(
    "iPhone_17_Pro|iphone69|$IPHONE_FRAME|30"
    "iPad_Pro_13-inch_(M5)|ipad13|$IPAD_FRAME|70"
    # "Apple_TV_4K_(3rd_generation)_(at_1080p)|appletv|$APPLETV_FRAME|30"
)
```

| Field | Description |
|-------|-------------|
| `folder_name` | Subfolder name in `screenshots/` (must match simulator output) |
| `device_preset` | Canvas size preset (see table below) |
| `frame_path` | Path to device frame PNG |
| `margin_px` | Minimum pixel margin around the frame on the canvas |

**Available device presets:**

| Preset | Canvas Size | Use For |
|--------|------------|---------|
| `iphone69` | 1320×2868 | iPhone 17/16 Pro Max, Plus models |
| `iphone65` | 1242×2688 | iPhone 14 Plus, 13 Pro Max |
| `iphone61` | 1179×2556 | iPhone 16, 15, 14 |
| `iphone55` | 1242×2208 | iPhone 8 Plus |
| `ipad13` | 2064×2752 | iPad Pro 13" |
| `ipad11` | 1668×2388 | iPad Pro 11", Air 11" |
| `appletv` | 1920×1080 | Apple TV 4K |

### Corner Radius

The screenshot is clipped with rounded corners so it fits inside the device frame's screen area. The radius is device-specific:

| Device Type | Corner Radius | Visual |
|-------------|--------------|--------|
| iPhone | 15% of screen width | Matches iPhone's rounded display |
| iPad | 2% of screen width | Subtle rounding for iPad's flatter corners |
| Apple TV | 1% of screen width | Minimal rounding for TV display |

To change the corner radius, edit `compose_mockup.swift`:

```swift
// In composeMockup(), find:
switch config.device {
case .ipad13, .ipad11, .ipad105, .ipad97:
    cornerRadiusFactor = 0.02    // ← Change iPad radius here
case .appletv:
    cornerRadiusFactor = 0.01    // ← Change Apple TV radius here
default:
    cornerRadiusFactor = 0.15    // ← Change iPhone radius here
}
```

### Timing & Delays

Override timing constants in your screenshot test subclass:

```swift
final class MyAppScreenshotTest: ScreenshotTestBase {
    // Longer delays for apps with complex animations
    override class var initialDelay: TimeInterval { 5.0 }
    override class var navigationDelay: TimeInterval { 2.5 }
    override class var animationDelay: TimeInterval { 1.0 }
    override class var sheetDelay: TimeInterval { 1.5 }
}
```

### Languages

Pass language codes to capture localized screenshots:

```bash
# In the template script:
--languages "en,de,fr"

# Or directly:
./scripts/capture_screenshots.sh --languages "en,de"
```

Each language creates a separate simulator run. Screenshots are saved per-device (the language is part of the `.xcresult` bundle name).

### Screenshot Directory

Override `screenshotsURL` in your subclass to control where screenshots are saved:

```swift
override func setUp() {
    super.setUp()

    // Save to a custom location
    screenshotsURL = URL(fileURLWithPath: "/tmp/my-app-screenshots")
        .appendingPathComponent(UIDevice.current.name
            .replacingOccurrences(of: " ", with: "_"))

    try? FileManager.default.createDirectory(
        at: screenshotsURL, withIntermediateDirectories: true
    )
}
```

---

## 6. Adding More Screens

### List + Detail Pattern

```swift
// Navigate to a list tab
navigateToTabByIndex(1)
sleep(1)
try takeScreenshot(name: "02_ItemList")

// Tap first data cell (index 1, skipping "Add" button at index 0)
let cells = app.cells.allElementsBoundByIndex
if cells.count > 1, cells[1].exists {
    cells[1].tap()
    sleep(1)
    try takeScreenshot(name: "03_ItemDetail")

    // Navigate back (iPhone only — iPad shows detail in split view)
    if !isIPad {
        let navBar = app.navigationBars.firstMatch
        if navBar.waitForExistence(timeout: 3) {
            navBar.buttons.firstMatch.tap()
            Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
        }
    }
}
```

> **Tip:** If your list doesn't have an "Add" button at the top, you can also use the
> built-in `tapFirstHittableCell()` helper, which taps the first visible cell at index 0.

### Sheet / Modal Pattern

```swift
// Open a sheet
if tapPlusButton() {
    try takeScreenshot(name: "04_AddItem")
    dismissSheet()
}
```

### Custom Button Tap

```swift
// Tap a specific button by accessibility label
let button = app.buttons["Show QR Code"]
if button.waitForExistence(timeout: 3) && button.isHittable {
    button.tap()
    sleep(1)
    try takeScreenshot(name: "05_QRCode")
}
```

### Scroll Down Before Screenshot

```swift
navigateToTabByIndex(2)
let scrollView = app.scrollViews.firstMatch
scrollView.swipeUp()
sleep(1)
try takeScreenshot(name: "06_ScrolledContent")
```

---

## 7. iPad Support

### Why iPad Is Different

On iPad, SwiftUI renders tabs differently depending on the OS version and `tabViewStyle`:

| iPadOS Version | `.automatic` | `.sidebarAdaptable` |
|---------------|-------------|---------------------|
| 17 | Bottom tab bar | Sidebar |
| 18+ | Floating top tab bar | Floating top tab bar + sidebar toggle |

The base class handles all variants automatically via 6 escalating strategies. **You just need to provide tab labels.**

### Required: Override `tabLabels(forIndex:)`

```swift
override func tabLabels(forIndex index: Int) -> [String] {
    switch index {
    case 0: return ["Home"]
    case 1: return ["Patches", "Beete"]         // Include ALL localizations
    case 2: return ["Plants", "Pflanzen"]
    case 3: return ["About", "Über"]
    default: return []
    }
}
```

> **Important:** The labels must exactly match the text used in your SwiftUI `Tab("Label", ...)` or `.tabItem { Label("Label", ...) }`. Include every localized variant.

### iPad Detail Views

On iPad with `NavigationSplitView`, tapping a list item shows the detail in the right-hand pane (no back button needed):

```swift
let isIPad = UIDevice.current.userInterfaceIdiom == .pad

// Tap first data cell (skip "Add" button at index 0)
let cells = app.cells.allElementsBoundByIndex
if cells.count > 1, cells[1].exists {
    cells[1].tap()
    sleep(1)
    try takeScreenshot(name: "03_Detail")

    // iPhone: navigate back; iPad: no-op (split view)
    if !isIPad {
        let navBar = app.navigationBars.firstMatch
        if navBar.waitForExistence(timeout: 3) {
            navBar.buttons.firstMatch.tap()
            Thread.sleep(forTimeInterval: type(of: self).navigationDelay)
        }
    }
}
```

---

## 8. Template Script Reference

The template is available at `Templates/capture_screenshots_template.sh`. Copy it to `scripts/capture_screenshots.sh` in your project and fill in the fields marked `← CHANGE`. The inline version below is for reference:

```bash
#!/usr/bin/env bash
#
# capture_screenshots.sh
#
# Automated screenshot capture + App Store mockup generation.
#
# Usage:
#   ./scripts/capture_screenshots.sh                    # full pipeline
#   ./scripts/capture_screenshots.sh --mockups-only     # mockups only
#   ./scripts/capture_screenshots.sh --iphone-only      # iPhone only
#   ./scripts/capture_screenshots.sh --languages "en,de"
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$PROJECT_ROOT/ios-screenshot-automator"
RUN_SCRIPT="$PACKAGE_DIR/Scripts/run_screenshots.sh"
COMPOSE_SCRIPT="$PACKAGE_DIR/Scripts/compose_mockup.swift"

# =============================================================================
# ← CHANGE: Project Configuration
# =============================================================================

PROJECT_FILE="$PROJECT_ROOT/MyApp.xcodeproj"          # ← CHANGE: Your .xcodeproj
SCHEME="MyApp"                                         # ← CHANGE: Your Xcode scheme
TEST_TARGET="MyAppUITests"                             # ← CHANGE: Your UITest target
TEST_CLASS="MyAppScreenshotTest"                       # ← CHANGE: Your test class name
DEFAULT_LANGUAGE="en"                                  # ← CHANGE: Default language
DEFAULT_DEVICES="iPhone 17 Pro,iPad Pro 13-inch (M5)"  # ← CHANGE: Default devices

# =============================================================================
# ← CHANGE: Design Configuration
# =============================================================================

SCREENSHOTS_DIR="$PROJECT_ROOT/screenshots"
MOCKUPS_DIR="$PROJECT_ROOT/Appstore Mockups"
GRADIENT_START="#667EEA"                               # ← CHANGE: Your brand color
GRADIENT_END="#764BA2"                                 # ← CHANGE: Your brand color

# Device frames                                       # ← CHANGE: Your frame paths
IPHONE_FRAME="$PROJECT_ROOT/Files/iPhone 17 Pro - Silver - Portrait.png"
IPAD_FRAME="$PROJECT_ROOT/Files/iPad Pro 13 - M4 - Silver - Portrait.png"

# =============================================================================
# ← CHANGE: Device Mapping
# =============================================================================
# Format: screenshot_folder | compose_preset | frame_path | margin_px
#
# screenshot_folder:  Must match the simulator name with spaces → underscores
# compose_preset:     Canvas size preset (iphone69, ipad13, appletv, etc.)
# frame_path:         Path to the device frame PNG
# margin_px:          Minimum margin around the frame in pixels

DEVICES=(
    "iPhone_17_Pro|iphone69|$IPHONE_FRAME|30"          # ← CHANGE: Your devices
    "iPad_Pro_13-inch_(M5)|ipad13|$IPAD_FRAME|70"     # ← CHANGE: Your devices
    # "Apple_TV_4K_(3rd_generation)_(at_1080p)|appletv|$APPLETV_FRAME|30"  # ← Apple TV
)

# =============================================================================
# Script Logic (no changes needed below this line)
# =============================================================================

MOCKUPS_ONLY=false
EXTRA_ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--mockups-only" ]; then
        MOCKUPS_ONLY=true
    else
        EXTRA_ARGS+=("$arg")
    fi
done

# --- Step 1: Capture screenshots ---
if [ "$MOCKUPS_ONLY" = false ]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  📸  Step 1: Capturing Screenshots                      ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    if [ ! -f "$RUN_SCRIPT" ]; then
        echo "❌ run_screenshots.sh not found at: $RUN_SCRIPT"
        echo "   Make sure ios-screenshot-automator is available."
        exit 1
    fi

    "$RUN_SCRIPT" \
        --project "$PROJECT_FILE" \
        --scheme "$SCHEME" \
        --test-target "$TEST_TARGET" \
        --test-class "$TEST_CLASS" \
        --output "$SCREENSHOTS_DIR" \
        --devices "$DEFAULT_DEVICES" \
        --languages "$DEFAULT_LANGUAGE" \
        "${EXTRA_ARGS[@]}"
fi

# --- Step 2: Generate App Store Mockups ---
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  🖼️  Step 2: Generating App Store Mockups                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

if [ ! -f "$COMPOSE_SCRIPT" ]; then
    echo "❌ compose_mockup.swift not found at: $COMPOSE_SCRIPT"
    exit 1
fi

TOTAL_MOCKUPS=0
FAILED_MOCKUPS=0

for device_config in "${DEVICES[@]}"; do
    IFS='|' read -r FOLDER PRESET FRAME MARGIN <<< "$device_config"

    DEVICE_SCREENSHOTS="$SCREENSHOTS_DIR/$FOLDER"
    DEVICE_MOCKUPS="$MOCKUPS_DIR/$FOLDER"

    if [ ! -d "$DEVICE_SCREENSHOTS" ]; then
        echo "⚠️  No screenshots found for $FOLDER — skipping"
        continue
    fi

    if [ ! -f "$FRAME" ]; then
        echo "⚠️  Frame not found: $FRAME — skipping $FOLDER"
        continue
    fi

    mkdir -p "$DEVICE_MOCKUPS"

    echo "📱 Processing: $FOLDER (preset: $PRESET, margin: ${MARGIN}px)"
    echo "   Frame: $(basename "$FRAME")"
    echo ""

    for screenshot in "$DEVICE_SCREENSHOTS"/*.png; do
        [ -f "$screenshot" ] || continue

        FILENAME=$(basename "$screenshot")
        OUTPUT="$DEVICE_MOCKUPS/$FILENAME"

        echo -n "   🖼️  $FILENAME → "

        if swift "$COMPOSE_SCRIPT" \
            --frame "$FRAME" \
            --screenshot "$screenshot" \
            --output "$OUTPUT" \
            --device "$PRESET" \
            --margin "$MARGIN" \
            --gradient-start "$GRADIENT_START" \
            --gradient-end "$GRADIENT_END" 2>&1 | tail -1; then
            TOTAL_MOCKUPS=$((TOTAL_MOCKUPS + 1))
        else
            echo "❌ Failed"
            FAILED_MOCKUPS=$((FAILED_MOCKUPS + 1))
        fi
    done

    echo ""
done

# --- Summary ---
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✅  Done!                                               ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  📸  Mockups generated: %-32s║\n" "$TOTAL_MOCKUPS"
if [ "$FAILED_MOCKUPS" -gt 0 ]; then
    printf "║  ❌  Failed:            %-32s║\n" "$FAILED_MOCKUPS"
fi
printf "║  📂  Output folder:     %-32s║\n" "Appstore Mockups/"
echo "╚══════════════════════════════════════════════════════════╝"
```

After copying, update all lines marked with `# ← CHANGE`.

---

## 9. CI/CD Integration

### GitHub Actions

```yaml
name: App Store Screenshots

on:
  workflow_dispatch:  # Manual trigger
  push:
    branches: [main]
    paths:
      - 'MyApp/**'
      - 'MyAppUITests/**'

jobs:
  screenshots:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: true

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.2.app

      - name: Install simulators
        run: |
          xcrun simctl list runtimes
          # Simulators are pre-installed on GitHub-hosted runners

      - name: Generate screenshots & mockups
        run: ./scripts/capture_screenshots.sh

      - name: Upload mockups
        uses: actions/upload-artifact@v4
        with:
          name: appstore-mockups
          path: Appstore Mockups/
```

### Fastlane

```ruby
# In your Fastfile:
lane :screenshots do
  sh("../scripts/capture_screenshots.sh")
end

# Or use Fastlane's built-in screenshot + frameit:
lane :screenshots_fastlane do
  capture_screenshots(scheme: "MyApp")
  frame_screenshots
end
```

### Xcode Cloud

Add a custom build script in your Xcode Cloud workflow:

```bash
#!/bin/bash
# ci_scripts/ci_post_xcodebuild.sh
if [ "$CI_WORKFLOW" = "Screenshots" ]; then
    ./scripts/capture_screenshots.sh --mockups-only
fi
```

---

## 10. FAQ

### Q: Do I need both `run_screenshots.sh` and `compose_mockup.swift`?

**A:** You don't interact with them directly. The template script (`capture_screenshots_template.sh`) calls both automatically. If you only want raw screenshots without device frames, simply leave the `DEVICES` frame paths empty or comment them out — the template's Step 2 (mockup generation) will skip devices without a valid frame.

### Q: Can I use my own device frames?

**A:** Yes. Any PNG with a transparent screen area works. The compose script auto-detects where the screen is. Place the PNG in your project repo (e.g. `Files/`) and reference it in the template script's `DEVICES` array.

### Q: Why are my iPad screenshots not navigating correctly?

**A:** You must override `tabLabels(forIndex:)` in your test subclass. The labels must exactly match your app's tab titles, including all localizations. See [iPad Support](#7-ipad-support).

### Q: Can I capture screenshots without building the full app?

**A:** No. `xcodebuild test` needs to build and install the app on the simulator. However, you can use `--mockups-only` to skip the capture step if you already have screenshots.

### Q: How do I capture screenshots for specific screens only?

**A:** Edit your `captureAllScreens()` method to include only the screens you want. You can also create multiple test methods and target them individually via `xcodebuild`'s `-only-testing` filter (e.g. `-only-testing:MyAppUITests/MyAppScreenshotTest/testHomeScreenshot`).

### Q: Why is the screenshot upside down in the mockup?

**A:** This was a bug in early versions. The current version uses `flipY()` to correctly convert between Core Graphics' bottom-left coordinate system and the image scanner's top-left coordinate system. Make sure you're using the latest `compose_mockup.swift`.

### Q: Can I add text labels or marketing copy to the mockups?

**A:** Not currently. The `compose_mockup.swift` script handles gradient + frame + screenshot only. For text overlays, use a design tool (Figma, Sketch) or extend the script with `CGContext.showGlyphs()` / `NSAttributedString.draw()`.

### Q: How do I add a new device?

**A:** Add a new entry to the `DEVICES` array in your template script with the correct simulator name, frame path, device preset, and margin. See the [template header](../Templates/capture_screenshots_template.sh) for the device entry format.

### Q: What if a simulator isn't available?

**A:** The internal `run_screenshots.sh` script automatically tries fallback devices. For example, if "iPhone 17 Pro Max" isn't installed, it tries "iPhone 16 Pro Max", then "iPhone 14 Plus". The fallback list is defined inside `run_screenshots.sh`.

### Q: Can I use JPEG instead of PNG for the output?

**A:** The script currently only outputs PNG (required by App Store Connect for the best quality). To change this, modify the `UTType.png.identifier` reference in `compose_mockup.swift` to `UTType.jpeg.identifier` and add JPEG compression options.
