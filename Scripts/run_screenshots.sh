#!/usr/bin/env bash
#
# run_screenshots.sh
#
# Builds and runs screenshot automation UI tests on a set of iOS simulators,
# collecting the resulting screenshots into an output directory.
#
# All project-specific values can be passed as arguments so this script
# can be called from any other script or CI pipeline.
#
# Usage:
#   ./scripts/run_screenshots.sh [OPTIONS]
#
# Options:
#   --project <path>         Path to the .xcodeproj file
#   --scheme <name>          Xcode scheme name
#   --test-target <name>     UI test target name (e.g. PlantnerUITests)
#   --test-class <name>      XCTest class name (e.g. PlantnerScreenshotTest)
#   --output <path>          Output directory for screenshots / result bundles
#   --devices <d1,d2,...>    Comma-separated list of simulator device names
#   --languages <l1,l2,...>  Comma-separated list of language codes
#   --iphone-only            Use default iPhone-only device list
#   --help, -h               Show this help message and exit
#
# Examples:
#   # Use Plantner defaults:
#   ./scripts/run_screenshots.sh
#
#   # Call from another script with custom values:
#   ./scripts/run_screenshots.sh \
#       --project /path/to/MyApp.xcodeproj \
#       --scheme MyApp \
#       --test-target MyAppUITests \
#       --test-class MyAppScreenshotTest \
#       --output /tmp/screenshots \
#       --devices "iPhone 16 Pro Max,iPhone 16 Pro" \
#       --languages "en,de"
#
# Requirements:
#   - Xcode with the required simulators installed
#

set -euo pipefail

# -----------------------------------------------------------------------------
# Colours
# -----------------------------------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Resolve project root relative to this script's location
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# -----------------------------------------------------------------------------
# Defaults (Plantner-specific – overridable via arguments)
# -----------------------------------------------------------------------------
PROJECT="$PROJECT_ROOT/Plantner.xcodeproj"
SCHEME="Plantner"
TEST_TARGET="PlantnerUITests"
TEST_CLASS="PlantnerScreenshotTest"
OUTPUT_DIR="$PROJECT_ROOT/screenshots"
DEVICES=("iPhone 17 Pro Max" "iPhone 17 Pro" "iPad Pro 13-inch (M5)")
LANGUAGES=("en")

# Fallback devices when a requested simulator is not installed
FALLBACK_DEVICES=(
    "iPhone 16 Pro Max"
    "iPhone 16 Pro"
    "iPhone 14 Plus"
    "iPad Pro 13-inch (M4)"
    "iPad Pro (12.9-inch) (6th generation)"
)

# =============================================================================
# Argument Parsing
# =============================================================================

show_help() {
    cat <<EOF

Usage: $0 [OPTIONS]

Options:
  --project <path>         Path to the .xcodeproj file
                           Default: $PROJECT
  --scheme <name>          Xcode scheme name
                           Default: $SCHEME
  --test-target <name>     UI test target name
                           Default: $TEST_TARGET
  --test-class <name>      XCTest class containing the screenshot test
                           Default: $TEST_CLASS
  --output <path>          Output directory for screenshots
                           Default: $OUTPUT_DIR
  --devices <d1,d2,...>    Comma-separated list of simulator device names
                           Default: iPhone 17 Pro Max, iPhone 17 Pro, iPad Pro 13-inch (M5)
  --languages <l1,l2,...>  Comma-separated list of language codes
                           Default: en
  --iphone-only            Use default iPhone-only device list
  --help, -h               Show this help message and exit

Examples:
  $0
  $0 --iphone-only --languages "en,de"
  $0 --project /path/to/App.xcodeproj --scheme App --test-target AppUITests --test-class AppScreenshotTest

EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --project)
            PROJECT="$2"
            shift 2
            ;;
        --scheme)
            SCHEME="$2"
            shift 2
            ;;
        --test-target)
            TEST_TARGET="$2"
            shift 2
            ;;
        --test-class)
            TEST_CLASS="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --devices)
            IFS=',' read -ra DEVICES <<< "$2"
            shift 2
            ;;
        --languages)
            IFS=',' read -ra LANGUAGES <<< "$2"
            shift 2
            ;;
        --iphone-only)
            DEVICES=("iPhone 17 Pro Max" "iPhone 17 Pro")
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run '$0 --help' for usage information."
            exit 1
            ;;
    esac
done

