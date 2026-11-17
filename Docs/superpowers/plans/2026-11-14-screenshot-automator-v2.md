# ios-screenshot-automator 2.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aus einer App mit einer `screenshots.json` und einem Befehl ein wiederholbares Set App-Store-fertiger Screenshots für iPhone, iPhone Duo, iPad, Apple TV, Mac und Apple Watch erzeugen.

**Architecture:** Ein Swift-Paket mit vier Targets. `ScreenshotAutomator` ist die dünne XCUITest-Bibliothek in der App (navigieren, `shot()` als Testanhang). `ScreenshotCore` enthält die gesamte Mac-seitige Logik (Konfiguration, Größentabelle, Gerätekatalog, Planung, `xcodebuild`/`simctl`-Aufrufe, Export, Zusammensetzen, Prüfen). `screenshots` ist die Kommandozeilen-Hülle. `ScreenshotProtocol` ist der winzige gemeinsame Vertrag zwischen Test und Werkzeug.

**Tech Stack:** Swift 6 (tools-version 6.0), Xcode 27.1, Swift Testing (`#expect`) für Unit-Tests, XCTest/XCUIAutomation, CoreGraphics/CoreText/ImageIO, `xcodebuild`, `xcrun simctl`, `xcrun xcresulttool`, swift-argument-parser, XcodeGen (nur zum Erzeugen der Beispiel-App).

**Spec:** `Docs/superpowers/specs/2026-11-14-screenshot-automator-v2-design.md` — vor jeder Aufgabe lesen; der Plan argumentiert daraus.

## Global Constraints

