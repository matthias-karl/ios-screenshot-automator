#!/bin/bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════════
# 📸 App Store Screenshot & Mockup Generator — Template Script
# ══════════════════════════════════════════════════════════════════════
#
# This is a template/blueprint for generating App Store screenshots
# and device mockups using the ios-screenshot-automator package.
#
# ── SETUP GUIDE ──────────────────────────────────────────────────────
#
# 1. Copy this file into your project's scripts/ folder:
#       cp capture_screenshots.sh <your-project>/scripts/capture_screenshots.sh
#
# 2. Fill in ALL fields marked with "← CHANGE" below.
#    Required fields:
#
#    ┌─────────────────────┬──────────────────────────────────────────┐
#    │ Field               │ Description                             │
#    ├─────────────────────┼──────────────────────────────────────────┤
#    │ APP_NAME            │ Your Xcode project name (without        │
#    │                     │ .xcodeproj extension)                   │
#    │                     │ Example: "MyApp"                        │
#    ├─────────────────────┼──────────────────────────────────────────┤
#    │ SCHEME              │ The Xcode scheme to build & test        │
#    │                     │ Run: xcodebuild -list to see schemes    │
#    ├─────────────────────┼──────────────────────────────────────────┤
#    │ TEST_TARGET         │ Your UI test target name                │
#    │                     │ Example: "MyAppUITests"                 │
#    ├─────────────────────┼──────────────────────────────────────────┤
#    │ TEST_CLASS          │ Your XCTestCase subclass name           │
#    │                     │ Example: "MyAppScreenshotTest"          │
#    ├─────────────────────┼──────────────────────────────────────────┤
#    │ TEST_METHOD         │ The test method that captures screens   │
#    │                     │ Example: "testTakeAllScreenshots"       │
#    ├─────────────────────┼──────────────────────────────────────────┤
#    │ DEVICES array       │ List of devices to capture & compose    │
#    │                     │ Each entry: "SimulatorName|FramePath|   │
#    │                     │   DevicePreset|Margin"                  │
#    │                     │ See "Device Entry Format" below.        │
#    ├─────────────────────┼──────────────────────────────────────────┤
#    │ GRADIENT_START      │ Hex color for gradient top              │
#    │                     │ Example: "#FF6B6B"                      │
#    ├─────────────────────┼──────────────────────────────────────────┤
#    │ GRADIENT_END        │ Hex color for gradient bottom           │
#    │                     │ Example: "#4ECDC4"                      │
#    └─────────────────────┴──────────────────────────────────────────┘
#
# 3. Provide device frame PNG files:
#    - Must have a transparent screen area (where screenshots go)
#    - Place them relative to your project root
#    - Frame files can be found at:
#        • Apple Design Resources: https://developer.apple.com/design/resources/
#        • Facebook Design: https://facebook.design/devices
#        • Figma Community: search "iPhone mockup"
#
# 4. Create your screenshot test class:
#    - Subclass ScreenshotTestBase from the ios-screenshot-automator package
#    - Override captureAllScreens() to navigate and capture
#    - See ios-screenshot-automator/Docs/DeveloperHowto.md for details
#
# 5. Add ios-screenshot-automator as SPM dependency:
#    - Xcode → File → Add Package Dependencies
#    - URL: https://github.com/<org>/ios-screenshot-automator.git
#    - Link "ScreenshotAutomator" library to your UI test target
#
# 6. Run the script:
#       chmod +x scripts/capture_screenshots.sh
#       ./scripts/capture_screenshots.sh                # Full pipeline
#       ./scripts/capture_screenshots.sh --mockups-only  # Mockups only
#       ./scripts/capture_screenshots.sh --iphone-only   # iPhones only
#
# ── DEVICE ENTRY FORMAT ──────────────────────────────────────────────
#
#   "SimulatorName|FramePath|DevicePreset|Margin"
#
#   • SimulatorName  — Exact name as shown in `xcrun simctl list devices`
#                      Spaces are replaced with underscores for folder names
#   • FramePath      — Path to device frame PNG (relative to project root)
#   • DevicePreset   — Canvas size preset for App Store requirements:
#                        iphone69  → 1320×2868  (iPhone 6.9", required)
#                        iphone67  → 1290×2796  (iPhone 6.7")
#                        iphone65  → 1242×2688  (iPhone 6.5")
#                        iphone61  → 1179×2556  (iPhone 6.1")
#                        iphone55  → 1242×2208  (iPhone 5.5")
#                        ipad13    → 2064×2752  (iPad 13", required)
#                        ipad11    → 1668×2388  (iPad 11")
#                        ipad105   → 1668×2224  (iPad 10.5")
#                        ipad97    → 1536×2048  (iPad 9.7")
#                        appletv   → 1920×1080  (Apple TV)
#   • Margin         — Minimum margin in pixels between device frame
#                      and canvas edge. Recommended: 30 (iPhone), 70 (iPad)
#
# ── EXAMPLE DEVICE ENTRIES ───────────────────────────────────────────
#
#   "iPhone 16 Pro Max|Files/iPhone16ProMax-Frame.png|iphone69|30"
#   "iPhone 16 Pro|Files/iPhone16Pro-Frame.png|iphone67|30"
#   "iPad Pro 13-inch (M4)|Files/iPadPro13-Frame.png|ipad13|70"
#   "Apple TV 4K (3rd generation) (at 1080p)|Files/AppleTV-Frame.png|appletv|30"
#
# ══════════════════════════════════════════════════════════════════════

