# Reference

Everything about `screenshots.json`, the `screenshots` tool and the `ScreenshotAutomator` test library. The short version is in the [README](../README.md).

- [How it works](#how-it-works)
- [`screenshots.json`](#screenshotsjson)
- [Sizes](#sizes)
- [Frame styles, background, captions](#frame-styles-background-captions)
- [Commands and exit codes](#commands-and-exit-codes)
- [Output](#output)
- [Test library](#test-library)
- [Platform notes](#platform-notes)
- [Troubleshooting](#troubleshooting)
- [Migrating from 1.x](#migrating-from-1x)

## How it works

1. `screenshots run` plans one **run** per size × language × appearance and picks the newest installed simulator whose display has an accepted pixel size for that size.
2. It builds each target once (`xcodebuild build-for-testing`), then runs your UI tests per run (`test-without-building`, `-testLanguage`/`-testRegion`, `-parallel-testing-enabled NO`, `-collect-test-diagnostics never`). It boots the simulator, sets status bar 9:41 and the appearance, and cleans up afterwards. It only shuts down simulators it started itself.
3. `shot("Name")` attaches the screenshot to the test result as `sa2v2__Name`. The tool exports the attachments from the `.xcresult` into `raw/`.
4. The composer draws background, frame and headline in the exact App Store size; the validator checks the result.

Every test method is its own run: if one fails, the screenshots of the others are still exported and composed, and the command exits with 1.

## `screenshots.json`

Complete example (all options):

```json
{
  "version": 2,
  "project": "Plantner.xcodeproj",
  "targets": [
    {
      "platform": "iOS",
      "scheme": "Plantner",
      "tests": "PlantnerUITests/Screenshots",
      "sizes": ["iphone-6.3", "iphone-6.9", "iphone-duo-outer", "ipad-13"],
      "landscape": []
    },
    {
      "platform": "tvOS",
      "scheme": "PlantnerTV",
      "tests": "PlantnerTVUITests/Screenshots",
      "sizes": ["appletv"]
    }
  ],
  "languages": ["de-DE", "en-US"],
  "appearances": ["light", "dark"],
  "permissions": ["photos"],
  "style": {
    "background": { "gradient": ["#1f881b", "#79b474"], "angle": 135 },
    "frame": "outline",
    "frameColor": "#000000",
    "caption": { "color": "#FFFFFF", "position": "top" }
  },
  "sizeStyles": {
    "appletv": { "background": { "color": "#102a43" }, "frame": "none", "caption": null }
  },
  "shots": {
    "01_Home": {
      "title": { "de-DE": "Alle Pflanzen im Blick", "en-US": "All your plants at a glance" },
      "subtitle": { "de-DE": "Mit Erinnerungen", "en-US": "With reminders" }
    }
  },
  "macCanvas": { "width": 2880, "height": 1800 },
  "output": "screenshots"
}
```

Paths (`project`, `workspace`, `frameImage`, `output`) are relative to the folder of `screenshots.json`.

| Field | Default | Meaning |
|---|---|---|
| `version` | required | Must be `2`. |
| `project` / `workspace` | required: exactly one | Xcode project or workspace, with the extension. Spaces are fine. |
| `targets` | required | One entry per scheme that runs UI tests; each has `platform`, `scheme`, `tests`, `sizes` and optionally `landscape`. |
| `targets[].platform` | required | `iOS`, `tvOS`, `watchOS` or `macOS`. Every size in `sizes` must belong to this platform. |
| `targets[].scheme` | required | Scheme to build and test. |
| `targets[].tests` | required | `<UITestTarget>/<TestClass>`, passed to `-only-testing:`. |
| `targets[].sizes` | required | Size IDs, see [Sizes](#sizes). |
| `targets[].landscape` | `[]` | Subset of `sizes` captured in landscape (the device is rotated; the output image is landscape). tvOS and macOS are always landscape. |
| `languages` | required | App Store codes such as `de-DE`, `en-US`, `zh-Hans`. `de-DE` runs as `-testLanguage de -testRegion DE`; a code without a two-letter region (`zh-Hans`) has no region. |
| `appearances` | `["light"]` | `light` and/or `dark`. Dark images get the suffix `_dark`. Not available on tvOS. |
| `permissions` | `[]` | `simctl privacy grant` services (for example `photos`, `camera`) granted for the app before each run. |
| `style` | see below | Look of all images. |
| `sizeStyles` | `{}` | Per size ID; **replaces** `style` completely for that size. |
| `shots` | `{}` | Headline (`title`) and optional `subtitle` per shot name and language. A shot without an entry gets no text. |
| `macCanvas` | 2880×1800 | Output size for Mac screenshots; use one of the sizes the App Store accepts for Mac (the `mac` row below, landscape). The validator requires every Mac image to have exactly this size. |
| `output` | `screenshots` | Output folder. |

`style` fields:

| Field | Default | Meaning |
|---|---|---|
| `background` | gradient `#2B2B2F` → `#5A5A63`, angle 135 | Either `{ "color": "#RRGGBB" }` or `{ "gradient": [colors…], "angle": 135 }`: `gradient` lists at least two stops, `angle` (default 135) sets the direction, see [Frame styles](#frame-styles-background-captions). Colors are `#RGB` or `#RRGGBB`. |
| `frame` | `outline` | `outline`, `bezel`, `image` or `none`, see [Frame styles](#frame-styles-background-captions). |
| `frameColor` | `#000000` | Line / ring color. |
| `frameImage` | none | PNG for `frame: image`; required in that case. |
| `caption` | white, top | `color` (default `#FFFFFF`), `position` (`top` or `bottom`, default `top`) and `font` (path to a `.ttf`/`.otf`, default the bold system font). `"caption": null` switches all text off (for example on the Watch). |

Rules the tool enforces (each problem is reported as `path: message`, exit code 2):

- Shot names contain only letters, digits, `_` and `-`.
- Titles and subtitles must exist for **every** language and use exactly the configured language codes (a title under `de` while the language is `de-DE` is an error with the hint to use `de-DE`).
- `frame: image` needs `frameImage`; colors must be valid; `landscape` entries must be in `sizes`.
- An iPhone size set needs `iphone-6.3`, an iPad size set needs `ipad-13`, Mac needs `mac`, Apple TV needs `appletv` (App Store requirement). More than one Watch size is an error. A set without iPhone Duo gives a warning (from April 2027 required for apps built with the iOS 27.1 SDK).

## Sizes

The only hand-maintained table is `Sources/ScreenshotCore/StoreSizes.swift`. Verified against <https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications> on 2026-11-14; Apple changes it about once a year. `screenshots sizes` lists the table and the simulator that would be used.

| ID | Platform | Required | Accepted pixel sizes (portrait; Apple TV and Mac are used in landscape) |
|---|---|---|---|
| `iphone-6.3` | iOS | yes | 1206×2622, 1179×2556 |
| `iphone-6.9` | iOS | no | 1320×2868, 1290×2796, 1260×2736 |
| `iphone-duo-outer` | iOS | no | 1398×2034 |
| `iphone-duo-inner` | iOS | no | 2007×2853 |
| `ipad-13` | iOS | yes | 2064×2752, 2048×2732 |
| `ipad-11` | iOS | no | 1668×2420, 1668×2388, 1640×2360, 1488×2266, 1512×2316 |
| `appletv` | tvOS | yes | 1080×1920, 2160×3840 (images are 1920×1080 or 3840×2160) |
| `mac` | macOS | yes | 1800×2880, 1600×2560, 900×1440, 800×1280 (images are 2880×1800, 2560×1600, 1440×900 or 1280×800) |
| `watch-ultra` | watchOS | no | 422×514, 410×502 |
| `watch-series` | watchOS | no | 416×496, 396×484 |
| `watch-se` | watchOS | no | 368×448 |

A size is chosen like this: among the installed device types with a display of an accepted pixel size (earlier entries in the list win), the one with the newest minimum runtime, then the highest installed runtime of that device. No match installed: error naming the size and the pixel sizes wanted; the tool never uses another size. PNG or JPEG, no alpha channel and 1 to 10 images per size and language are checked for every final image.

## Frame styles, background, captions

| `frame` | Look |
|---|---|
| `outline` | Thin line (0.6 % of the shorter device side) along the screen edge; the screenshot is clipped to the device's corner radii, taken per corner from the simulator profile. On iPhones with a Dynamic Island a black capsule is drawn (simulator screenshots do not contain it). |
| `bezel` | Filled ring (2.2 % of the device width) around the screen, like a stylized case. Same island rule. |
| `image` | Your own PNG with a transparent screen area in its center. The tool finds the area by walking from the image center to the first opaque pixel on each side. The area's aspect ratio must match the screenshot within 1 %, otherwise the run fails. No island is added. |
| `none` | Screenshot with rounded corners straight on the background. |

On macOS the window screenshot is drawn with a soft shadow on the canvas (16:10), whatever `frame` says. Devices with two displays (iPhone Duo) get no drawn island.

**Gradient angle.** Direction in screen coordinates: `0` = left to right, `90` = top to bottom, `45` = top-left to bottom-right, `135` = top-right to bottom-left. (This is not the CSS convention.)

**Captions.** The caption area is 18 % of the canvas height at the top or bottom. The title is bold, starts at 4.2 % of the canvas height (subtitle regular, 2.6 %), wraps to at most 2 title lines and 1 subtitle line, shrinks in 5 % steps down to 60 % and is then shortened with "…". Text never leaves the caption area. Emoji, umlauts and non-Latin scripts are laid out with CoreText font fallback. `font` takes a path to a `.ttf`/`.otf` file.

## Commands and exit codes

| Command | Purpose |
|---|---|
| `screenshots init` | Asks for scheme, UI-test target, sizes, languages, frame style and two gradient colors; writes `screenshots.json` and `<UITestTarget>/Screenshots.swift`, offers to add `screenshots/raw/` and `screenshots/.work/` to `.gitignore`. Never overwrites an existing config or test file. The wizard offers iOS sizes; add tvOS/macOS/watchOS targets by hand. |
| `screenshots run` | Capture, compose, validate, write `index.html`. Filters: `--size`, `--language`, `--scheme` (repeatable). |
| `screenshots compose` | Rebuild final images from existing raw images. Starts no simulator. Same filters. |
| `screenshots check` | Config, installed simulators, required sizes, texts without a matching shot (once `raw/` has images). Changes nothing. |
| `screenshots sizes` | All known sizes and the chosen simulator. |

All commands take `--config <path>` (default `./screenshots.json`).

| Exit code | Meaning |
|---|---|
| 0 | Success (warnings are allowed). |
| 1 | An image is missing, a test run failed, a validation error occurred, or no simulator is installed for a size. |
| 2 | Invalid or unreadable configuration. |

Environment: `SCREENSHOTS_COMMAND_TIMEOUT` is the longest time in seconds one `xcodebuild`/`simctl` call may run (default 1200). A test run that times out is tried once more; a second timeout is a failure.

## Output

```
screenshots/
├── raw/<size>/<language>-<appearance>/<shot>.png    raw screenshots, unchanged
├── final/<language>/<size>_<shot>[_dark].png        final images, exact App Store size
├── index.html                                       overview of the final images
└── .work/                                           derived data and result bundles
```

`final/<language>/` uses App Store language codes, so `fastlane deliver` can read the folder directly. A run replaces all outputs of its scope: old images of the same size and language never stay behind, and a run without exported screenshots deletes its raw folder instead of leaving stale files. Commit `final/` if you like; add `raw/` and `.work/` to `.gitignore`.

## Test library

Add the package product `ScreenshotAutomator` to the UI-test target and subclass `ScreenshotTestCase`:

| API | Meaning |
|---|---|
| `launch(extraArguments:environment:)` | Starts the app with the default arguments **plus** `extraArguments`. |
| `shot(_ name:)` | Takes a screenshot of the right display and attaches it (nothing is written to disk). Waits `settleDelay` first. Invalid names fail the test. |
| `tap(id:timeout:)` | Taps the first element with that `accessibilityIdentifier`. |
| `waitFor(_:timeout:)` | `waitForExistence`, returns `Bool`. |
| `class var launchArguments` | Default `-UITEST -LOAD_MOCK_DATA -DISABLE_ANIMATIONS -SKIP_ONBOARDING`; override to change. |
| `class var settleDelay` | 0.5 s. |

Your app reacts to the launch arguments itself, for example `CommandLine.arguments.contains("-UITEST")`. Other states can be started with your own arguments (`-SCREEN detail`). System permission dialogs are tapped away by an interruption handler (last button), independent of language; for a controlled result grant permissions through `permissions` instead.

On a device with two displays `shot()` captures the display named by the tool (`primary`, `primary-1`) and fails if the app is not running on it.

**Tabs.** SwiftUI's `TabView` ignores an `accessibilityIdentifier` on its tabs (the identifier lands on the tab's content). On iPhone, iPad and iPhone Duo the system exposes the SF Symbol name of each tab as the identifier of the tab button, so give every tab its own symbol and use `tap(id: "list.bullet")` (see `Example/`). On Apple TV navigate with `XCUIRemote`.

## Platform notes

- **iPhone, iPad.** Status bar override and appearance through `simctl`. iPad uses the floating tab bar on iPadOS 18+ (no `TabBar` element); see Tabs above.
- **iPhone Duo.** Booted, the device is **closed**: the app runs on the outer display (`iphone-duo-outer`, works fully automatically). The inner display (`iphone-duo-inner`) lights up only when the device is **unfolded**, and the app then shows in landscape. There is no public way to unfold a simulator from the command line (Xcode 27 has no `Simulator.app` any more; DeviceHub offers nothing a script can drive). Unfold it by hand, then run `screenshots run --size iphone-duo-inner` with `"landscape": ["iphone-duo-inner"]` in the target; the tool uses the running device and leaves it running. A closed device fails with `The app is not running on display "primary-1"` instead of producing a black image. The inner size is therefore not part of the example configuration.
- **Apple TV.** Landscape, outline without corner radius. No touch: navigate with `XCUIRemote.shared.press(…)` or start in a state with launch arguments. tvOS simulators cannot switch appearance, so only `light` is supported; `dark` fails with a clear message.
- **Mac and Apple Watch.** Implemented and unit-tested but **not verified against a real run yet**; they need local setup (UI automation on the Mac, a watchOS runtime). See [issue #6](https://github.com/matthias-karl/ios-screenshot-automator/issues/6).
- **Landscape.** List sizes in `landscape` to rotate the device (primary display only) and get landscape output.

## Troubleshooting

| Message | Cause and fix |
|---|---|
| `No installed simulator has a display of …` | Install a matching runtime/device in Xcode ▸ Settings ▸ Components. The tool never substitutes another size. |
| `Unknown size "…"` | Typo; `screenshots sizes` lists the IDs. |
| `Test run … failed` with the end of the `xcodebuild` log | A test failed or the build is broken. Open `screenshots/.work/<run>.xcresult` in Xcode. |
| `xcodebuild timed out, trying once more…` | A simulator or `xcodebuild` hung. A second timeout fails the run; raise `SCREENSHOTS_COMMAND_TIMEOUT` for very slow builds. |
| `finished without any screenshot attachment` | The tests ran but never called `shot("…")`, or the test class is not in `tests`. |
| `produced the shot "…" more than once` | Two `shot` calls with the same name in one run; names must be unique per run. |
| `screenshot protocol version …` | The `ScreenshotAutomator` package in your app and the installed tool are different releases; update both. |
| `raw image … is …; not a valid size for …` | The test ran on the wrong simulator. Plan and run use the same selection; check what is booted. |
| `has texts, but no test produced a shot named "…"` | A title in `shots` without a matching `shot("…")`, or you filtered the run. Fix the name or remove the entry. |
| `all languages need the same shots` | One language lacks a shot (a failed run); fix the failing run. |
| `The app is not running on display "primary-1"` | The iPhone Duo is closed; unfold it, see [Platform notes](#platform-notes). |
| `Multiple matching elements` / tab not found | Use `tap(id:)` (takes the first match); tabs need distinct SF Symbols, see Tabs. |
| `tvOS simulators cannot switch appearance` | Use `"appearances": ["light"]` for the tvOS target. |
| `Invalid shot name` | Letters, digits, `_` and `-` only. |

## Migrating from 1.x

Version 2.0 is a clean break; 1.x stays available under the tags `1.0.0` to `1.2.0`.

| 1.x | 2.0 |
|---|---|
| `Scripts/run_screenshots.sh` template copied into each app | Gone. `screenshots run` with `screenshots.json`. |
| `ScreenshotTestBase`, `setUp()`, `captureAllScreens()`, `tabLabels`, `tapPlusButton`, `dismissSheet`, device lists | `ScreenshotTestCase` with `launch()`, `shot()`, `tap(id:)`. Give controls an `accessibilityIdentifier`. |
| Frame PNGs and `compose_mockup.swift` | Frames come from simulator data (`outline`, `bezel`); your own PNG via `frame: image`. |
| Device names and pixel sizes in the app or script | Only size IDs in `screenshots.json`. |
| `extraArguments` replaced the default launch arguments | `extraArguments` are **appended** to the defaults. |

Steps: update the package to 2.0 (the product is still called `ScreenshotAutomator`), switch the test to `ScreenshotTestCase`, run `screenshots init`, delete the old script, templates and frame PNGs, and run `screenshots run`.
