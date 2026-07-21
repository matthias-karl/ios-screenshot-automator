# Code Review — `ios-screenshot-automator`

**Reviewer:** Automated deep review
**Date:** 2026-07-21
**Scope:** Full repository (`Sources/`, `Scripts/`, `Templates/`, `Examples/`, `Docs/`, `Package.swift`)
**Version reviewed:** post-`142c995` (Apple TV support)

---

## 0. TL;DR

This is a genuinely useful, well-documented toolkit with a clear purpose: turn a subclass +
one shell script into App-Store-ready screenshots across iPhone / iPad / Apple TV. The
documentation is excellent (arguably the strongest part of the repo). The Swift is clean and
readable, and the navigation heuristics are thoughtfully layered.

However, **the default "copy the template and run" happy path is broken out of the box** because
of three independent, confirmed bugs (an unsupported `iphone67` preset shipped in the template, a
folder-name sanitisation mismatch, and failures being silently counted as successes). None are
hard to fix, but together they mean a first-time user following the Quick Start will very likely
get zero iPad mockups and a misleading "✅ Done" summary.

Severity legend: 🔴 Blocker / correctness · 🟠 Bug / likely-wrong · 🟡 Design / robustness ·
🔵 Nice-to-have / polish

---

## 1. 🔴 Blocking / correctness bugs

### 1.1 🔴 `iphone67` preset is shipped in the template but does not exist in the composer

- **Where:** `Templates/capture_screenshots_template.sh:98` & `:126`, `Docs/QuickStart.md:140`,
  `README.md:280`, template comment `:83`.
- **What:** The default `DEVICES` array ships with
  `"iPhone 16 Pro|Files/iPhone16Pro-Frame.png|iphone67|30"`. But `DevicePreset` in
  `Scripts/compose_mockup.swift` only defines `iphone69, iphone65, iphone61, iphone55, iphone47`
  — **there is no `iphone67`**.
- **Effect:** `compose_mockup.swift` hits
  `guard let preset = DevicePreset(rawValue: deviceArg)` → prints
  `❌ Unknown device 'iphone67'` → `exit(1)` for every iPhone 16 Pro screenshot. The very first
  device in the shipped template fails.
- **Fix (pick one):**
  - Add the missing case: `case iphone67 = "iphone67"` with `portraitSize = 1290×2796`
    (this is a real, current App Store size — it *should* exist), **and** add `iphone47` to the
    template's documented preset list (it's implemented but undocumented — the mirror image of
    this bug), or
  - Change the template's default entries to a supported preset (`iphone69`).
- **Recommendation:** Add `iphone67`. It's a legitimate 6.7" slot and its omission is clearly an
  oversight, not a decision.

### 1.2 🔴 Template folder sanitisation strips parentheses; the test's folder keeps them → iPad/Apple TV mockups silently skipped

- **Where:** `Templates/capture_screenshots_template.sh:227-229` (`sanitize_name`) vs
  `Sources/ScreenshotTestBase.swift:150` / example `setUp()`.
- **What:**
  - The XCUITest writes screenshots into a folder named from `UIDevice.current.name` with **only
    spaces replaced** → `iPad_Pro_13-inch_(M5)` (parentheses **kept**).
  - The template computes the lookup folder via
    `sanitize_name() { ... sed 's/(//g' | sed 's/)//g'; }` → `iPad_Pro_13-inch_M5`
    (parentheses **stripped**).
- **Effect:** For any device whose name contains parentheses — **every iPad `(M5)/(M4)` and every
  Apple TV `(3rd generation) (at 1080p)`** — the Step-2 mockup loop looks in a folder that does
  not exist, prints `⚠️ No screenshots found for …`, and skips it. iPhones (no parens) work, which
  is exactly why this slips through casual testing.
