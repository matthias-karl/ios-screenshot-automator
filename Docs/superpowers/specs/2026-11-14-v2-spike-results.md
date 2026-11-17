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