- Arbeitszweig `v2` (bereits angelegt, abgezweigt von `origin/main`). Nicht auf `main` oder dem alten Zweig `copilot/add-apple-tv-screenshot-support` arbeiten.
- Einzige Paket-Abhängigkeit: `swift-argument-parser`. Keine weitere ohne Rückfrage.
- Produktname der Testbibliothek bleibt `ScreenshotAutomator`.
- Plattform-Untergrenzen in `Package.swift`: iOS 17, tvOS 17, watchOS 10, macOS 14. Werkzeug setzt Xcode 27 voraus.
- Kein Apple-eigenes Bildmaterial im Repo oder in Ausgaben (keine Bezels, keine Sensor-PDFs, auch nicht als Test-Fixture).
- Kein Skript, das Nutzer kopieren oder anpassen müssen. In App-Repos stehen keine Gerätenamen, Pixelgrößen oder Margins.
- Externe Programme werden immer mit Argument-Array gestartet, nie über eine Shell-Zeichenkette.
- Jeder Befehl endet mit Exit-Code ≠ 0, wenn ein angefordertes Bild fehlt oder eine Prüfung fehlschlägt. Erfolg wird nie aus „Datei existiert" oder Textsuche in Logs abgeleitet.
- Fehlt ein passender Simulator, ist das ein Fehler; es wird nie auf eine andere Größe ausgewichen.
- `StoreSizes.swift` ist die einzige Stelle mit App-Store-Pixelgrößen; sie trägt Prüfdatum `2026-11-14` und die Quell-URL.
- Standard-Startargumente: `-UITEST`, `-LOAD_MOCK_DATA`, `-DISABLE_ANIMATIONS`, `-SKIP_ONBOARDING`.
- Statusleiste: Zeit `9:41`, Akku geladen 100 %, WLAN 3 Balken, Mobilfunk 4 Balken.
- `xcodebuild`-Testläufe immer mit `-parallel-testing-enabled NO` (behebt Issue #5).
- Commits klein und pro Aufgabe; nichts pushen, kein Tag, kein PR ohne ausdrückliche Anweisung von Matthias.

## Review Focus

Fälle, die das Design nahelegt, aber nicht ausbuchstabiert. Jeder hat einen Test in der genannten Aufgabe.

1. **Ein Simulator ist schon gebootet** (Matthias hat meist einen offen): Das Werkzeug fährt nur Simulatoren herunter, die es selbst gestartet hat, und räumt die Statusleisten-Überschreibung in jedem Fall wieder ab. → Aufgabe 6
2. **Ein Test läuft grün, liefert aber kein oder ein doppeltes Bild:** gilt als Fehler mit Nennung von Größe, Sprache und Shot-Name. → Aufgabe 7
3. **Pfade und Scheme-Namen mit Leerzeichen** (1.x hatte `Appstore Mockups`): funktionieren unverändert. → Aufgabe 6
4. **Titel passen nicht zur Sprachenliste** (Konfiguration `de-DE`, Titel unter `de`; oder Titel fehlt für eine Sprache): klare Fehlermeldung mit Feldpfad statt Bild ohne Text. → Aufgabe 2
5. **Sehr lange Titel, Umlaute, Emoji, nicht-lateinische Schrift:** Text wird verkleinert und umbrochen, nie abgeschnitten und ragt nie in das Gerät. → Aufgabe 9

---

## Dateistruktur

```
Package.swift
Sources/
  ScreenshotProtocol/ShotProtocol.swift        Vertrag: Anhangsname, Umgebungsvariablen, Version
  ScreenshotAutomator/ScreenshotTestCase.swift Basisklasse für UI-Tests
  ScreenshotCore/
    Model.swift            PixelSize, Platform, Appearance, LocaleCode
    Config.swift           screenshots.json: Typen, Laden, Prüfen
    StoreSizes.swift       App-Store-Größentabelle
    DeviceCatalog.swift    Gerätetypen und Simulatoren aus simctl + Plists
    Planner.swift          Konfiguration → CaptureRun-Liste
    Shell.swift            CommandRunning, ProcessRunner
    Runner.swift           xcodebuild/simctl-Ablauf für einen CaptureRun
    Exporter.swift         xcresult → raw/
    Layout.swift           Geometrie: Geräte-Rechteck, Titelbereich, Radien
    Composer.swift         Hintergrund, Rahmen, Titel, PNG ohne Alpha
    FrameImage.swift       Bildschirmbereich in eigenem Rahmen-PNG finden
    Validator.swift        Prüfung der fertigen Bilder
    Report.swift           index.html
    Pipeline.swift         Ablauf capture → compose → validate
    ProjectInspector.swift Projekt, Schemes, UI-Test-Targets erkennen
    InitWizard.swift       Fragen → Config + Test-Gerüst
  screenshots/Main.swift   ArgumentParser-Befehle
Tests/
  ScreenshotProtocolTests/ShotProtocolTests.swift
  ScreenshotCoreTests/     eine Testdatei je Quelldatei, plus Support/TestImage.swift, Support/FakeRunner.swift, Fixtures/
Example/
  project.yml, Demo.xcodeproj (erzeugt, eingecheckt), Shared/, DemoUITests/, DemoTV*/, DemoMac*/, DemoWatch*/, screenshots.json
Scripts/install.sh
Docs/Reference.md, README.md
```

Gelöscht in Aufgabe 1: `Sources/ScreenshotTestBase.swift`, `Sources/ScreenshotComposer.swift`, `Scripts/run_screenshots.sh`, `Scripts/compose_mockup.swift`, `Templates/`, `Examples/`. Die alten Dokumente fallen in Aufgabe 17.

---

## Phase 1 — Fundament und reine Logik

### Task 1: Paketgerüst und Vertrag

**Files:**
- Create: `Package.swift` (ersetzen), `Sources/ScreenshotProtocol/ShotProtocol.swift`, `Tests/ScreenshotProtocolTests/ShotProtocolTests.swift`, `Sources/ScreenshotCore/Model.swift`, `Sources/screenshots/Main.swift`, `Sources/ScreenshotAutomator/ScreenshotTestCase.swift` (leere Klasse), `.github/workflows/ci.yml`
- Delete: siehe Dateistruktur

**Interfaces — Produces:**
```swift
// ScreenshotProtocol
public enum ShotProtocol {
    public static let version = 2
    public static let attachmentPrefix = "sa2v2__"
    public enum Env { public static let display = "SA2_DISPLAY", landscape = "SA2_LANDSCAPE", appearance = "SA2_APPEARANCE" }
    public enum Parsed: Equatable { case shot(String); case otherVersion(Int) }
    public static func isValidShotName(_ name: String) -> Bool        // ^[A-Za-z0-9][A-Za-z0-9_-]*$
    public static func attachmentName(for shot: String) -> String     // "sa2v2__" + shot
    public static func parse(attachmentName: String) -> Parsed?
}
// ScreenshotCore/Model.swift
public struct PixelSize: Hashable, Codable, Sendable { public var width: Int, height: Int; public var swapped: PixelSize; public var isLandscape: Bool }
public enum Platform: String, Codable, CaseIterable, Sendable { case iOS, tvOS, watchOS, macOS }
public enum Appearance: String, Codable, Sendable { case light, dark }
public enum LocaleCode { public static func split(_ code: String) -> (language: String, region: String?) }
```

- [x] **Step 1:** Der Zweig `v2` existiert bereits (von `origin/main` abgezweigt, enthält Plan und Design): `git switch v2`. Dann die 1.x-Dateien löschen.
- [x] **Step 2:** `Package.swift` schreiben: Produkte `.library("ScreenshotAutomator")`, `.executable("screenshots")`; Targets `ScreenshotProtocol`, `ScreenshotAutomator` (hängt an `ScreenshotProtocol`), `ScreenshotCore` (hängt an `ScreenshotProtocol`), `screenshots` (hängt an `ScreenshotCore`, `ArgumentParser`), Test-Targets `ScreenshotProtocolTests`, `ScreenshotCoreTests` (mit `resources: [.copy("Fixtures")]`).
- [x] **Step 3: Fehlschlagende Tests schreiben** in `ShotProtocolTests`:
```swift
#expect(ShotProtocol.attachmentName(for: "01_Home") == "sa2v2__01_Home")
#expect(ShotProtocol.parse(attachmentName: "sa2v2__01_Home") == .shot("01_Home"))
#expect(ShotProtocol.parse(attachmentName: "sa2v2__01_Home_0_5F2C1E9A-1B2C-4D3E-8F90-123456789ABC.png") == .shot("01_Home"))
#expect(ShotProtocol.parse(attachmentName: "sa2v3__x") == .otherVersion(3))
#expect(ShotProtocol.parse(attachmentName: "Screenshot_1") == nil)
#expect(ShotProtocol.isValidShotName("01_Home-dark") && !ShotProtocol.isValidShotName("a b") && !ShotProtocol.isValidShotName("../x") && !ShotProtocol.isValidShotName(""))
#expect(LocaleCode.split("de-DE") == ("de", "DE")); #expect(LocaleCode.split("zh-Hans") == ("zh-Hans", nil)); #expect(LocaleCode.split("fr") == ("fr", nil))
```
(`LocaleCode`-Tests in `ScreenshotCoreTests/ModelTests.swift`. Regel: zweiter Teil aus genau zwei Großbuchstaben = Region.)
- [x] **Step 4:** `swift test` → schlägt fehl (Symbole fehlen). Implementieren. `swift test` → grün.
- [x] **Step 5:** `swift build` und `xcodebuild -scheme ScreenshotAutomator -destination 'generic/platform=iOS Simulator' build` → beide erfolgreich. Schlägt `import XCTest` im Bibliotheks-Target unter `swift build` fehl, `ScreenshotAutomator` per `#if canImport(XCTest)` kapseln und das hier vermerken.
- [x] **Step 6:** `ci.yml`: macOS-Runner, `swift build`, `swift test`. Commit `chore: v2 package skeleton and shot protocol`.

### Task 2: Konfiguration laden und prüfen

**Files:** Create `Sources/ScreenshotCore/Config.swift`, `Tests/ScreenshotCoreTests/ConfigTests.swift`, `Tests/ScreenshotCoreTests/Fixtures/plantner.json` (das Beispiel aus Spec 5.3)

**Interfaces — Produces:**
```swift
public struct Config: Codable, Equatable, Sendable {
    public var version: Int
    public var project: String?; public var workspace: String?
    public var targets: [Target]
    public var languages: [String]
    public var appearances: [Appearance]          // Standard [.light]
    public var permissions: [String]              // Standard []
    public var style: Style
    public var sizeStyles: [String: Style]        // Standard [:], ersetzt style für diese Größen-ID vollständig
    public var shots: [String: Shot]              // Standard [:]
    public var macCanvas: PixelSize               // Standard 2880×1800
    public var output: String                     // Standard "screenshots"
    public struct Target: Codable, Equatable, Sendable { public var platform: Platform; public var scheme: String; public var tests: String; public var sizes: [String]; public var landscape: [String] /* Standard [] */ }
    public struct Style: Codable, Equatable, Sendable { public var background: Background; public var frame: Frame; public var frameColor: String /* "#000000" */; public var frameImage: String?; public var caption: Caption? }
    public enum Frame: String, Codable, Sendable { case outline, bezel, image, none }
    public enum Background: Codable, Equatable, Sendable { case color(String); case gradient([String], angle: Double) }   // JSON {"color": "#fff"} bzw. {"gradient": [...], "angle": 135}
    public struct Caption: Codable, Equatable, Sendable { public var color: String /* "#FFFFFF" */; public var position: Position /* .top */; public var font: String?; public enum Position: String, Codable, Sendable { case top, bottom } }
    public struct Shot: Codable, Equatable, Sendable { public var title: [String: String]?; public var subtitle: [String: String]? }
    public static func load(from url: URL) throws -> Config        // wirft ConfigError
    public func issues() -> [ConfigIssue]                           // leere Liste = gültig
    public func style(forSize id: String) -> Style
}
public struct ConfigIssue: Equatable, Sendable { public var path: String; public var message: String }
public enum ConfigError: Error, Equatable { case unreadable(String); case invalid([ConfigIssue]) }
public struct RGBA: Equatable, Sendable { public init?(hex: String) }   // "#RGB" und "#RRGGBB"
```

- [x] **Step 1: Fehlschlagende Tests.** Fixture lädt und liefert `languages == ["de-DE","en-US"]`, `targets[0].sizes.count == 5`, `style.frame == .outline`, Standardwerte `output == "screenshots"`, `appearances == [.light]`, `macCanvas == PixelSize(width: 2880, height: 1800)`. Dazu je ein Test, der genau ein `ConfigIssue` mit diesem `path` erwartet:

| Eingabe | `path` |
|---|---|
| `version: 1` | `version` |
| `project` und `workspace` beide gesetzt, oder keines | `project` |
| `languages: []` | `languages` |
| `targets[0].tests: "NurTarget"` (kein `/`) | `targets[0].tests` |
| `landscape` nennt Größe, die nicht in `sizes` steht | `targets[0].landscape` |
| `style.frame: "image"` ohne `frameImage` | `style.frameImage` |
| Farbe `"#12"` | `style.background` |
| Shot-Name `"a b"` | `shots.a b` |
| Titel-Schlüssel `de`, Sprache `de-DE` (Review Focus 4) | `shots.01_Home.title.de` |
| Titel für `de-DE`, fehlt für `en-US` (Review Focus 4) | `shots.01_Home.title.en-US` |

- [x] **Step 2:** `swift test --filter ConfigTests` → rot. Implementieren (eigene `init(from:)` für Standardwerte und `Background`). → grün.
- [x] **Step 3:** Commit `feat(core): config model with validation`.

### Task 3: Größentabelle

**Files:** Create `Sources/ScreenshotCore/StoreSizes.swift`, `Tests/ScreenshotCoreTests/StoreSizesTests.swift`

**Interfaces — Produces:**
```swift
public struct StoreSize: Equatable, Sendable { public var id: String; public var platform: Platform; public var label: String; public var pixelSizes: [PixelSize] /* Hochformat, bevorzugte zuerst */; public var family: Family; public var requiredWithinFamily: Bool; public enum Family: String, Sendable { case iPhone, iPad, appleTV, mac, watch } }
public enum StoreSizes { public static let lastVerified = "2026-11-14"; public static let source = "https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications"; public static let all: [StoreSize]; public static func size(id: String) -> StoreSize? }
```

Exakte Tabelle (Breite×Höhe):

| id | platform | family | Pflicht | pixelSizes |
|---|---|---|---|---|
| `iphone-6.3` | iOS | iPhone | ja | 1206×2622, 1179×2556 |
| `iphone-6.9` | iOS | iPhone | nein | 1320×2868, 1290×2796, 1260×2736 |
| `iphone-duo-outer` | iOS | iPhone | nein | 1398×2034 |
| `iphone-duo-inner` | iOS | iPhone | nein | 2007×2853 |
| `ipad-13` | iOS | iPad | ja | 2064×2752, 2048×2732 |
| `ipad-11` | iOS | iPad | nein | 1668×2420, 1668×2388, 1640×2360, 1488×2266, 1512×2316 |
| `appletv` | tvOS | appleTV | ja | 1080×1920, 2160×3840 (immer quer verwendet) |
| `mac` | macOS | mac | ja | 1800×2880, 1600×2560, 900×1440, 800×1280 (immer quer) |
| `watch-ultra` | watchOS | watch | nein | 422×514, 410×502 |
| `watch-series` | watchOS | watch | nein | 416×496, 396×484 |
| `watch-se` | watchOS | watch | nein | 368×448 |

- [x] **Step 1: Tests:** `size(id: "iphone-duo-outer")?.pixelSizes == [PixelSize(width: 1398, height: 2034)]`; `size(id: "iphone-6.3")?.requiredWithinFamily == true`; alle IDs eindeutig; jede `pixelSizes`-Angabe ist Hochformat (`width < height`); `size(id: "iphone-6.7") == nil`.
- [x] **Step 2:** rot → implementieren → grün. Commit `feat(core): app store size table`.

### Task 4: Gerätekatalog

**Files:** Create `Sources/ScreenshotCore/Shell.swift`, `Sources/ScreenshotCore/DeviceCatalog.swift`, `Tests/ScreenshotCoreTests/Support/FakeRunner.swift`, `Tests/ScreenshotCoreTests/DeviceCatalogTests.swift`, `Tests/ScreenshotCoreTests/Fixtures/devicetypes.json`, `devices.json`, `capabilities-*.plist` (handgeschrieben, nur benötigte Schlüssel, Werte aus Spec Abschnitt 3)

**Interfaces — Produces:**
```swift
public struct CommandResult: Sendable { public var exitCode: Int32; public var stdout: Data; public var stderr: Data }
public protocol CommandRunning: Sendable { func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult }
public struct ProcessRunner: CommandRunning { public init(echo: Bool = false) }
// Test: final class FakeRunner: CommandRunning — zeichnet Aufrufe in `calls: [[String]]` auf, Antworten per `stub(prefix: [String], result: CommandResult)`

public struct CornerRadii: Equatable, Sendable { public var upperLeft, upperRight, lowerLeft, lowerRight: Double }   // in Punkten
public struct DisplaySpec: Equatable, Sendable { public var name: String; public var pixelSize: PixelSize; public var scale: Double; public var cornerRadii: CornerRadii }
public struct DeviceType: Equatable, Sendable { public var identifier, name, family: String; public var minRuntimeVersion: Int; public var displays: [DisplaySpec]; public var hasDynamicIsland: Bool }
public struct Simulator: Equatable, Sendable { public var udid, name, deviceTypeIdentifier, runtimeIdentifier: String; public var isBooted: Bool }
public struct DeviceCatalog: Sendable {
    public var deviceTypes: [DeviceType]; public var simulators: [Simulator]
    public static func load(shell: CommandRunning) throws -> DeviceCatalog
    public static func parseCapabilities(_ plist: Data, name: String) throws -> (displays: [DisplaySpec], hasDynamicIsland: Bool)
}
```
Quellen: `xcrun simctl list -j devicetypes` (Felder `name`, `identifier`, `productFamily`, `bundlePath`, `minRuntimeVersion`), `xcrun simctl list -j devices available` (Wörterbuch Laufzeit → Liste mit `udid`, `name`, `deviceTypeIdentifier`, `state`), `<bundlePath>/Contents/Resources/capabilities.plist` → `capabilities.displays[]` mit `displayType == "integrated"` (`deviceName`, `width`, `height`, `scale`, `cornerRadiusUL/UR/LL/LR`) und `capabilities.DeviceSupportsDynamicIsland`. Hat ein Gerät kein integriertes Display (Apple TV), ein Display `primary` aus `ScreenDimensionsCapability` (`main-screen-width/-height/-scale`) mit Radien 0 bilden.

- [x] **Step 1: Tests** gegen die Fixtures:
```swift
let duo = try DeviceCatalog.parseCapabilities(fixture("capabilities-duo.plist"), name: "iPhone Duo")
#expect(duo.displays.map(\.name) == ["primary", "primary-1"])
#expect(duo.displays[0].pixelSize == PixelSize(width: 1398, height: 2034))
#expect(duo.displays[0].cornerRadii == CornerRadii(upperLeft: 8, upperRight: 59, lowerLeft: 8, lowerRight: 59))
#expect(duo.displays[1].pixelSize == PixelSize(width: 2007, height: 2853))
let tv = try DeviceCatalog.parseCapabilities(fixture("capabilities-appletv.plist"), name: "Apple TV")
#expect(tv.displays == [DisplaySpec(name: "primary", pixelSize: .init(width: 1920, height: 1080), scale: 1, cornerRadii: .init(upperLeft: 0, upperRight: 0, lowerLeft: 0, lowerRight: 0))])
```
plus `load(shell:)` mit `FakeRunner`: liefert 3 Gerätetypen und 2 Simulatoren, `isBooted` korrekt aus `state == "Booted"`; ein Gerätetyp mit unlesbarer Plist wird übersprungen statt den Lauf abzubrechen.
- [x] **Step 2:** rot → implementieren → grün.
- [x] **Step 3:** Rauchtest gegen die echte Maschine: temporärer Test `DeviceCatalog.load(shell: ProcessRunner())` enthält einen Typ `iPhone Duo` mit zwei Displays. Danach als `.disabled("needs local Xcode")` markieren. Commit `feat(core): device catalog from simulator profiles`.

### Task 5: Planer

**Files:** Create `Sources/ScreenshotCore/Planner.swift`, `Tests/ScreenshotCoreTests/PlannerTests.swift`

**Interfaces:**
- Consumes: `Config`, `StoreSizes`, `DeviceCatalog`
- Produces:
```swift
public struct CaptureRun: Equatable, Sendable {
    public var target: Config.Target; public var size: StoreSize
    public var simulator: Simulator?          // nil nur bei macOS
    public var display: DisplaySpec?          // nil nur bei macOS
    public var deviceTypeName: String?
    public var hasDynamicIsland: Bool         // aus DeviceType, false bei macOS
    public var language: String; public var appearance: Appearance; public var landscape: Bool
    public var slug: String                   // "<size.id>_<language>_<appearance>"
}
public struct RunFilter: Equatable, Sendable { public var sizes: Set<String>?; public var languages: Set<String>?; public var scheme: String? ; public init() }
public enum PlanError: Error, Equatable { case unknownSize(String); case wrongPlatform(size: String, expected: Platform); case noSimulator(size: String, wanted: [PixelSize]) }
public enum Planner { public static func plan(config: Config, catalog: DeviceCatalog, filter: RunFilter) throws -> [CaptureRun] }
```
Auswahlregel: Kandidaten sind Gerätetypen mit einem Display, dessen `pixelSize` in `size.pixelSizes` liegt (bei tvOS gegen `swapped` vergleichen) **und** für die ein Simulator existiert. Sortierung: Position der Pixelgröße in `size.pixelSizes`, dann höchste `minRuntimeVersion`, dann Name. Vom gewählten Typ der Simulator mit der höchsten `runtimeIdentifier`. `landscape` ist `true` für tvOS und macOS, sonst wenn die Größe in `target.landscape` steht. Reihenfolge der Läufe: Target → Größe → Sprache → Appearance.

- [x] **Step 1: Tests:** `iphone-6.3` wählt „iPhone 18 Pro" vor „iPhone 17 Pro"; `iphone-duo-outer` und `iphone-duo-inner` wählen denselben Simulator mit `display.name` `primary` bzw. `primary-1`; 2 Größen × 2 Sprachen × 2 Appearances = 8 Läufe in definierter Reihenfolge; `slug == "iphone-6.3_de-DE_light"`; ohne passenden Simulator `PlanError.noSimulator(size: "ipad-13", wanted: [2064×2752, 2048×2732])` — **auch wenn** ein iPad 11" installiert ist; `ipad-13` in einem tvOS-Target → `.wrongPlatform`; `mac` → `simulator == nil`, `landscape == true`; Filter `sizes: ["iphone-6.3"]` reduziert korrekt.
- [x] **Step 2:** rot → implementieren → grün. Commit `feat(core): capture planner`.

---

## Phase 2 — Aufnahmeweg (iOS)

### Task 6: Testbibliothek, Beispiel-App (iOS) und Runner

**Files:**
- Create: `Sources/ScreenshotAutomator/ScreenshotTestCase.swift`, `Example/project.yml`, `Example/Shared/*.swift`, `Example/DemoUITests/Screenshots.swift`, `Example/screenshots.json`, `Sources/ScreenshotCore/Runner.swift`, `Tests/ScreenshotCoreTests/RunnerTests.swift`

**Interfaces — Produces:**
```swift
// ScreenshotAutomator
open class ScreenshotTestCase: XCTestCase {
    public private(set) var app: XCUIApplication!
    open class var launchArguments: [String] { get }      // die vier Standardargumente
    open class var settleDelay: TimeInterval { get }      // 0.5
    public func launch(extraArguments: [String] = [], environment: [String: String] = [:])
    public func shot(_ name: String, file: StaticString = #filePath, line: UInt = #line)
    public func tap(id: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line)
    @discardableResult public func waitFor(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool
}
// ScreenshotCore
public struct Runner {
    public init(config: Config, root: URL, workDir: URL, shell: CommandRunning, log: @escaping @Sendable (String) -> Void)
    public func build(target: Config.Target) throws                       // einmal je Target
    public func capture(_ run: CaptureRun) throws -> URL                  // Pfad zum .xcresult
}
public enum RunnerError: Error, Equatable { case buildFailed(scheme: String, logTail: String); case testFailed(slug: String, logTail: String) }
```
Verhalten der Testbibliothek: `continueAfterFailure = true`. `launch` hängt `extraArguments` an `launchArguments` an, setzt bei `SA2_LANDSCAPE == "1"` vor dem Start `XCUIDevice.shared.orientation = .landscapeLeft` (nur iOS), auf macOS bei `SA2_APPEARANCE == "dark"` zusätzlich `-AppleInterfaceStyle Dark`, und registriert einen `addUIInterruptionMonitor`, der den letzten Button eines Systemdialogs tippt. `shot` meldet bei ungültigem Namen `XCTFail`, wartet `settleDelay`, nimmt auf macOS `app.windows.firstMatch.screenshot()`, sonst `XCUIScreen.main.screenshot()`, und hängt das PNG mit `ShotProtocol.attachmentName(for:)` und `lifetime = .keepAlways` an. `tap(id:)` sucht `app.descendants(matching: .any)[id]`, wartet bis `timeout`, sonst `XCTFail` mit der ID.

Exakte Aufrufe des Runners (jeweils als Argument-Array):
- Build: `xcodebuild build-for-testing (-project P | -workspace W) -scheme S -destination <generic> -derivedDataPath <workDir>/dd-<platform>`; `<generic>` = `generic/platform=iOS Simulator`, `generic/platform=tvOS Simulator`, `generic/platform=watchOS Simulator`, `platform=macOS`.
- Vorbereitung (nicht macOS): `xcrun simctl boot <udid>` nur wenn nicht gebootet; `xcrun simctl bootstatus <udid> -b`; nur iOS: `xcrun simctl status_bar <udid> override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4`; `xcrun simctl ui <udid> appearance <light|dark>`; je Eintrag in `permissions`: `xcrun simctl privacy <udid> grant <service> <bundleID>` (Bundle-ID einmalig über `xcodebuild -showBuildSettings -json`, Schlüssel `PRODUCT_BUNDLE_IDENTIFIER`).
- Test: `xcodebuild test-without-building … -destination platform=<Plattform> Simulator,id=<udid> -derivedDataPath … -only-testing:<tests> -testLanguage <lang> [-testRegion <region>] -parallel-testing-enabled NO -resultBundlePath <workDir>/<slug>.xcresult`, Umgebung `TEST_RUNNER_SA2_DISPLAY=<display.name>`, `TEST_RUNNER_SA2_LANDSCAPE=<0|1>`, `TEST_RUNNER_SA2_APPEARANCE=<light|dark>`. Vorher vorhandenes `.xcresult` löschen.
- Nachbereitung, auch im Fehlerfall: `xcrun simctl status_bar <udid> clear`; `xcrun simctl shutdown <udid>` **nur**, wenn der Runner diesen Simulator selbst gebootet hat.
- Exit-Code ≠ 0 → `RunnerError` mit den letzten 40 Zeilen der Ausgabe.

- [x] **Step 1:** Beispiel-App anlegen: SwiftUI, `TabView` mit Tabs `tab.home`, `tab.items`, `tab.settings` (als `accessibilityIdentifier`), Liste → Detail, ein Sheet, feste Mock-Daten, Texte in `de` und `en` lokalisiert, reagiert auf `-SCREEN detail` (startet direkt im Detail). `project.yml` mit Targets `Demo` (iOS, iPhone+iPad) und `DemoUITests`, lokales Paket `..`. `cd Example && xcodegen generate`, `.xcodeproj` einchecken.
- [x] **Step 2:** `ScreenshotTestCase` implementieren; `Example/DemoUITests/Screenshots.swift` mit `testTabs()` (`01_Home`, `02_Items`, `04_Settings`) und `testDetail()` (`launch(extraArguments: ["-SCREEN","detail"])`, `03_Detail`).
- [x] **Step 3: Von Hand prüfen** (noch ohne Runner): `xcodebuild test -project Example/Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:DemoUITests/Screenshots -parallel-testing-enabled NO -resultBundlePath /tmp/sa2.xcresult`, dann `xcrun xcresulttool export attachments --path /tmp/sa2.xcresult --output-path /tmp/sa2-out`. Erwartet: 4 PNG mit 1206×2622. `manifest.json` als `Tests/ScreenshotCoreTests/Fixtures/manifest.json` ablegen (Geräte-IDs anonymisieren). Weicht das Format von `suggestedHumanReadableName` von der Annahme in Aufgabe 1 ab, `ShotProtocol.parse` und dessen Test anpassen.
- [x] **Step 4: Fehlschlagende Runner-Tests** mit `FakeRunner`:
  - Reihenfolge der Aufrufe für einen iOS-Lauf entspricht exakt der Liste oben.
  - Simulator war schon gebootet → kein `boot`, kein `shutdown`, aber `status_bar clear` (Review Focus 1).
  - Simulator vom Runner gebootet und `xcodebuild` schlägt fehl → `status_bar clear` und `shutdown` werden trotzdem aufgerufen, Fehler ist `.testFailed(slug:…)` (Review Focus 1).
  - Projektpfad `/tmp/My App/My App.xcodeproj`, Scheme `My App` → erscheinen als je ein unverändertes Argument (Review Focus 3).
  - `de-DE` → `-testLanguage de -testRegion DE`; `zh-Hans` → kein `-testRegion`.
  - tvOS-Lauf → kein `status_bar override`; macOS-Lauf → keinerlei `simctl`-Aufruf, Destination `platform=macOS`.
- [x] **Step 5:** rot → `ProcessRunner` und `Runner` implementieren → grün.
- [x] **Step 6: Vorversuch V4** (Statusleiste): Runner gegen die Beispiel-App laufen lassen; zeigen alle vier Rohbilder 9:41? Ergebnis in `Docs/superpowers/specs/2026-11-14-v2-spike-results.md` festhalten. Geht die Überschreibung beim App-Neustart verloren, im Runner zusätzlich unmittelbar vor `test-without-building` erneut setzen.
- [x] **Step 7:** Commit `feat: XCUITest base class, example app and capture runner`.

### Task 7: Export aus dem Testergebnis

**Files:** Create `Sources/ScreenshotCore/Exporter.swift`, `Tests/ScreenshotCoreTests/ExporterTests.swift`

**Interfaces:**
- Consumes: `ShotProtocol.parse`, `CaptureRun.slug`, Fixture `manifest.json`
- Produces:
```swift
public struct RawShot: Equatable, Sendable { public var name: String; public var file: URL }
public enum ExportError: Error, Equatable { case toolFailed(String); case noShots(slug: String); case duplicateShot(slug: String, name: String); case protocolMismatch(found: Int, expected: Int) }
public enum Exporter { public static func export(xcresult: URL, run: CaptureRun, rawRoot: URL, shell: CommandRunning) throws -> [RawShot] }
```
Ablauf: `xcrun xcresulttool export attachments --path <xcresult> --output-path <tmp>`; `manifest.json` ist ein Array von `{ testIdentifier, attachments: [{ exportedFileName, suggestedHumanReadableName }] }`. Zielordner `rawRoot/<size.id>/<language>-<appearance>/` wird vorher geleert; Dateien heißen `<name>.png`. Rückgabe nach Name sortiert.

- [x] **Step 1: Tests:** Fixture ergibt Namen `["01_Home","02_Items","03_Detail","04_Settings"]`; fremde Anhänge werden ignoriert; leeres Manifest → `.noShots(slug: "iphone-6.3_de-DE_light")` (Review Focus 2); zweimal `01_Home` → `.duplicateShot` (Review Focus 2); Anhang `sa2v3__x` → `.protocolMismatch(found: 3, expected: 2)`; alte Datei im Zielordner ist danach weg.
- [x] **Step 2:** rot → implementieren → grün. Commit `feat(core): export shots from xcresult`.

---

## Phase 3 — Zusammensetzen und Prüfen

### Task 8: Geometrie und Rahmen

**Files:** Create `Sources/ScreenshotCore/Layout.swift`, `Sources/ScreenshotCore/Composer.swift`, `Tests/ScreenshotCoreTests/Support/TestImage.swift`, `Tests/ScreenshotCoreTests/LayoutTests.swift`, `Tests/ScreenshotCoreTests/ComposerTests.swift`

**Interfaces — Produces:**
```swift
public struct ComposeRequest { public var screenshot: CGImage; public var canvas: PixelSize; public var display: DisplaySpec?; public var hasDynamicIsland: Bool; public var platform: Platform; public var style: Config.Style; public var title: String?; public var subtitle: String?; public var frameImage: CGImage? }
public enum ComposeError: Error, Equatable { case badColor(String); case frameAspectMismatch(expected: Double, actual: Double); case fontUnreadable(String) }
public enum Layout {
    public static func captionRect(canvas: PixelSize, position: Config.Caption.Position) -> CGRect   // 18 % der Höhe, oben bzw. unten, seitlich 6 % Rand
    public static func deviceRect(canvas: PixelSize, screenshot: PixelSize, caption: CGRect?, ringWidthFactor: Double) -> CGRect
    public static func cornerRadii(display: DisplaySpec, drawnWidth: Double) -> CornerRadii          // Punkte × scale × drawnWidth / pixelSize.width
}
public enum Composer { public static func compose(_ r: ComposeRequest) throws -> CGImage; public static func writePNG(_ image: CGImage, to url: URL) throws }
// Test-Support: TestImage.solid(PixelSize, RGBA) -> CGImage; TestImage.pixel(CGImage, x: Int, y: Int) -> RGBA (Ursprung oben links)
```
Feste Werte: Außenrand 6 % der kürzeren Canvas-Seite. `deviceRect` passt den Screenshot seitenverhältnistreu in die Fläche unter/über dem Titelbereich und zentriert ihn. Linienstärke `outline` 0,6 % der kürzeren Geräteseite; Ringbreite `bezel` 2,2 % der Gerätebreite, äußerer Radius = innerer Radius + Ringbreite; `none` nur beschneiden. Der Screenshot wird immer mit den vier Einzelradien beschnitten. macOS: Screenshot unverändert (mit eigenem Alpha) zeichnen, dazu Schatten (Unschärfe 3 % der Canvas-Höhe, Schwarz 35 %), kein Rahmen. `writePNG` schreibt 8 Bit sRGB ohne Alphakanal. Dynamic Island: Zeigen die Rohbilder aus Aufgabe 6 Step 3 die Insel nicht (erwartet, sie ist Hardware), zeichnet der Composer bei `hasDynamicIsland`, Hochformat, `display.name == "primary"` und Stil `outline` oder `bezel` eine schwarze Kapsel: Breite 31 % der gezeichneten Gerätebreite, Höhe 9,2 % der Breite, Abstand von oben 3,5 % der Breite, horizontal zentriert. Zeigen die Rohbilder sie bereits, entfällt das.

- [x] **Step 1: Layout-Tests:** Screenshot 1206×2622 auf Canvas 1206×2622 ohne Titel → `deviceRect` hat Seitenverhältnis 1206/2622 (±0,001), ist zentriert, hält links ≥ 72 px Abstand; mit Titel oben beginnt `deviceRect` unterhalb `captionRect.maxY`; `cornerRadii` fürs Duo-Außendisplay bei `drawnWidth == 1398` → `(24, 177, 24, 177)`.
- [x] **Step 2: Composer-Tests** mit rotem Screenshot (`TestImage.solid`) auf weißem Hintergrund, `frame: .outline`, schwarz:
  - Ergebnis ist exakt `canvas` groß; Pixel (0,0) weiß; Pixel in der Mitte von `deviceRect` rot.
  - Pixel auf der Mitte der oberen Gerätekante schwarz.
  - Duo außen: 3 px innerhalb der **rechten** oberen Ecke des `deviceRect` weiß (runde Ecke), 30 px innerhalb der **linken** oberen Ecke rot bzw. schwarz, nicht weiß.
  - `frame: .none`: kein schwarzer Pixel im Bild.
  - `hasDynamicIsland: true`, `outline`: Pixel bei halber Gerätebreite und 8 % der Gerätebreite unter der Oberkante schwarz; mit `false` an derselben Stelle rot.
  - `frame: .bezel`: Pixel 1 % der Gerätebreite außerhalb der linken Bildschirmkante schwarz.
  - Verlauf `["#000000","#FFFFFF"]`, Winkel 90: Pixel oben Mitte und unten Mitte unterscheiden sich um > 200 je Kanal.
  - `writePNG` → erneut geladen: `alphaInfo` ist `.none` oder `.noneSkipLast`, Größe unverändert.
  - Farbe `"#12"` → `ComposeError.badColor("#12")`.
- [x] **Step 3:** rot → implementieren → grün. Commit `feat(core): layout and frame composer`.

### Task 9: Titel und eigene Rahmen-PNGs

**Files:** Modify `Sources/ScreenshotCore/Composer.swift`; Create `Sources/ScreenshotCore/FrameImage.swift`, `Tests/ScreenshotCoreTests/CaptionTests.swift`, `Tests/ScreenshotCoreTests/FrameImageTests.swift`

**Interfaces — Produces:**
```swift
public enum CaptionLayout { public static func fit(title: String, subtitle: String?, in rect: CGRect, canvasHeight: Double, fontPath: String?) throws -> (titleSize: Double, subtitleSize: Double, lines: Int) }
public enum FrameImage { public static func screenRect(in frame: CGImage) throws -> CGRect }   // Ursprung oben links, in Rahmen-Pixeln
public enum FrameImageError: Error, Equatable { case noTransparentScreen }
```
Feste Werte: Titel fett, Startgröße 4,2 % der Canvas-Höhe; Untertitel normal, 2,6 %; höchstens 2 Titelzeilen und 1 Untertitelzeile; passt es nicht, in 5-%-Schritten bis 60 % der Startgröße verkleinern, danach mit „…" kürzen. Text zentriert, per CoreText gesetzt. Standardschrift ist die Systemschrift; `fontPath` lädt eine `.ttf`/`.otf`. `FrameImage.screenRect`: Rahmen zuerst in einen bekannten RGBA8-Kontext zeichnen, dann vom Bildmittelpunkt in alle vier Richtungen bis zum ersten Pixel mit Alpha > 200 laufen; ist der Mittelpunkt nicht transparent (Alpha ≥ 10) oder wird eine Kante nicht gefunden → Fehler. Bei `frame: .image` gilt: Rahmen seitenverhältnistreu einpassen, Screenshot in das gefundene Rechteck, Rahmen darüber; weicht das Seitenverhältnis des Rechtecks um mehr als 1 % vom Screenshot ab → `ComposeError.frameAspectMismatch`.

- [x] **Step 1: Titel-Tests:** kurzer Titel → `titleSize == 0.042 * canvasHeight`, `lines == 1`; Titel mit 120 Zeichen → `lines <= 2` und `titleSize >= 0.6 * 0.042 * canvasHeight` (Review Focus 5); Eingaben `"Gießen nicht vergessen 🌱"`, `"植物の水やりを忘れずに"`, `"لا تنسَ الري"` werfen nicht und liefern `lines >= 1` (Review Focus 5); im komponierten Bild mit weißem Titel auf schwarzem Hintergrund enthält `captionRect` mindestens einen weißen Pixel und der Bereich von `deviceRect` keinen Pixel aus dem Titel (Review Focus 5); `fontPath: "/nope.ttf"` → `ComposeError.fontUnreadable`.
- [x] **Step 2: Rahmen-Tests** mit erzeugtem Rahmen (schwarzes 400×800-Bild, transparentes Loch `x 20…379, y 30…769`): `screenRect == CGRect(x: 20, y: 30, width: 360, height: 740)`; vollständig deckendes Bild → `.noTransparentScreen`; Screenshot 100×100 in diesen Rahmen → `.frameAspectMismatch`.
- [x] **Step 3:** rot → implementieren → grün. Commit `feat(core): captions and custom frame images`.

### Task 10: Prüfung und Übersicht

**Files:** Create `Sources/ScreenshotCore/Validator.swift`, `Sources/ScreenshotCore/Report.swift`, `Tests/ScreenshotCoreTests/ValidatorTests.swift`, `Tests/ScreenshotCoreTests/ReportTests.swift`

**Interfaces — Produces:**
```swift
public struct ValidationIssue: Equatable, Sendable { public enum Severity: Sendable { case error, warning }; public var severity: Severity; public var file: String?; public var message: String }
public enum Validator {
    public static func checkSet(config: Config) -> [ValidationIssue]                       // ohne Dateien: Pflichtgrößen, Watch-Regel
    public static func checkOutput(finalDir: URL, config: Config) -> [ValidationIssue]     // Dateien in final/
    public static func finalFileName(size: String, shot: String, appearance: Appearance) -> String   // "<size>_<shot>.png" bzw. "<size>_<shot>_dark.png"
}
public enum Report { public static func writeIndex(finalDir: URL, to url: URL) throws }
```
Regeln: Enthält die Konfiguration eine iPhone-Größe, muss `iphone-6.3` dabei sein (Fehler); bei einer iPad-Größe `ipad-13` (Fehler); mehr als eine Watch-Größe → Fehler; fehlt eine Duo-Größe in einer iOS-Konfiguration → Warnung „ab April 2027 Pflicht für Apps mit iOS-27.1-SDK". Je Datei: Pixelgröße liegt in `size.pixelSizes` (oder `swapped`), bei `mac` gleich `config.macCanvas`; kein Alphakanal. Je Größe und Sprache 1–10 Bilder. Alle Sprachen haben dieselbe Menge an Shot-Namen.

- [x] **Step 1: Tests:** nur `iphone-6.9` konfiguriert → genau ein Fehler mit `iphone-6.3` im Text; iOS ohne Duo → eine Warnung, kein Fehler; `watch-ultra` + `watch-series` → Fehler; Datei mit 1000×1000 unter Namen `iphone-6.3_01_Home.png` → Fehler mit Dateiname; PNG mit Alpha → Fehler; 11 Bilder → Fehler; `de-DE` hat `03_Detail`, `en-US` nicht → Fehler nennt beide. `Report`: erzeugte `index.html` enthält je Bild ein `<img src="…">` mit relativem Pfad und je Sprache eine Überschrift.
- [x] **Step 2:** rot → implementieren → grün. Commit `feat(core): output validation and html index`.

---

## Phase 4 — Werkzeug

### Task 11: Ablaufsteuerung und Befehle `run`, `compose`, `check`, `sizes`

**Files:** Create `Sources/ScreenshotCore/Pipeline.swift`, `Tests/ScreenshotCoreTests/PipelineTests.swift`; Modify `Sources/screenshots/Main.swift`; Create `Scripts/install.sh`

**Interfaces:**
- Consumes: alles aus Phase 1–3
- Produces:
```swift
public struct PipelineResult: Sendable { public var runs: [CaptureRun]; public var finalFiles: [URL]; public var issues: [ValidationIssue]; public var failures: [String]; public var succeeded: Bool }
public struct Pipeline {
    public init(configURL: URL, shell: CommandRunning, log: @escaping @Sendable (String) -> Void)
    public func check() throws -> PipelineResult
    public func capture(filter: RunFilter) throws -> PipelineResult
    public func compose(filter: RunFilter) throws -> PipelineResult
    public func run(filter: RunFilter) throws -> PipelineResult        // capture + compose + validate + index.html
}
```
Verzeichnisse relativ zum Ordner der Konfiguration: `<output>/raw`, `<output>/final/<language>/`, `<output>/.work`, `<output>/index.html`. `capture` baut jedes Target einmal, führt die Läufe nacheinander aus und macht bei einem fehlgeschlagenen Lauf mit dem nächsten weiter; der Fehler landet in `failures`. `compose` plant ebenfalls (für Display-Radien und Dynamic Island), startet aber nichts; es leert `final/<language>/` für die betroffenen Größen, prüft, dass jedes Rohbild eine für die Größe erlaubte Pixelgröße hat, nimmt Titel aus `config.shots[name]` und lädt `style.frameImage` relativ zum Ordner der Konfiguration. Ein Eintrag in `config.shots` ohne Rohbild in irgendeinem Lauf ist in `run` und `compose` ein Fehler; `check` meldet ihn nur, wenn `raw/` bereits Bilder enthält. `succeeded` ist nur `true`, wenn `failures` leer ist und kein `ValidationIssue` mit `.error` vorliegt.

Befehle (ArgumentParser, Root `screenshots`, Option `--config` mit Standard `./screenshots.json`): `run`, `compose` (beide mit `--size`, `--language`, `--scheme`, mehrfach angebbar), `check`, `sizes` (Tabelle: ID, Pflicht, Pixelgrößen, gewählter Simulator oder „nicht installiert"). Exit-Codes: 0 Erfolg, 1 Fehlschlag, 2 Konfigurationsfehler (jede `ConfigIssue` als `path: message`).

- [x] **Step 1: Tests** mit `FakeRunner`, der beim `xcresulttool`-Aufruf ein vorbereitetes Exportverzeichnis liefert: `run` erzeugt `final/de-DE/iphone-6.3_01_Home.png` in 1206×2622; scheitert einer von zwei Läufen, existieren die Bilder des anderen und `succeeded == false`; zweiter `compose` nach Entfernen eines Rohbilds lässt keine alte Datei in `final/` zurück; `check` mit fehlendem Simulator liefert `succeeded == false` und nennt die Größe; Titel für einen Shot ohne Rohbild → Fehler in `compose`, in `check` nur bei vorhandenem `raw/`.
- [x] **Step 2:** rot → implementieren → grün.
- [x] **Step 3:** `Scripts/install.sh`: `swift build -c release`, Verknüpfung `~/.local/bin/screenshots`, Hinweis falls `~/.local/bin` nicht im `PATH`.
- [x] **Step 4: Ende-zu-Ende:** `cd Example && ../.build/release/screenshots run --size iphone-6.3 --size ipad-13`. Erwartet: Exit 0; je Sprache 8 Dateien in `final/`; `index.html` öffnet; Bilder ansehen (Read-Tool) und auf Rahmen, Titel, 9:41 prüfen. Dann `Example/DemoUITests/Screenshots.swift` kurz so ändern, dass ein Test fehlschlägt → Exit 1, die Bilder des anderen Tests existieren; Änderung zurücknehmen.
- [x] **Step 5:** Commit `feat(cli): run, compose, check, sizes`.

### Task 12: Assistent `init`

**Files:** Create `Sources/ScreenshotCore/ProjectInspector.swift`, `Sources/ScreenshotCore/InitWizard.swift`, `Tests/ScreenshotCoreTests/InitWizardTests.swift`; Modify `Sources/screenshots/Main.swift`

**Interfaces — Produces:**
```swift
public struct ProjectInfo: Equatable, Sendable { public var container: String; public var isWorkspace: Bool; public var schemes: [String]; public var uiTestTargets: [String] }
public enum ProjectInspector { public static func inspect(directory: URL, shell: CommandRunning) throws -> ProjectInfo }   // xcodebuild -list -json; UI-Test-Targets = Targets mit Suffix "UITests"
public protocol Prompting { func ask(_ question: String, default: String?) -> String; func choose(_ question: String, options: [String], preselected: Set<Int>) -> Set<Int> }
public struct InitResult: Equatable { public var config: Config; public var testFilePath: String; public var testFileContents: String; public var gitignoreLines: [String] }
public enum InitWizard { public static func run(info: ProjectInfo, catalog: DeviceCatalog, prompt: Prompting) -> InitResult }
```
Fragen in dieser Reihenfolge: Scheme, UI-Test-Target, Größen (vorausgewählt: Pflichtgrößen plus jede Größe, für die ein Simulator installiert ist), Sprachen (Standard `en-US`), Rahmenstil (Standard `outline`), zwei Verlaufsfarben. Test-Gerüst: Klasse `Screenshots: ScreenshotTestCase` mit einer Methode `testScreens()` und einem `shot("01_Start")`. `gitignoreLines == ["<output>/raw/", "<output>/.work/"]`. `init` überschreibt weder eine vorhandene `screenshots.json` noch eine vorhandene Testdatei (Abbruch mit Hinweis) und gibt am Ende den Codeschnipsel für die vier Startargumente aus.

- [x] **Step 1: Tests** mit einem `ScriptedPrompt`: Eingaben ergeben eine `Config`, für die `issues()` leer ist; `tests == "DemoUITests/Screenshots"`; `testFileContents` enthält `import ScreenshotAutomator` und `shot("01_Start")`; `ProjectInspector` liest aus `xcodebuild -list -json`-Fixture zwei Schemes und ein UI-Test-Target.
- [x] **Step 2:** rot → implementieren → grün.
- [x] **Step 3: Von Hand:** in einer Kopie von `Example/` ohne `screenshots.json` `screenshots init` durchspielen, danach `screenshots check` → Exit 0. Commit `feat(cli): init wizard`.

---

## Phase 5 — Weitere Plattformen

Jede Aufgabe beginnt mit ihrem Vorversuch aus Spec Abschnitt 9. Das Ergebnis kommt in `Docs/superpowers/specs/2026-11-14-v2-spike-results.md`. Greift eine „Wenn es nicht geht"-Regel, die das Design als Abstimmung mit Matthias kennzeichnet, **anhalten und fragen**.

### Task 13: iPhone Duo

**Files:** Modify `Sources/ScreenshotAutomator/ScreenshotTestCase.swift`, ggf. `Sources/ScreenshotCore/Runner.swift`, `Example/screenshots.json`

- [x] **Step 1: Vorversuch V1.** Mit dem Simulator „iPhone Duo" (iOS 27.1) klären und notieren: (a) Auf welchem Display zeigt die Beispiel-App nach dem Start? (b) Was liefert `XCUIScreen.screens` (Anzahl, Größen)? (c) Gibt es einen programmatischen Weg umzuschalten — `XCUIDevice`-API, `simctl`-Unterbefehl, Simulator-Menü (`Device ▸ …`) samt Tastenkürzel? (d) Liefert `xcrun simctl io <udid> screenshot --display=primary-1` das Innendisplay mit App-Inhalt?
- [x] **Step 2:** Weg nach der Entscheidungsregel in Spec Abschnitt 7 wählen und umsetzen. Variante „Test sieht beide Bildschirme": `shot()` wählt den Bildschirm, dessen Pixelgröße zu `SA2_DISPLAY` passt. Variante „von außen": `shot()` schreibt eine Markierung in die Testausgabe und der Runner nimmt per `simctl io` auf; das ist ein eigener, kleiner Entwurf — vor der Umsetzung kurz mit Matthias abstimmen.
- [x] **Step 3: Test:** Für den gewählten Weg ein Unit-Test der neuen Logik (z. B. Bildschirmauswahl nach `SA2_DISPLAY`).
- [x] **Step 4: Ende-zu-Ende:** `screenshots run --size iphone-duo-outer --size iphone-duo-inner` in `Example/`. Erwartet: Bilder mit 1398×2034 und 2007×2853; im Außenbild sind die linken Ecken fast eckig, die rechten rund. Bilder ansehen. Commit `feat: iPhone Duo outer and inner display`.

### Task 14: Apple TV

**Files:** Modify `Example/project.yml`; Create `Example/DemoTV/`, `Example/DemoTVUITests/Screenshots.swift`; Modify `Example/screenshots.json`

- [x] **Step 1:** tvOS-Target `DemoTV` (nutzt `Example/Shared`), UI-Tests navigieren mit `XCUIRemote.shared.press(.right)` / `.select` und über `-SCREEN detail`. Zweiter Target-Eintrag in `screenshots.json` (`platform: "tvOS"`, `sizes: ["appletv"]`).
- [x] **Step 2:** `tap(id:)` auf tvOS: `XCTFail` mit Hinweis auf `XCUIRemote` (Tippen gibt es dort nicht). Unit-Test entfällt (reiner XCUITest-Code); Beleg ist Step 3.
- [x] **Step 3: Ende-zu-Ende:** `screenshots run --size appletv` → Bilder 1920×1080, Rahmenlinie ohne Eckenradius. Ansehen. Commit `feat: Apple TV example and capture`.

### Task 15: Mac

> **Zurückgestellt (2026-11-17):** nicht Teil des ersten 2.0-Stands, siehe GitHub-Issue #6 (Mac braucht aktivierte UI-Automatisierung, Watch eine watchOS-Laufzeit). Schritte bleiben unabgehakt.

**Files:** Modify `Example/project.yml`, `Sources/ScreenshotAutomator/ScreenshotTestCase.swift`; Create `Example/DemoMac/`, `Example/DemoMacUITests/Screenshots.swift`

- [ ] **Step 1: Vorversuch V2.** Liefert `app.windows.firstMatch.screenshot()` das Fenster mit runden Ecken und Transparenz? Lässt sich die Fenstergröße festlegen (Startargument der App oder Ziehen per XCUITest)? Welche Berechtigungen fragt macOS ab? Notieren. Geht es nicht, die Ausweichlösung aus Spec Abschnitt 9 (`screencapture`) umsetzen.
- [ ] **Step 2:** macOS-Target und UI-Tests; Target-Eintrag `platform: "macOS"`, `sizes: ["mac"]`. Die Beispiel-App setzt bei `-UITEST` eine feste Fenstergröße von 1280×800 Punkten.
- [ ] **Step 3: Ende-zu-Ende:** `screenshots run --size mac` → Bilder 2880×1800, Fenster mit Schatten mittig, Titel darüber, kein Alphakanal. Zusätzlich `appearances: ["light","dark"]` → das `_dark`-Bild zeigt die dunkle Oberfläche. Ansehen. Commit `feat: Mac window capture`.

### Task 16: Apple Watch

> **Zurückgestellt (2026-11-17):** nicht Teil des ersten 2.0-Stands, siehe GitHub-Issue #6 (Mac braucht aktivierte UI-Automatisierung, Watch eine watchOS-Laufzeit). Schritte bleiben unabgehakt.

**Files:** Modify `Example/project.yml`; Create `Example/DemoWatch/`, `Example/DemoWatchUITests/Screenshots.swift`

- [ ] **Step 1: Voraussetzung:** `xcrun simctl list runtimes | grep watchOS`. Fehlt eine verfügbare watchOS-Laufzeit, **anhalten** und Matthias bitten, sie in Xcode ▸ Settings ▸ Components zu installieren.
- [ ] **Step 2: Vorversuch V3.** Eigenständige watchOS-App mit UI-Test-Target: Läuft `xcodebuild test` im Watch-Simulator stabil, und enthält der Export die `sa2v2__`-Anhänge? Notieren. Wenn nicht stabil: anhalten, Verschiebung auf 2.1 mit Matthias abstimmen.
- [ ] **Step 3:** Target-Eintrag `platform: "watchOS"`, `sizes: ["watch-series"]`, `sizeStyles` für diese Größe mit `caption: null`.
- [ ] **Step 4: Ende-zu-Ende:** `screenshots run --size watch-series` → Bilder 416×496, Linie mit Radius, kein Titel. Ansehen. Dann vollständiger Lauf `screenshots run` über alle Targets und Sprachen, danach `screenshots check` → Exit 0. Commit `feat: Apple Watch capture`.

---

## Phase 6 — Abschluss

### Task 17: Dokumentation

**Files:** Rewrite `README.md`; Create `Docs/Reference.md`; Delete `Docs/QuickStart.md`, `Docs/DeveloperHowto.md`, `Docs/ScreenshotPipeline.md`; Modify `.gitignore`

- [ ] **Step 1:** README (Englisch, wie bisher): was es ist, Installation (`Scripts/install.sh`, Paket im UI-Test-Target), Schnellstart in vier Schritten (`init`, Testdatei, Startargumente in der App, `run`), ein Beispielbild aus `Example/`, Verweis auf die Referenz. Höchstens 150 Zeilen.
- [ ] **Step 2:** `Docs/Reference.md`: jedes Feld von `screenshots.json` mit Standardwert, Größentabelle (aus `StoreSizes` übernommen, mit Prüfdatum), Rahmenstile, Befehle und Exit-Codes, Plattform-Hinweise (Duo, Mac, Watch, TV), Fehlerbilder mit Lösung, Umstieg von 1.x.
- [ ] **Step 3:** Jeden Befehl und jedes Konfigurationsbeispiel der Dokumentation einmal gegen `Example/` ausführen bzw. mit `Config.load` laden. `.gitignore` um `Example/screenshots/raw/` und `Example/screenshots/.work/` ergänzen. Commit `docs: v2 readme and reference`.

### Task 18: Abnahme mit Spndx und Freigabe

**Files (anderes Repo, `/Users/matthias/Documents/GitHub/Spndx`):** Modify `SpndxUITests/SpndxScreenshotTest.swift`, Paketverweis im Projekt; Create `screenshots.json`; Delete `Scripts/capture_screenshots_spndx.sh` und die Rahmen-PNGs

- [ ] **Step 1:** Vor Beginn Matthias fragen, ob die Arbeit im Spndx-Repo jetzt starten darf und auf welchem Zweig.
- [ ] **Step 2:** Paket in Spndx auf den Zweig `v2` zeigen lassen. Tabs erhalten `accessibilityIdentifier` (`tab.transactions`, `tab.categories`, `tab.statistics`, `tab.info`). Test auf `ScreenshotTestCase` umstellen: dieselben fünf Shots `01_Transactions` … `05_Info`, ohne `setUp()`, ohne `tabLabels`.
- [ ] **Step 3:** `screenshots init` in Spndx; Größen `iphone-6.3`, `iphone-6.9`, `iphone-duo-outer`, `iphone-duo-inner`, `ipad-13`; die bisherigen Verlaufsfarben aus dem alten Skript übernehmen; deutsche und englische Titel mit Matthias abstimmen.
- [ ] **Step 4:** `screenshots run` → Exit 0, `screenshots check` → Exit 0. Bilder ansehen. Alte Dateien löschen.
- [ ] **Step 5:** Ergebnis Matthias zeigen. Erst nach seinem OK: PR für `v2` öffnen, Issue #5 im PR-Text als behoben nennen, nach dem Merge Tag `2.0.0`. Die Migration von Plantner, ThreadScanner und gameservice sind eigene Folgeaufgaben in den jeweiligen Repos (Reihenfolge laut Spec Abschnitt 11).