- **Note the internal inconsistency:** the *inline* template inside `Docs/DeveloperHowto.md`
  (§8) takes the folder name **verbatim from the `DEVICES` array** (`iPad_Pro_13-inch_(M5)`), so it
  actually matches — but the *shipped* `Templates/capture_screenshots_template.sh` derives it from
  the simulator name and mangles it. The two documented templates disagree.
- **Fix:** Make `sanitize_name` replace only spaces (`tr ' ' '_'`), matching the Swift side
  exactly. Or, better, make both sides call a single documented rule and state it once.

### 1.3 🔴 Failed compositions and failed test runs are counted as successes

Two separate instances of the same class of bug:

- **`Templates/capture_screenshots_template.sh:343-357`:** the `swift compose_mockup … | grep -E "✅|❌|Error"`
  is used as an `if` condition. On failure, `compose_mockup.swift` prints `❌ <error>` to stdout,
  which **matches the grep**, so grep exits 0, the `if` is true, and the run is counted as a
  success (`TOTAL_MOCKUPS++`). Worse, *both* the `then` and `else` branches increment the same
  counters, so failures are structurally invisible. `FAILED_MOCKUPS` is declared (`:286`) and never
  incremented.
- **`Scripts/run_screenshots.sh:262-286`:** the whole `xcodebuild test | grep … | grep … || true`
  pipeline is force-succeeded with `|| true`, then success is judged **solely by
  `if [ -d "$RESULT_BUNDLE" ]`**. But `xcodebuild` creates the `.xcresult` bundle **even when tests
  fail**. So a build/test failure (no screenshots produced) still reports `✅ Done`.
- **Effect:** The summary line lies. A user sees "✅ Done! Mockups generated: N" while some or all
  screens are missing or unframed.
- **Fix:**
  - For compose: capture the swift exit code explicitly
    (`if swift … ; then ok else FAILED_MOCKUPS=$((FAILED_MOCKUPS+1)); fi`) *without* piping through
    grep, or `set -o pipefail` and check `${PIPESTATUS[0]}`.
  - For the test run: inspect the `xcodebuild` exit status (guard the `|| true` so it doesn't mask
    it — e.g. `set -o pipefail; xcodebuild … ; status=${PIPESTATUS[0]}`), or parse
    `xcresulttool`/`** TEST FAILED **` rather than mere bundle existence.

---

## 2. 🟠 Bugs / likely-wrong behaviour

### 2.1 🟠 `--output` does **not** control where screenshots are written

- **Where:** `Scripts/run_screenshots.sh` help text (`:19`) & `--output` handling vs the actual
  writer in `ScreenshotTestBase.setUp()` / subclass.
- **What:** `--output` is only used to name the `.xcresult` bundle path
  (`RESULT_BUNDLE="$OUTPUT_DIR/…"`). The PNGs themselves are written by the *test process* to
  `screenshotsURL`, which is derived from `#file` (or a subclass override) — **completely
  independent of `--output`.** The docs describe `--output` as "Output directory for screenshots /
  result bundles."
- **Effect:** If a user does **not** override `setUp()`, screenshots land next to the compiled
  source. Via SPM that is
  `…/DerivedData/…/SourcePackages/checkouts/ios-screenshot-automator/Screenshots/…` — buried in
  DerivedData, not the project. This is why *every* example overrides `setUp()`; the default is a
  trap.
- **Fix:** Either (a) pass the desired output dir into the test via a launch **environment
  variable** (`app.launchEnvironment["SCREENSHOT_OUT"] = …`) and have `setUp()` prefer it, or
  (b) stop writing to the host filesystem from inside the test entirely and extract from the
  `.xcresult` on the host (see 3.1). At minimum, correct the docs to say `--output` = result
  bundles only.

### 2.2 🟠 `#file`-based project-root detection is fragile and undocumented-by-default

- **Where:** `Sources/ScreenshotTestBase.swift:163-170`.
- **What:** The base writes to `<#file>/../../Screenshots/<device>`. The comment claims two
  `deletingLastPathComponent()` calls reach the project root — true only when the file happens to
  sit exactly two levels under the project *and* `#file` resolves to a path on the host that the
  simulator can write to. When consumed as an SPM package, `#file` points into the package
  checkout, not the user's project.
