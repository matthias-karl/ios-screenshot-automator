---
name: ios-screenshots
description: Create, update or fix App Store screenshots for an iOS, iPadOS or tvOS app with the `screenshots` command-line tool (ios-screenshot-automator 2.0) — set up screenshots.json and XCUITest shots, capture on simulators, compose framed images with headlines, and validate them against App Store rules. Use when the user asks for App Store screenshots, store images, marketing screenshots or mockups of their app.
---

# App Store screenshots with `screenshots`

The `screenshots` tool runs the app's UI tests on the right simulators, collects every `shot("Name")`, draws background, device outline and headline in the exact App Store pixel size, and validates the result. You write navigation only; no device names, pixel sizes or scripts go into the app.

Full reference (every config field, sizes, troubleshooting): https://github.com/matthias-karl/ios-screenshot-automator/blob/main/Docs/Reference.md

## 1. Check the tools

```bash
command -v screenshots || echo "missing"
screenshots --version            # 2.x
screenshots sizes                # known sizes and the simulator each would use
```

Missing? Install once: clone https://github.com/matthias-karl/ios-screenshot-automator and run `Scripts/install.sh` (needs Xcode 27; links `~/.local/bin/screenshots`). A size without an installed simulator is an error — the tool never substitutes another size. Tell the user which runtime/device to install instead of changing sizes on your own.

## 2. Set up an app (once)

Run in the folder that contains the `.xcodeproj` / `.xcworkspace`. Without a terminal (or with `--yes`) `init` asks nothing:

```bash
screenshots init --yes --scheme MyApp --ui-tests MyAppUITests \
  --size iphone-6.3 --size ipad-13 --language en-US --language de-DE \
  --gradient '#1f881b' --gradient '#79b474'
```

It writes `screenshots.json` and `MyAppUITests/Screenshots.swift`, and adds `screenshots/raw/` and `screenshots/.work/` to `.gitignore`. It never overwrites an existing config or test file. Then:

- Make sure the test file is part of the UI-test target (folders added as synchronized groups pick it up automatically; otherwise add it to the target).
- Add the Swift package product `ScreenshotAutomator` (from https://github.com/matthias-karl/ios-screenshot-automator, version 2.x) to the **UI-test target only**.
- tvOS: add a second target entry by hand (`"platform": "tvOS"`, `"sizes": ["appletv"]`). Mac and Apple Watch are not verified yet (issue #6) — do not promise them.

Required sizes: an iPhone set needs `iphone-6.3`, an iPad set needs `ipad-13`, tvOS needs `appletv`.

## 3. Write the screenshot test

```swift
import XCTest
import ScreenshotAutomator

final class Screenshots: ScreenshotTestCase {
    func test01_Home() { launch(); shot("01_Home") }

    func test02_Detail() {
        launch()
        tap(id: "game.hero")                 // accessibilityIdentifier
        shot("02_Detail")
    }

    func test03_Settings() {
        launch()
        tap(id: "gearshape")                 // tabs: the SF Symbol name of the tab
        shot("03_Settings")
    }

    func test04_State() {
        launch(extraArguments: ["-SCREEN", "detail"])   // start directly in a state
        shot("04_State")
    }
}
```

Rules that keep runs stable:

- **One test method per screen**, each starting with `launch()`. A failing method does not cost the screenshots of the others.
- Shot names: letters, digits, `_`, `-`; prefix with a number for the order. The same names must exist in every language.
- Find controls by `accessibilityIdentifier` (add them to the app where missing, e.g. `button.add`). Never by visible text: the run happens in every language.
- **Tabs:** SwiftUI's `TabView` ignores identifiers on tabs. Tap the tab's SF Symbol name instead (`tap(id: "books.vertical")`); give every tab a symbol that is not used elsewhere on screen.
- Hard-to-reach states: add a launch argument to the app and pass it with `launch(extraArguments:)`.
- Apple TV has no touch: `XCUIRemote.shared.press(.right)` / `.select`, or launch arguments.
- Override `class var settleDelay` (default 0.5 s) only if a screen animates longer.

App side: `ScreenshotTestCase` launches with `-UITEST -LOAD_MOCK_DATA -DISABLE_ANIMATIONS -SKIP_ONBOARDING`. The app should load deterministic sample data, skip onboarding and permission prompts, and turn animations off when it sees them.

## 4. Headlines and style

```json
"shots": {
  "01_Home": { "title": { "en-US": "All your games in one place", "de-DE": "Alle Spiele an einem Ort" } }
}
```

Every title needs every configured language, with exactly the configured codes (`de-DE`, not `de`). Ask the user for marketing copy rather than inventing it. Style: `"frame": "outline" | "bezel" | "image" | "none"`, `"background": {"gradient": [...], "angle": 135}` (0° = left→right, 90° = top→bottom).

## 5. Run

```bash
screenshots check                                          # config + simulators, changes nothing
screenshots run --size iphone-6.3 --language en-US         # fast first iteration
screenshots run                                            # everything
screenshots compose                                        # after changing titles/style: no simulators
```

- A full run takes minutes (about 1–3 min per size × language). Run it in the background and wait for it; do not start a second run or other `xcodebuild` runs on the same project meanwhile.
- **Exit code 0 is the only success.** 1 = an image is missing or a check failed, 2 = invalid config. Never report success from log text alone.
- The tool boots and shuts down only simulators it started itself. Do not shut down simulators the user had running.
- Output: `screenshots/final/<language>/<size>_<shot>[_dark].png` and `screenshots/index.html`. Look at several final images before you report.

## 6. When it fails

| Message | Do this |
|---|---|
| `No installed simulator has a display of …` | Ask the user to install that device/runtime; do not drop the size silently. |
| `Test run … failed` | Read the failures: `xcrun xcresulttool get test-results tests --path screenshots/.work/<run>.xcresult`. Usually a missing identifier or a timing issue in the test. |
| `No element with accessibilityIdentifier …` | Add the identifier in the app, or for tabs use the SF Symbol name. |
| `has texts, but no test produced a shot named …` | A title without a matching `shot(...)`; fix the name. |
| `all languages need the same shots` | One language run failed; fix that run. |
| `The app is not running on display "primary-1"` | iPhone Duo inner display: a human must unfold the booted Duo simulator first, then run `--size iphone-duo-inner` (config needs `"landscape": ["iphone-duo-inner"]`). |
| `tvOS simulators cannot switch appearance` | Use `"appearances": ["light"]` for tvOS. |
| `xcodebuild timed out, trying once more…` | Usually recovers. For very slow builds set `SCREENSHOTS_COMMAND_TIMEOUT` (seconds). |

Commit `screenshots.json`, the test file and app changes; commit `screenshots/final/` only if the user wants the images in the repository. Never commit `raw/` or `.work/`.