# =============================================================================
# Banner
# =============================================================================

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           📱 App Store Screenshot Generator 📱            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Project:      ${BLUE}$PROJECT${NC}"
echo -e "  Scheme:       ${BLUE}$SCHEME${NC}"
echo -e "  Test target:  ${BLUE}$TEST_TARGET${NC}"
echo -e "  Test class:   ${BLUE}$TEST_CLASS${NC}"
echo -e "  Output dir:   ${BLUE}$OUTPUT_DIR${NC}"
echo -e "  Languages:    ${BLUE}${LANGUAGES[*]}${NC}"
echo ""
echo "Target devices:"
for DEVICE in "${DEVICES[@]}"; do
    echo "  • $DEVICE"
done
echo ""

# =============================================================================
# Create output directory
# =============================================================================

mkdir -p "$OUTPUT_DIR"

TOTAL=0
SUCCESS=0
FAILED=0

# =============================================================================
# Per-device / per-language loop
# =============================================================================

for DEVICE in "${DEVICES[@]}"; do
    # Trim leading/trailing whitespace (from comma-separated input)
    DEVICE="$(echo "$DEVICE" | xargs)"

    for LANG in "${LANGUAGES[@]}"; do
        LANG="$(echo "$LANG" | xargs)"

        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}📱 $DEVICE  |  🌐 $LANG${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        ACTUAL_DEVICE="$DEVICE"

        # Check whether the simulator is available; try fallbacks if not
        if ! xcrun simctl list devices available | grep -q "$ACTUAL_DEVICE"; then
            FALLBACK_USED=""
            for FB in "${FALLBACK_DEVICES[@]}"; do
                if xcrun simctl list devices available | grep -q "$FB"; then
                    echo -e "${YELLOW}⚠️  '$DEVICE' not found – using fallback: $FB${NC}"
                    ACTUAL_DEVICE="$FB"
                    FALLBACK_USED="yes"
                    break
                fi
            done

            if [ -z "$FALLBACK_USED" ]; then
                echo -e "${RED}⚠️  Simulator '$DEVICE' not found and no fallback available – skipping${NC}"
                FAILED=$((FAILED + 1))
                continue
            fi
        fi

        DESTINATION="platform=iOS Simulator,name=${ACTUAL_DEVICE},OS=latest"
        SAFE_DEVICE_NAME="${ACTUAL_DEVICE// /_}"
        RESULT_BUNDLE="$OUTPUT_DIR/${SAFE_DEVICE_NAME}_${LANG}.xcresult"

        # Remove existing result bundle to avoid xcodebuild error
        rm -rf "$RESULT_BUNDLE"

        # Prepare the simulator
        echo "Preparing simulator..."
        xcrun simctl shutdown "$ACTUAL_DEVICE" 2>/dev/null || true
        sleep 2
        xcrun simctl boot "$ACTUAL_DEVICE" 2>/dev/null || true
        sleep 3

        # Run the tests (filter out noisy build output)
        xcodebuild test \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -destination "$DESTINATION" \
            -testLanguage "$LANG" \
            -only-testing:"$TEST_TARGET/$TEST_CLASS" \
            -resultBundlePath "$RESULT_BUNDLE" \
            2>&1 \
            | grep -v -E "(codesign|CodeSign|CompileC|Ld |clang|SwiftCompile|SwiftDriver|MergeSwiftModule|Copy |Ditto|RegisterExecutionPolicy|ProcessInfoPlistFile|LinkStoryboards|CompileStoryboard|CompileAssetCatalog|ProcessProductPackaging|GenerateDSYMFile|Touch |WriteAuxiliary|CreateBuildDirectory|EmitSwiftModule|SwiftMergeGeneratedHeaders|ValidateEmbedded|PhaseScriptExecution|note:)" \
            | grep -E "(Test |Testing|Screenshot|Error|BUILD|FAIL|Passed|📸|📱|✅|❌|Suite|started|passed|failed)" \
            || true

        # Shut down the simulator
        xcrun simctl shutdown "$ACTUAL_DEVICE" 2>/dev/null || true
        sleep 2

        TOTAL=$((TOTAL + 1))

        if [ -d "$RESULT_BUNDLE" ]; then
            echo -e "${GREEN}✅ Done: $ACTUAL_DEVICE ($LANG)${NC}"
            SUCCESS=$((SUCCESS + 1))
        else
            echo -e "${RED}❌ Failed: $ACTUAL_DEVICE ($LANG)${NC}"
            FAILED=$((FAILED + 1))
        fi
    done
done

# =============================================================================
# Summary
# =============================================================================

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                       📊 Summary                          ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✅ Successful:  $SUCCESS / $TOTAL${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}❌ Failed:      $FAILED${NC}"
fi
echo -e "${BLUE}📂 Output:      $OUTPUT_DIR${NC}"
echo ""

# List result bundles
echo "Result bundles:"
for f in "$OUTPUT_DIR"/*.xcresult; do
    [ -d "$f" ] && echo "  └── $(basename "$f")"
done
echo ""

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