- **Fix:** Make the default a no-op (write only the XCTAttachment) and require the subclass to opt
  into a host path, or better, drive it via launch environment (2.1).

### 2.3 🟠 `Screenshots` (capital) vs `screenshots` (lower) inconsistency

- **Where:** base class writes `…/Screenshots/…` (`:169`); every example, doc, and script uses
  lowercase `screenshots/…`.
- **Effect:** Works on the default case-insensitive APFS, **breaks on case-sensitive volumes / CI**
  (mockup step won't find the folder). Pick one spelling everywhere. (Docs even show a capital-S
  `Screenshots/` tree in the README output section but lowercase elsewhere.)

### 2.4 🟠 `grep -q "$DEVICE"` availability check over-matches (substring + regex)

- **Where:** `Scripts/run_screenshots.sh:218,226`.
- **What:** `xcrun simctl list devices available | grep -q "$ACTUAL_DEVICE"`:
  - **Substring:** requesting `iPhone 17 Pro` matches the `iPhone 17 Pro Max` line → reports
    "available" when it isn't → later `boot`/`xcodebuild` by that exact name fails.
  - **Regex:** the name is treated as a regex; `.` in `13-inch` etc. are wildcards. Mostly benign,
    but wrong in principle.
- **Fix:** `grep -Fq -- "$ACTUAL_DEVICE"` and ideally anchor to a line/word boundary, or match on
  the device line format from `simctl list devices --json` and resolve to a **UDID** to feed
  `boot`/`-destination id=…`. UDIDs also fix the "ambiguous device name across runtimes" failure
  from `simctl boot`.

### 2.5 🟠 `dismissSystemAlerts()` is English-only, but runs are localised

- **Where:** `Sources/ScreenshotTestBase.swift:778-790`.
- **What:** It taps `springboard.buttons["Allow"]` / `["OK"]`. When `run_screenshots.sh` passes
  `-testLanguage de` (or fr/es…), the permission dialog buttons are localised ("Erlauben", etc.),
  so nothing is dismissed and the alert can block/obscure the first screenshots.
- **Fix:** Match by button index/position, use `addUIInterruptionMonitor`, use
  `simctl privacy … grant` to pre-authorise, or accept a localised label set (mirroring the
  approach already used in `dismissSheet`).

### 2.6 🟠 `TEST_METHOD` is collected but never used

- **Where:** `Templates/capture_screenshots_template.sh:111` (and Quick Start).
- **What:** The template exposes `TEST_METHOD` and calls it a `← CHANGE` field, but the call to
  `run_screenshots.sh` (`:261-268`) never passes it, and `run_screenshots.sh` has no
  `--test-method` flag — it runs `-only-testing:$TEST_TARGET/$TEST_CLASS` (all methods in the
  class). Dead configuration that implies control it doesn't have.
- **Fix:** Either add a `--test-method` flag that appends `/$TEST_METHOD` to `-only-testing`, or
  remove `TEST_METHOD` from the template.

### 2.7 🟠 The two documented templates diverge (flag forwarding, `--landscape`, folder naming)

- **What:** `Templates/capture_screenshots_template.sh` (the file you copy) and the inline template
  in `Docs/DeveloperHowto.md §8` are meaningfully different scripts:
  - The shipped one does its **own** `--iphone-only` filtering and does **not** forward the flag;
    the inline one forwards `"${EXTRA_ARGS[@]}"` into `run_screenshots.sh`, whose `--iphone-only`
    then **overrides `--devices`** with a hard-coded `iPhone 17` list (ignoring the user's device
    map).
  - The shipped one adds `--landscape` for `appletv` (`:339`); the inline one **never** does →
    Apple TV mockups would compose in portrait `1080×1920`.
  - Folder naming differs (see 1.2).
