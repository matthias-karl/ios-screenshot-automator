# Vorversuche 2.0 — Ergebnisse

Stand: 2026-11-17 · Xcode 27.1, iOS-27.x-Simulatoren.

## V4 — Statusleiste (Task 6)

**Frage:** Bleibt `simctl status_bar override` über Teststarts hinweg erhalten?

**Ergebnis (iOS): ja.** Der echte `Runner` lief gegen `Example/` auf „iPhone 18 Pro Max“ (vom Runner gebootet, danach
heruntergefahren). Beide App-Starts des Laufs (`testDetail` und `testTabs`, je ein eigener `launch()`) zeigen in den
Rohbildern 09:41, volles Netz, WLAN und vollen Akku; `simctl ui … appearance light` wirkt ebenfalls (das manuelle
Vergleichsbild ohne Runner zeigt die Systemzeit und den Dunkelmodus des Simulators). Ein erneutes Setzen unmittelbar vor
`test-without-building` ist deshalb **nicht** nötig. Rohbilder: 1320×2868 (iPhone 6,9").
**Offen:** tvOS hat keine Statusleiste (kein Override); watchOS wird in Task 16 geprüft.

## Weitere Beobachtungen aus Task 6

- **Anhangsnamen:** `xcresulttool export attachments` liefert `suggestedHumanReadableName` als
  `sa2v2__<Name>_<Index>_<UUID>.png` — genau das Format, das `ShotProtocol.parse` erwartet. `manifest.json` ist unter
  `Tests/ScreenshotCoreTests/Fixtures/manifest.json` abgelegt (Geräte-ID anonymisiert).
- **Dynamic Island:** In den Rohbildern der Simulatoren fehlt sie (Hardware); der Composer zeichnet sie (Task 8).
- **Tab-Leiste und `accessibilityIdentifier`:** SwiftUI-`TabView` reicht den Identifier **nicht** an die Tab-Leisten-Buttons
  weiter (weder per `Label` im `tabItem` noch per `Tab(...)`-API noch am `.tabItem`-Ergebnis). Der Identifier landet am
  Inhalt des Tabs (`Other`, erst nach Auswahl vorhanden). Folge: `tap(id: "tab.…")` kann Tabs in SwiftUI-Apps nicht
  erreichen. Das Beispiel wählt Tabs deshalb per Position (`app.tabBars.buttons.element(boundBy:)`, sprachunabhängig).
  Betrifft die Migration der Apps (Task 18 / Spec 11): Tabs nicht über `tap(id:)` ansprechen.
- **Hänger:** Ein `xcodebuild test`, das parallel zu `swift build`/`swift test` im selben Paket lief, blieb nach dem
  letzten Testfall stehen (Ergebnisbündel im Zustand `Staging`). Ohne Parallellauf trat es nicht auf. Der `Runner` hat
  derzeit keine Zeitüberschreitung.

## V1 — iPhone Duo (Task 13)

Simulator „iPhone Duo“ (iOS 27.1), Beispiel-App, Test mit `XCUIScreen.screens`, dazu `simctl io … --display=…`.

| Frage | Ergebnis |
|---|---|
| (a) Auf welchem Display erscheint die App? | Nach dem Booten ist das Gerät **zugeklappt** (Hinge 0°): Außendisplay (`primary`, 1398×2034, 466×678 pt) ist an, das Innendisplay (`primary-1`) ist schwarz. Die App läuft auf dem Außendisplay, `XCUIScreen.main` ist das Außendisplay. **Aufgeklappt** (flach, 180°) läuft die App auf dem **Innendisplay**, dann im **Querformat** (Fenster 951×669 pt, Bild 2853×2007 px); `XCUIScreen.main.screenshot()` liefert dann weiterhin das (inaktive) Außendisplay. |
| (b) `XCUIScreen.screens` | **Zwei** Bildschirme, Reihenfolge wie im Geräteprofil: `[0]` = `primary` (Außen), `[1]` = `primary-1` (Innen). `screens[i].screenshot()` liefert jeweils das ganze Display. |
| (c) Programmatisch umschalten? | **Nicht gefunden.** Weder `simctl` (kein Unterbefehl; `simctl ui` kennt nur appearance, increase_contrast, content_size), noch `XCUIDevice`/`XCUIScreen` (keine API in den Headern), noch eine öffentliche CoreSimulator-/SimulatorKit-Schnittstelle. Die Hinge-Haltung ist nur in Simulator.app bedienbar (und über das Simulator-Werkzeug dieser Claude-Sitzung, das keine Xcode-Komponente ist). Sie bleibt **nicht** über `shutdown`/`boot` erhalten (danach wieder zugeklappt). |
| (d) `simctl io <udid> screenshot --display=primary-1` | Liefert 2007×2853 bzw. 2853×2007 px. **Zugeklappt: schwarz.** Aufgeklappt: Inhalt der App. |

**Folgerung.** Außendisplay (`iphone-duo-outer`) funktioniert vollautomatisch mit dem normalen Weg. Das Innendisplay verlangt, dass das Gerät **aufgeklappt** ist, und dafür gibt es keinen öffentlichen programmatischen Weg. Der „von außen“-Weg (`simctl io`) löst das Problem nicht, weil das Innendisplay zugeklappt schwarz bleibt. Umgesetzt ist die Bildschirmwahl im Test (`SA2_DISPLAY` → `XCUIScreen.screens[n]`, mit Prüfung, dass die App auf diesem Display läuft). Offene Entscheidung für Matthias: siehe Bericht zu Task 13.

## Der Hänger von `xcodebuild` (Task 11/13/14) — Ursache gefunden

Nach dem Ende der Tests blieb `xcodebuild test-without-building` gelegentlich für Minuten (tvOS: immer) hängen; das Ergebnisbündel
stand dabei im Zustand `Staging`. `sample` auf den Prozess zeigt `XCTHRunDestinationAllocator.collectSimulatorDiagnostics →
XCTHProcessInvocation.simCtlDiagnose`: `xcodebuild` startet nach dem Lauf `simctl diagnose` und wartet auf dessen Ende; dieser Prozess
blieb in unseren Läufen hängen. **Abhilfe:** `-collect-test-diagnostics never`. Damit lief der Apple-TV-Lauf in 17 s durch (vorher
> 10 min, abgebrochen). Der Runner übergibt die Option jetzt immer; Zeitlimit und einmalige Wiederholung bleiben als Sicherung.

## tvOS (Task 14)

- `simctl ui … appearance` wird von tvOS-Simulatoren abgelehnt („Runtime does not support userInterfaceStyle“). Der Runner setzt es
  dort nicht und lehnt `dark` für tvOS-Targets mit klarer Meldung ab (`"appearances": ["light"]`).
- Navigation im Beispiel: `XCUIRemote.shared.press(.right)`; im `TabView` wechselt der Inhalt, sobald der Tab den Fokus hat.
  Der Inhalt erscheint dabei wie von tvOS gewohnt abgedunkelt (Fokus liegt auf der Tab-Leiste).

## V2 — Mac (Task 15): blockiert durch fehlende UI-Automatisierung

Das macOS-Beispiel (`DemoMac`, `DemoMacUITests`, ad-hoc signiert, Fenster bei `-UITEST` fest 1280×800 pt) baut. Der UI-Testlauf scheitert aber
vor dem ersten Test: `Failed to initialize for UI testing … Timed out while enabling automation mode.`
`DevToolsSecurity -status` meldet „Developer mode is currently disabled“, `automationmodetool` „Automation Mode is disabled. This device
requires user authentication to enable Automation Mode.“ Beides sind Systemeinstellungen, die eine Admin-Authentifizierung brauchen
und nicht von der Automatisierung gesetzt werden dürfen. Damit ist offen: V2 (Fenster-Screenshot mit runden Ecken/Transparenz, Fenstergröße),
die Tab-Navigation unter macOS, der Mac-Lauf und der Dunkelmodus-Lauf. Der Mac-Eintrag fehlt deshalb noch in `Example/screenshots.json`.

### V1, Nachtrag: GUI-Skript für „aufklappen“ geprüft — nicht machbar

Matthias wählte für das Innendisplay ein GUI-Skript (AppleScript/System Events gegen den Simulator). Auf diesem Mac (Xcode 27.1) scheitert das schon am Zielprogramm:
`Simulator.app` gibt es nicht mehr; die Simulatoren gehören zu `DeviceHub.app` (`com.apple.dt.Devices`, nur ein `DevicesTrampoline` plus Prozess `DeviceHub`).
Dieser Prozess hat für die Bedienungshilfen **kein Fenster und keine Menüleiste** (`count of windows` = 0, `menu bar 1` ungültig, auch nach `open`/`reopen`/`devices://`; per
Computer-Use ebenfalls keine Fenster). Ein Skript hätte nichts zum Anklicken. Mit anderer Xcode-Version oder einer sichtbaren Oberfläche wäre es neu zu bewerten.

**Gewählter Weg: manuell bereitstellen** (Spec 7, Regel 3). Ist das Duo gebootet **und aufgeklappt**, funktioniert alles weitere vollautomatisch:
`screenshots run --size iphone-duo-inner` nutzt das laufende Gerät (der Runner bootet und beendet nur Geräte, die er selbst gestartet hat), Ergebnis: 2853×2007 px quer, 9:41.
Dafür waren drei Korrekturen nötig, die jetzt im Code stecken:
1. `XCUIScreen.screenshot()` des Innendisplays liefert das hochformatige Panel unrotiert (Inhalt 90° gedreht); `shot()` zeichnet das `UIImage` mit seiner Ausrichtung neu, **nur** wenn Bild- und Bitmapformat sich widersprechen.
2. Der Runner dreht nur das Hauptdisplay (`XCUIDevice.orientation`); das aufgeklappte Duo zeigt das Innendisplay von sich aus quer.
3. Die Rohgröße wird mit einem Pixel Toleranz geprüft (Punktgröße 668,67 × 3 wird zu 2006 abgeschnitten).
In der Konfiguration gehört `"landscape": ["iphone-duo-inner"]` ins Target (Ausgabebild quer, 2853×2007; der Validator akzeptiert die gedrehte Größe).
Ist das Gerät zugeklappt, schlägt `shot()` mit „The app is not running on display "primary-1" … Is the device open?“ fehl statt ein schwarzes Bild zu liefern.