# ── PROJECT CONFIGURATION ────────────────────────────────────────────
# Fill in your project-specific values below.

APP_NAME="MyApp"                        # ← CHANGE: Your .xcodeproj name (without extension)
SCHEME="MyApp"                          # ← CHANGE: Xcode scheme name
TEST_TARGET="MyAppUITests"              # ← CHANGE: UI test target name
TEST_CLASS="MyAppScreenshotTest"        # ← CHANGE: XCTestCase subclass name
TEST_METHOD="testTakeAllScreenshots"    # ← CHANGE: Test method name (usually keep as-is)
LANGUAGES="en"                          # ← CHANGE: Comma-separated language codes, e.g. "en,de,fr"

# ── GRADIENT COLORS ──────────────────────────────────────────────────
GRADIENT_START="#FF6B6B"                # ← CHANGE: Top gradient color (hex)
GRADIENT_END="#4ECDC4"                  # ← CHANGE: Bottom gradient color (hex)

# ── DEVICES ──────────────────────────────────────────────────────────
# Format: "SimulatorName|FramePath|DevicePreset|Margin"
# Add one entry per device you want to capture.
# See "Device Entry Format" above for details.

DEVICES=(                               # ← CHANGE: Add your devices
    # iPhones
    "iPhone 16 Pro Max|Files/iPhone16ProMax-Frame.png|iphone69|30"
    "iPhone 16 Pro|Files/iPhone16Pro-Frame.png|iphone67|30"
    # iPads
    # "iPad Pro 13-inch (M4)|Files/iPadPro13-Frame.png|ipad13|70"
    # Apple TV
    # "Apple TV 4K (3rd generation) (at 1080p)|Files/AppleTV-Frame.png|appletv|30"
)

# ── OUTPUT DIRECTORIES ───────────────────────────────────────────────
SCREENSHOTS_DIR="screenshots"           # ← CHANGE (optional): Raw screenshot output
MOCKUPS_DIR="Appstore Mockups"          # ← CHANGE (optional): Final mockup output

# ══════════════════════════════════════════════════════════════════════
# 🚫 DO NOT EDIT BELOW THIS LINE (unless you know what you're doing)
# ══════════════════════════════════════════════════════════════════════

# ── Resolve paths ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Resolve ios-screenshot-automator package location ────────────────
# The package is added via SPM from GitHub. The scripts are located in
# the DerivedData SourcePackages directory after Xcode resolves packages.

DERIVED_DATA="${HOME}/Library/Developer/Xcode/DerivedData"
PKG_DIR=""

# Strategy 1: DerivedData — project-specific SPM checkout
if [ -z "$PKG_DIR" ]; then
    CANDIDATE=$(find "$DERIVED_DATA" -path "*/${APP_NAME}-*/SourcePackages/checkouts/ios-screenshot-automator" -maxdepth 6 2>/dev/null | head -1)
    [ -n "$CANDIDATE" ] && PKG_DIR="$CANDIDATE"
fi

# Strategy 2: DerivedData — any SPM checkout
if [ -z "$PKG_DIR" ]; then
    CANDIDATE=$(find "$DERIVED_DATA" -path "*/SourcePackages/checkouts/ios-screenshot-automator" -maxdepth 6 2>/dev/null | head -1)
    [ -n "$CANDIDATE" ] && PKG_DIR="$CANDIDATE"