- **Fix:** Keep exactly one canonical template. Have the docs `include`/quote the real file rather
  than maintaining a second, drifting copy.

### 2.8 🟠 Fallback devices can silently produce wrong-sized / wrong-slot screenshots

- **Where:** `Scripts/run_screenshots.sh:72-84,217-239`.
- **What:** If `iPhone 17 Pro Max` (6.9", 1320×2868) is missing, it falls back down the list to
  `iPhone 14 Plus` — which is a **6.5"** device (1284×2778), a *different App Store slot*. The
  on-device `ScreenshotComposer` keeps whatever the simulator produced, so you can end up
  submitting 6.5" images believing they're 6.9".
- **Fix:** Keep fallbacks within the *same size class* only, and warn loudly (or fail) when the
  fallback's native resolution differs from the target preset. The `compose_mockup.swift` canvas
  preset masks this for framed mockups but not for raw output.

### 2.9 🟠 `detectScreenRect` assumes a specific pixel layout that `NSImage.cgImage` does not guarantee

- **Where:** `Scripts/compose_mockup.swift:103-120`.
- **What:** It reads raw bytes assuming 8-bit **RGBA**, alpha at `offset+3`, non-premultiplied,
  in memory order R,G,B,A. `NSImage(contentsOfFile:).cgImage(...)` may hand back BGRA, premultiplied
  alpha, a different `alphaInfo`, or 16-bit components depending on the source PNG. The alpha/RGB
  reads would then be wrong, breaking auto-detection on some perfectly valid frame PNGs.
- **Fix:** First redraw the frame into a **known** context (sRGB, 8-bit,
  `premultipliedLast`) and scan *that* buffer, so the byte layout is guaranteed.

### 2.10 🟠 `detectScreenRect` fails "open" to a whole-image rect

- **Where:** `Scripts/compose_mockup.swift:138-170`.
- **What:** `screenBottom`/`screenRight` initialise to `h-1`/`w-1` and `screenTop`/`screenLeft` to
  `0`. If a directional scan never finds the `opaque→transparent` transition (e.g. odd frame), the
  bounds stay at the image extremes, `screenW/H` pass the `> w/3 && > h/3` sanity check, and the
  function returns "the entire image is the screen." The screenshot then fills the whole frame.
- **Fix:** Track whether each of the four transitions was actually found; if any wasn't, treat
  detection as failed and fall through to Strategy 2 / manual `--screen-rect` / the explicit
  fallback rect.

### 2.11 🟠 Screenshot is stretched into the screen rect (no aspect preservation)

- **Where:** `Scripts/compose_mockup.swift:339` `context.draw(ssCGImage, in: screenDrawRect)`.
- **What:** The screenshot is scaled to *exactly* the detected screen rect. If the screenshot's
  aspect ratio doesn't match the frame's screen area (mismatched frame, fallback device, wrong
  preset), the image is distorted with no warning.
- **Fix:** Aspect-fill + clip (you already clip to the rounded rect), or at least warn when the
  aspect delta exceeds a small threshold.

### 2.12 🟠 XCTAttachment stores the **raw** screenshot even when the on-device composer ran

- **Where:** `Sources/ScreenshotTestBase.swift:247-266`.
- **What:** When `composerConfig != nil`, the **file on disk** is the composed image, but the
  `.xcresult` attachment (`:263`) is built from the *raw* `screenshot`. CI reviewers looking at the
  test bundle see un-composed images; the on-disk artifacts differ from the attachments.
- **Fix:** Attach the same bytes you wrote (`XCTAttachment(data: imageData, uniformTypeIdentifier:
  "public.png")`).

---

## 3. 🟡 Design / architecture / robustness

### 3.1 🟡 Writing PNGs to the host filesystem from inside the UITest is an anti-pattern

The whole "derive project root from `#file`, then `imageData.write(to:)`" mechanism only works
because the simulator shares the host filesystem and the path happens to be writable. It's the root
cause of 2.1/2.2/2.3. The canonical, robust pattern is:

- In-test: only `add(XCTAttachment(...))` with `.keepAlways`.
- On host: extract with `xcrun xcresulttool` (or `xcparse`) after `xcodebuild` finishes.

This removes `screenshotsURL`, the `#file` gymnastics, the capital/lowercase mismatch, and makes
`--output` meaningful. Strongly recommended as the v2 direction. (If you keep host-writes, at least
pass the target dir through `launchEnvironment`.)

### 3.2 🟡 Two independent compositors that will double-frame if combined

There are **two** framing engines:
- `Sources/ScreenshotComposer.swift` — runs *inside the test* (UIKit), draws a **synthetic** bezel,
  no real frame PNG.
- `Scripts/compose_mockup.swift` — runs *on the host* (AppKit/CoreGraphics), uses a **real** frame
  PNG.

If a user sets `composerConfig` **and** runs the shell pipeline (the default full run), the mockup
script composes a device frame around an image that already has a synthetic frame → **frame within
a frame**. Nothing warns about this. The relationship between the two is never spelled out.
- **Fix:** Document them as mutually exclusive, and/or have the pipeline detect/skip already-composed
  screenshots. Consider whether both need to exist — the synthetic composer is the weaker of the
  two (fake bezel) and adds a lot of surface area.

### 3.3 🟡 `swift compose_mockup.swift` recompiles the script for every single image

- **Where:** template loops call `swift "$COMPOSE_SCRIPT" …` once per screenshot.
- **What:** Running via the `swift` interpreter recompiles ~500 lines each invocation. For
  N devices × M languages × K screens that's a lot of redundant compilation → slow runs.
- **Fix:** `swiftc -O "$COMPOSE_SCRIPT" -o /tmp/compose_mockup` once, then invoke the binary in the
  loop; or make the script accept a batch/manifest and process a whole folder in one process.

### 3.4 🟡 `continueAfterFailure = false` throws away partial screenshot output

For a screenshot tool, a single flaky navigation aborts the entire remaining capture. Since all
screens run in one `testTakeAllScreenshots`, you lose everything after the first failure.
- **Fix:** Consider `continueAfterFailure = true` for capture runs, and/or wrap each screen in a
  soft try so one bad screen doesn't kill the rest. At minimum make it overridable.

### 3.5 🟡 `captureAllScreens()` default is `fatalError`

- **Where:** `:221-230`. Not overriding it crashes the runner instead of failing gracefully.
- **Fix:** `XCTFail("override captureAllScreens()")` (or `throw XCTSkip(...)`) reads better in
  reports and doesn't take the process down.

### 3.6 🟡 No status-bar override → clock/battery/carrier vary between runs

App Store screenshots conventionally show a clean status bar (9:41, full signal, full battery).
Nothing calls `xcrun simctl status_bar <udid> override …`. Screenshots will show real simulator
time and a possibly-charging battery.
- **Fix:** Add a `status_bar override` step (time `9:41`, `wifiBars 3`, `cellularBars 4`,
  `batteryState charged`, `batteryLevel 100`) before capture, and clear it after.

### 3.7 🟡 Navigation relies on brittle heuristics rather than a stable contract

The 6-strategy iPad cascade and the label-scanning are clever but inherently fragile (localised
labels, partial `contains` matching that can mis-hit, coordinate taps at `(0.5,0.5)`). The robust
contract is **accessibility identifiers** (stable, non-localised) rather than labels.
- **Fix:** Prefer `.accessibilityIdentifier` lookups first; document that apps should tag tabs with
  stable identifiers. Keep the heuristic cascade as a fallback.

### 3.8 🟡 Device-name sanitisation logic is duplicated in ≥3 places

`deviceName.replacingOccurrences(of: " ", with: "_")` appears in `setUp()`, in `takeScreenshot()`,
and in every example's `setUp()`. Divergence here is exactly what caused 1.2.
- **Fix:** One `static func sanitized(_ name: String) -> String` used everywhere (Swift + a mirror
  in shell).

### 3.9 🟡 `screenshotsURL` defaults to `URL(fileURLWithPath: "")`

A footgun: if `setUp()` is bypassed or the assignment reordered, writes go to a nonsense path.
Prefer an optional (`URL?`) that forces an explicit decision, or a computed temp-dir default.

### 3.10 🟡 Library target links `XCTest`; consumed as a normal product

`ScreenshotAutomator` is a plain `.target` (library) that `import XCTest`. It only makes sense
linked into a UI-test bundle. Declaring it as a regular library invites "XCTest not found" / linker
issues if someone links it into the app target by mistake, and muddies SPM resolution.
- **Fix:** Document emphatically "UITest target only" (the README does, good), and consider whether
  the composer (pure UIKit, testable) should be split from the XCTest-dependent base so at least
  part is usable/unit-testable without XCTest.

### 3.11 🟡 The package that automates *testing* has **no tests** of its own

`Package.swift` has no test target. `detectScreenRect`, `scaleRect`, `frameRect`,
`mapRectToCanvas`, `hexToNSColor`, and the gradient math are all pure, deterministic, and eminently
unit-testable — and they're where the subtle bugs live (2.9, 2.10, 2.11).
- **Fix:** Add a macOS unit-test target covering the geometry/color helpers with fixture PNGs.

---

## 4. 🔵 Minor / polish / consistency

- **4.1 🔵 Corner-radius docs vs code disagree for Apple TV.** `compose_mockup.swift:319` uses
  `0.0`; `DeveloperHowto.md:528` says `0.01`; `ScreenshotComposer.swift` uses `0.02` for `.tv`.
  Pick one and cite it consistently.
- **4.2 🔵 `iphone65` preset labelling.** Enum `iphone65 = 1242×2688` is labelled "iPhone 14 Plus /
  13 Pro Max", but the iPhone 14 Plus is actually **1284×2778**. `AppStoreDevices.iPhone6_5`
  comment says 1284×2778. The 6.5" slot accepts both, but the mapping/labels are muddled — worth a
  clarifying comment.
- **4.3 🔵 `hexToNSColor` fails silently to `.systemBlue`** on a malformed hex (`compose_mockup.swift:415`).
  A typo'd gradient color yields blue with no warning. Print a warning at least.
- **4.4 🔵 Redundant delays.** `takeScreenshot()` sleeps `animationDelay`, and every example also
  `sleep(1)` right before/after. Both fixed `sleep(1)` and the overridable `*Delay` constants are
  used inconsistently; consolidate on the overridable constants.
- **4.5 🔵 `dismissSheet()` Strategy 1 "tap the first nav-bar button" is risky.** On a non-modal
  screen the first nav-bar button might be *Back* or *Edit*, causing unwanted navigation. Gate it
  more tightly (only when a modal is actually detected).
- **4.6 🔵 `ensureMainViewVisible()` / `tapPlusButton()` German-only heuristics** (`hinzufügen`,
  `neu`, `Abbrechen`, `Schließen`, `Fertig`) — fine, but hard-coding one extra language hints the
  list should be data-driven / injectable rather than English+German forever.
- **4.7 🔵 `run_screenshots.sh` help/examples still reference "Plantner"** (`:26`, defaults
  `:64-67`). The extracted generic tool ships with a specific app's names as defaults; a new user
  running it with no args tries to build `Plantner.xcodeproj`. Prefer neutral placeholders or no
  runnable default.
- **4.8 🔵 `sleep 2` / `sleep 3` fixed simulator waits** are guesswork; `simctl bootstatus -b`
  waits deterministically for boot completion and is faster + more reliable.
- **4.9 🔵 Manual `simctl boot` + `-destination …,OS=latest`** can target different runtimes than
  the one you booted; let `xcodebuild` manage the sim, or boot by UDID and destine by `id=`.
- **4.10 🔵 `Apple?TV` glob** (`*Apple?TV*`) matches any single char, incl. "AppleXTV". Cosmetic;
  `*"Apple TV"*` is clearer.
- **4.11 🔵 Docs line-count claims drift** ("768 lines", "363 lines" in `ScreenshotPipeline.md`) —
  these will rot; drop hard numbers or generate them.
- **4.12 🔵 `.gitignore` ignores `fastlane/screenshots/**` but the tool writes to `screenshots/`
  and `Appstore Mockups/`.** Neither is ignored, so generated artefacts can accidentally be
  committed. Add them (or document that they're intended to be committed).
- **4.13 🔵 `MockDataProviderExample.swift` ships as one big block comment.** The protocol
  `ScreenshotMockDataProvider` is empty (no requirements), so it provides no compile-time guidance.
  Consider a minimal, *uncommented*, compiling skeleton behind `#if DEBUG` instead.
- **4.14 🔵 `-testLanguage` sets language but not `-testRegion`.** Date/number/currency formatting
  in screenshots may not match the target locale. Consider exposing region too.

---

## 5. What's genuinely good (keep doing this)

- **Documentation quality is excellent** — Quick Start, Developer How-To, and the Pipeline doc are
  thorough, with diagrams, tables, troubleshooting matrices, and CI recipes. This is well above the
  norm for a utility repo.
- **The `open`-everything design** (overridable class vars, `open func`) makes the base class
  genuinely extensible.
- **Clear separation of runtime flags** (`--mockups-only`, `--iphone-only`) and sensible per-device
  argument parsing with whitespace trimming.
- **Thoughtful edge handling** in places: reversing an inner path to punch the bezel hole
  (`drawDeviceFrame`), scanning at `x=w/4` to dodge the notch, the two-context opaque-flatten to
  satisfy App Store's no-alpha rule, per-platform fallback lists split so iOS never falls back to
  tvOS.
- **The `flipY` coordinate handling** and the FAQ entry documenting the historical upside-down bug
  show good institutional memory.

---

## 6. Suggested fix priority

| # | Item | Severity | Effort | Priority |
|---|------|----------|--------|----------|
| 1.1 | Add `iphone67` preset (or fix template default) | 🔴 | XS | **Do first** |
| 1.2 | `sanitize_name` parens mismatch | 🔴 | XS | **Do first** |
| 1.3 | Failures counted as success (both scripts) | 🔴 | S | **Do first** |
| 2.1/2.2/3.1 | Screenshot output path via env / xcresult extraction | 🟠/🟡 | M | High |
| 2.3 | `Screenshots` vs `screenshots` casing | 🟠 | XS | High |
| 2.4 | Exact device match + UDIDs | 🟠 | S | High |
| 2.7 | Deduplicate the two templates | 🟠 | S | High |
| 2.5 | Localised system-alert dismissal | 🟠 | S | Medium |
| 2.9/2.10/2.11 | Harden `detectScreenRect` + aspect | 🟠 | M | Medium |
| 3.2 | Document/guard the two compositors | 🟡 | S | Medium |
| 3.6 | Status-bar override | 🟡 | S | Medium |
| 3.11 | Add a unit-test target for the pure helpers | 🟡 | M | Medium |
| §4 | Consistency/polish batch | 🔵 | — | Low |

---

## 7. Concrete first-PR checklist (the three blockers)

1. `Scripts/compose_mockup.swift`: add
   `case iphone67 = "iphone67"` → `portraitSize` `CGSize(width: 1290, height: 2796)` + displayName;
   add `iphone47` to the template's documented preset list.
2. `Templates/capture_screenshots_template.sh`: change `sanitize_name` to replace **only spaces**
   (drop the two `sed` parens-strippers) so it matches the Swift folder name.
3. Both scripts: stop treating "bundle exists" / "grep matched" as success — check the real exit
   status (`set -o pipefail` + `${PIPESTATUS[0]}`), and actually increment `FAILED_*`.

Each is a few lines and independently shippable.