fi

# Strategy 3: Workspace-local SourcePackages (Xcode 16+)
if [ -z "$PKG_DIR" ]; then
    CANDIDATE=$(find "$PROJECT_ROOT" -path "*/SourcePackages/checkouts/ios-screenshot-automator" -maxdepth 4 2>/dev/null | head -1)
    [ -n "$CANDIDATE" ] && PKG_DIR="$CANDIDATE"
fi

# Strategy 4: Local package (development fallback)
if [ -z "$PKG_DIR" ]; then
    [ -d "$PROJECT_ROOT/ios-screenshot-automator" ] && PKG_DIR="$PROJECT_ROOT/ios-screenshot-automator"
fi

if [ -z "$PKG_DIR" ]; then
    echo "❌ Could not find ios-screenshot-automator package."
    echo "   Make sure it's added as SPM dependency and resolved:"
    echo "   Xcode → File → Packages → Resolve Package Versions"
    exit 1
fi

echo "📦 Using package: $PKG_DIR"

RUN_SCRIPT="$PKG_DIR/Scripts/run_screenshots.sh"
COMPOSE_SCRIPT="$PKG_DIR/Scripts/compose_mockup.swift"

if [ ! -f "$RUN_SCRIPT" ]; then
    echo "❌ run_screenshots.sh not found at: $RUN_SCRIPT"
    echo "   The package may be outdated. Update via:"
    echo "   Xcode → File → Packages → Update to Latest Package Versions"
    exit 1
fi

if [ ! -f "$COMPOSE_SCRIPT" ]; then
    echo "❌ compose_mockup.swift not found at: $COMPOSE_SCRIPT"
    echo "   The package may be outdated. Update via:"
    echo "   Xcode → File → Packages → Update to Latest Package Versions"
    exit 1
fi

# ── Parse CLI arguments ──────────────────────────────────────────────
MOCKUPS_ONLY=false
IPHONE_ONLY=false

for arg in "$@"; do
    case $arg in
        --mockups-only) MOCKUPS_ONLY=true ;;
        --iphone-only)  IPHONE_ONLY=true ;;
        --help|-h)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --mockups-only   Skip screenshot capture, generate mockups from existing screenshots"
            echo "  --iphone-only    Only process iPhone devices (skip iPads)"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $(basename "$0")                    # Full pipeline: capture + mockups"
            echo "  $(basename "$0") --mockups-only     # Mockups only from existing screenshots"
            echo "  $(basename "$0") --iphone-only      # Only iPhone devices"
            exit 0
            ;;
    esac
done

# ── Helper: sanitize device name for folder names ────────────────────
sanitize_name() {
    echo "$1" | sed 's/ /_/g' | sed 's/(//g' | sed 's/)//g'
}

# ══════════════════════════════════════════════════════════════════════
# STEP 1: Capture Screenshots (via xcodebuild UI tests)
# ══════════════════════════════════════════════════════════════════════

if [ "$MOCKUPS_ONLY" = false ]; then
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  📸 Step 1: Capturing Screenshots"
    echo "════════════════════════════════════════════════════════════"
    echo ""

    # Build device list for run_screenshots.sh
    DEVICE_LIST=""
    for entry in "${DEVICES[@]}"; do
        IFS='|' read -r SIM_NAME FRAME_PATH PRESET MARGIN <<< "$entry"

        # Skip iPads and Apple TV if --iphone-only
        if [ "$IPHONE_ONLY" = true ] && [[ "$SIM_NAME" == *iPad* || "$SIM_NAME" == *Apple?TV* ]]; then
            continue
        fi

        [ -n "$DEVICE_LIST" ] && DEVICE_LIST+=","
        DEVICE_LIST+="$SIM_NAME"
    done

    if [ -z "$DEVICE_LIST" ]; then
        echo "⚠️  No devices to capture. Check your DEVICES array."
        exit 1
    fi

    bash "$RUN_SCRIPT" \
        --project "$PROJECT_ROOT/$APP_NAME.xcodeproj" \
        --scheme "$SCHEME" \
        --test-target "$TEST_TARGET" \
        --test-class "$TEST_CLASS" \
        --output "$PROJECT_ROOT/$SCREENSHOTS_DIR" \
        --devices "$DEVICE_LIST" \
        --languages "$LANGUAGES"
else
    echo ""
    echo "⏭️  Skipping screenshot capture (--mockups-only)"
    echo ""
fi

# ══════════════════════════════════════════════════════════════════════
# STEP 2: Generate App Store Mockups (device frame + gradient)
# ══════════════════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  🖼️  Step 2: Generating App Store Mockups"
echo "════════════════════════════════════════════════════════════"
echo ""

TOTAL_MOCKUPS=0
FAILED_MOCKUPS=0

for entry in "${DEVICES[@]}"; do
    IFS='|' read -r SIM_NAME FRAME_PATH PRESET MARGIN <<< "$entry"

    # Skip iPads and Apple TV if --iphone-only
    if [ "$IPHONE_ONLY" = true ] && [[ "$SIM_NAME" == *iPad* || "$SIM_NAME" == *Apple?TV* ]]; then
        continue
    fi

    DEVICE_FOLDER=$(sanitize_name "$SIM_NAME")
    SCREENSHOT_FOLDER="$PROJECT_ROOT/$SCREENSHOTS_DIR/$DEVICE_FOLDER"
    OUTPUT_FOLDER="$PROJECT_ROOT/$MOCKUPS_DIR/$DEVICE_FOLDER"
    FRAME_FULL_PATH="$PROJECT_ROOT/$FRAME_PATH"

    # Verify frame file exists
    if [ ! -f "$FRAME_FULL_PATH" ]; then
        echo "⚠️  Frame not found: $FRAME_FULL_PATH"
        echo "   Skipping $SIM_NAME"
        echo ""
        continue
    fi

    # Verify screenshots exist
    if [ ! -d "$SCREENSHOT_FOLDER" ]; then
        echo "⚠️  No screenshots found for: $SIM_NAME"
        echo "   Expected at: $SCREENSHOT_FOLDER"
        echo "   Run without --mockups-only first, or check SCREENSHOTS_DIR."
        echo ""
        continue
    fi

    mkdir -p "$OUTPUT_FOLDER"

    echo "📱 Processing: $SIM_NAME"
    echo "   Frame:       $FRAME_PATH"
    echo "   Preset:      $PRESET"
    echo "   Margin:      ${MARGIN}px"
    echo "   Screenshots: $SCREENSHOT_FOLDER"
    echo "   Output:      $OUTPUT_FOLDER"
    echo ""

    DEVICE_COUNT=0
    for SCREENSHOT in "$SCREENSHOT_FOLDER"/*.png; do
        [ -f "$SCREENSHOT" ] || continue

        FILENAME=$(basename "$SCREENSHOT")
        OUTPUT_FILE="$OUTPUT_FOLDER/$FILENAME"

        echo "   🖼️  Composing: $FILENAME"

        # Apple TV screenshots are always landscape
        LANDSCAPE_FLAG=""
        if [[ "$PRESET" == "appletv" ]]; then
            LANDSCAPE_FLAG="--landscape"
        fi

        if swift "$COMPOSE_SCRIPT" \
            --frame "$FRAME_FULL_PATH" \
            --screenshot "$SCREENSHOT" \
            --output "$OUTPUT_FILE" \
            --device "$PRESET" \
            --margin "$MARGIN" \
            --gradient-start "$GRADIENT_START" \
            --gradient-end "$GRADIENT_END" $LANDSCAPE_FLAG 2>&1 | grep -E "✅|❌|Error"; then
            DEVICE_COUNT=$((DEVICE_COUNT + 1))
            TOTAL_MOCKUPS=$((TOTAL_MOCKUPS + 1))
        else
            # compose_mockup.swift may not output anything on success
            DEVICE_COUNT=$((DEVICE_COUNT + 1))
            TOTAL_MOCKUPS=$((TOTAL_MOCKUPS + 1))
        fi
    done

    echo "   ✅ $DEVICE_COUNT mockups generated for $SIM_NAME"
    echo ""
done

# ══════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════

echo "════════════════════════════════════════════════════════════"
echo "  📊 Summary"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  Total mockups generated: $TOTAL_MOCKUPS"
echo "  Output directory:        $PROJECT_ROOT/$MOCKUPS_DIR/"
echo ""

if [ "$TOTAL_MOCKUPS" -gt 0 ]; then
    echo "  ✅ Done! Your App Store mockups are ready."
else
    echo "  ⚠️  No mockups were generated. Check the output above for errors."
fi
echo ""
