# ios-screenshot-automator 2.0 — Design

Stand: 2026-11-14 · Status: Entwurf zur Freigabe · Geprüft gegen Xcode 27.1 / Swift 6.4

Legende: **[E]** = von Matthias entschieden · **[V]** = Vorschlag von Claude, noch nicht bestätigt · **[U]** = dem Umsetzer überlassen

---

## 1. Absicht

Die Library soll aus einer App mit möglichst wenig Handgriffen ein **wiederholbares Set gut aussehender App-Store-Screenshots** für alle aktuellen Apple-Geräte erzeugen.

Version 1.x scheitert daran nicht bei der Aufnahme, sondern beim Drumherum: Jede der vier nutzenden Apps (Plantner, gameservice, ThreadScanner, Spndx) pflegt ein eigenes, auseinanderlaufendes Bash-Skript mit 257–415 Zeilen, kopiert dieselbe `setUp()`-Passage und muss Rahmen-PNGs selbst besorgen. Version 2.0 ersetzt dieses Drumherum durch **eine Konfigurationsdatei und einen Befehl**.

Erfolg heißt: In einer App, die schon ein UI-Test-Target hat, führt `screenshots init` plus eine Testdatei mit `shot("…")`-Aufrufen zu fertigen, von App Store Connect akzeptierten Bildern. Ein zweiter Lauf Wochen später liefert ohne Nacharbeit dasselbe Set.

## 2. Ziele, Nicht-Ziele, Anti-Ziele

### Ziele für 2.0

- **[E]** Zielgruppe sind zuerst die eigenen vier Apps. Harte Brüche zu 1.x sind erlaubt.
- **[E]** Plattformen: iPhone, **iPhone Duo (Außen- und Innendisplay)**, iPad, Apple TV, **Apple Watch**, **Mac**.
- **[E]** Einrichtung über einen Terminal-Befehl mit Assistent (`screenshots init`), dazu eine Beispiel-App im Repo.
- **[E]** Marketingtexte (Überschrift, optional Unterzeile) pro Screenshot und Sprache.
- **[E]** Rahmen wahlweise als echtes Geräte-PNG oder als stilisierte schwarze Linie.
- **[E]** Bauvariante A: Swift-Werkzeug auf dem Mac plus dünne Testbibliothek; Aufnahme weiter über XCUITest.
- **[V]** Hell und Dunkel als Dimension der Aufnahme.
- **[V]** Statusleiste standardmäßig auf 9:41, voller Akku, volles Netz.
- **[V]** Prüfung jedes fertigen Bildes gegen Apples Vorgaben (Pixelgröße, kein Alphakanal, höchstens 10 pro Größe, Pflichtgrößen vorhanden).

### Nicht-Ziele für 2.0

- Apple Vision Pro (die Architektur darf es nicht verbauen).
- Upload zu App Store Connect. **[V]** Die Ausgabestruktur wird so gewählt, dass `fastlane deliver` sie einlesen kann.
- Eine Mac-App mit Live-Vorschau, Homebrew-Formel, App-Vorschau-Videos, parallele Aufnahme auf mehreren Simulatoren.
- Abwärtskompatibilität der 1.x-API. 1.x bleibt über die Tags `1.0.0`–`1.2.0` nutzbar.

### Anti-Ziele (wäre ein Fehlschlag, auch wenn es technisch läuft)

- Die App muss wieder ein Skript kopieren und anpassen.
- In der App stehen Gerätenamen, Pixelgrößen oder Rahmen-Margins.
- Ein Lauf meldet Erfolg, obwohl Bilder fehlen oder die falsche Größe haben.
- Fehlt ein Simulator, wird still ein Gerät einer anderen Größenklasse genommen.
- Im Repo oder in den Ausgaben liegt Apple-eigenes Bildmaterial (Bezels, Sensor-Grafiken). **[V]**

## 3. Randbedingungen (geprüft am 2026-11-14)

- **App-Store-Größen** laut [Apples Spezifikationsseite](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications):
  - Pflicht für iPhone-Apps ist „iPhone mit Dynamic Island (mittel)": 1206×2622 oder 1179×2556. (Die README von 1.x nennt noch 6,9".)
  - Pflicht für iPad-Apps: 13" mit 2064×2752 oder 2048×2732.
  - iPhone Duo: außen 1398×2034, innen 2007×2853; Pflicht ab April 2027 für Apps mit iOS-27.1-SDK.
  - Apple TV: 1920×1080 oder 3840×2160. Mac: 1280×800, 1440×900, 2560×1600 oder 2880×1800. Watch: eine Größe je Modellreihe (z. B. 416×496, 422×514), über alle Sprachen gleich.
  - Allgemein: PNG oder JPEG, kein Alphakanal, 1–10 Bilder je Größe.
- **Gerätedaten liegen lokal vor.** `xcrun simctl list -j devicetypes` liefert je Gerätetyp den `bundlePath`; darin enthält `capabilities.plist` für jedes eingebaute Display Pixelgröße, Skalierung und vier einzelne Eckenradien, `profile.plist` die Bildschirmmaske. Geprüft für iPhone 18 Pro/Pro Max, 17e, Duo, iPad Pro 13" (M5), iPad mini, Apple TV, Watch Series 12, Watch Ultra 4.
- **iPhone Duo:** Der Simulator führt zwei Displays (`primary` 1398×2034 mit Radien 8/59/8/59, `primary-1` 2007×2853 mit Radius 55). `simctl io <udid> screenshot --display=primary|primary-1` nimmt beide einzeln auf (ausprobiert). Einen Befehl zum Auf- und Zuklappen habe ich weder in `simctl` noch in den XCUIAutomation-Headern gefunden.
- **Testanhänge exportierbar:** `xcrun xcresulttool export attachments --path … --output-path …` schreibt alle Anhänge plus `manifest.json`.
- **Auf diesem Mac fehlt** eine watchOS-27-Laufzeit; sie muss vor der Watch-Phase installiert werden.
- **Verbraucher:** Plantner und Spndx (iPhone/iPad), ThreadScanner (iPhone/iPad/Mac), gameservice (iPhone/iPad + tvOS). Keine App hat ein Watch-Target; Watch wird nur durch die Beispiel-App belegt.
- Alle vier Apps reagieren bereits auf `-UITEST`, `-LOAD_MOCK_DATA`, `-DISABLE_ANIMATIONS`, `-SKIP_ONBOARDING`.

## 4. Bauvarianten

| | Variante | Abwägung |
|---|---|---|
| **A** | Swift-Werkzeug + dünner Test. UI-Test navigiert und ruft `shot()`. Werkzeug wählt Simulatoren, exportiert Bilder aus dem Testergebnis, setzt zusammen. | Volle Originaltreue, jeder Zustand erreichbar, ein Weg für alle Plattformen. Langsamste Aufnahme; Watch und Mac brauchen ein eigenes UI-Test-Target. |
| B | Ohne UI-Tests: Werkzeug startet die App per `simctl` in einem Zustand und fotografiert von außen. | Schnell, kein Test-Target. Aber Routing-Code für jeden Zustand in jeder App, Timing geraten, Mac braucht trotzdem einen zweiten Weg. |
| C | Bash aufräumen. | Behält das Konzept, das zu vier Forks geführt hat; kein Weg zu Watch, Mac, Duo. Verworfen. |

**[E] Gewählt: A.** Grund: B verschiebt die Komplexität aus dem Test in jede App; gewünscht ist „so einfach wie möglich in der App". Die gute Idee aus B bleibt als Option erhalten: Ein Test darf die App mit zusätzlichen Argumenten direkt in einen Zustand starten.

## 5. Was der Nutzer sieht

### 5.1 Einrichtung, einmal pro App

```
$ screenshots init
Projekt:        Plantner.xcodeproj
Scheme (iOS):   Plantner            UI-Tests: PlantnerUITests
Größen:         [x] iPhone 6,3" (Pflicht)  [x] iPhone 6,9"  [x] iPhone Duo außen
                [x] iPhone Duo innen       [x] iPad 13" (Pflicht)
Sprachen:       de, en
Rahmen:         Linie
Hintergrund:    Verlauf #1f881b → #79b474

✓ screenshots.json geschrieben
✓ PlantnerUITests/Screenshots.swift angelegt (bitte dem UI-Test-Target hinzufügen)
→ Weiter mit: screenshots run
```

### 5.2 Testdatei in der App

```swift
import XCTest
import ScreenshotAutomator

final class Screenshots: ScreenshotTestCase {

    func testHome() {
        launch()
        shot("01_Home")
        tap(id: "tab.plants")
        shot("02_Plants")
    }

    func testDetail() {
        launch(extraArguments: ["-SCREEN", "plantDetail"])   // direkt in einen Zustand
        shot("03_Detail")
    }
}
```

Kein `setUp()`-Boilerplate, kein Pfad, kein Gerätename.

### 5.3 Konfiguration `screenshots.json` im App-Repo

```json
{
  "version": 2,
  "project": "Plantner.xcodeproj",
  "targets": [
    {
      "platform": "iOS",
      "scheme": "Plantner",
      "tests": "PlantnerUITests/Screenshots",
      "sizes": ["iphone-6.3", "iphone-6.9", "iphone-duo-outer", "iphone-duo-inner", "ipad-13"]
    }
  ],
  "languages": ["de-DE", "en-US"],
  "appearances": ["light"],
  "style": {
    "background": { "gradient": ["#1f881b", "#79b474"], "angle": 135 },
    "frame": "outline",
    "caption": { "color": "#FFFFFF", "position": "top" }
  },
  "shots": {
    "01_Home":   { "title": { "de-DE": "Alle Pflanzen im Blick", "en-US": "All your plants at a glance" } },
    "02_Plants": { "title": { "de-DE": "Gießen nicht vergessen",  "en-US": "Never miss a watering" } }
  },
  "output": "screenshots"
}
```

### 5.4 Befehle

| Befehl | Zweck |
|---|---|
| `screenshots init` | Assistent: erkennt Projekt, Schemes, UI-Test-Targets; schreibt Konfiguration und Test-Gerüst. |
| `screenshots run` | Aufnahme und Zusammensetzen, danach Prüfung. Filter: `--size`, `--language`, `--target`. |
| `screenshots compose` | Nur neu zusammensetzen aus vorhandenen Rohbildern (Nachfolger von `--mockups-only`). |
| `screenshots check` | Prüft Konfiguration, installierte Simulatoren, Abdeckung der Pflichtgrößen. Ändert nichts. |
| `screenshots sizes` | Listet alle bekannten Größen und den jeweils gewählten Simulator. |

Jeder Befehl endet mit einem Exit-Code ≠ 0, sobald ein angefordertes Bild fehlt oder die Prüfung fehlschlägt.

### 5.5 Ausgabe

```
screenshots/
├── raw/<größe>/<sprache>-<appearance>/<name>.png      Rohbilder, unverändert
├── final/<sprache>/<größe>_<name>[_dark].png          fertige Bilder, exakte App-Store-Größe
└── index.html                                         Übersicht aller fertigen Bilder
```

**[V]** `final/<sprache>/` verwendet App-Store-Sprachcodes, damit `fastlane deliver` den Ordner direkt nehmen kann.

Regeln **[V]**:

- Sprachen stehen als App-Store-Codes in der Konfiguration (`de-DE`); das Werkzeug leitet daraus Testsprache (`de`) und Region (`DE`) ab.
- Ein Lauf ersetzt alle Ausgaben in seinem Filterbereich; alte Bilder derselben Größe und Sprache bleiben nie liegen.
- Ein Shot ohne Titel in `shots` wird ohne Text gesetzt. Ein Titel für einen Shot, den kein Test liefert, ist ein Fehler in `run` und `compose`; `check` meldet ihn, sobald Rohbilder vorliegen.
- `init` bietet an, `screenshots/raw/` in `.gitignore` einzutragen; `final/` bleibt versionierbar.
- Statt `project` ist auch `workspace` erlaubt (genau eines von beiden).

### 5.6 Rahmenstile

| Stil | Aussehen | Quelle der Form |
|---|---|---|
| `outline` | dünne schwarze Linie entlang des Bildschirmrands, Screenshot mit passenden Ecken beschnitten | Eckenradien aus dem Simulator-Profil, pro Ecke (wichtig fürs Duo-Außendisplay) |
| `bezel` | gefüllter schwarzer Ring wie ein stilisiertes Gehäuse | wie `outline`, plus Ringbreite |
| `image` | eigenes Rahmen-PNG mit transparentem Bildschirmbereich (wie 1.x) | Pfad je Größe in der Konfiguration |
| `none` | Screenshot mit runden Ecken direkt auf dem Hintergrund | Eckenradien aus dem Profil |

Skizze `outline` mit Text oben:

```
┌───────────────────────────┐
│   Alle Pflanzen im Blick  │  ← Titel, pro Sprache
│                           │
│     ╭───────────────╮     │
│     │   ▬▬▬▬        │     │  ← schwarze Linie, Ecken wie das Gerät
│     │               │     │
│     │  Screenshot   │     │
│     │               │     │
│     ╰───────────────╯     │
└───────────────────────────┘  ← exakt die App-Store-Pixelgröße
```

Voreinstellungen je Plattform **[V]**: iPhone/iPad `outline` mit Titel; Apple TV `outline` ohne Eckenradius; Mac Fenster-Screenshot mit Schatten auf Hintergrund; Watch `outline` ohne Titel (die Bildfläche ist zu klein für Text). Jede Voreinstellung ist pro Größe überschreibbar.

## 6. Aufbau

Ein Swift-Paket, drei Bausteine:

```
Package.swift
Sources/
  ScreenshotAutomator/     Testbibliothek (iOS, tvOS, watchOS, macOS) — hängt an XCTest
  ScreenshotCore/          macOS-Bibliothek: gesamte Logik, ohne Terminal-Ein-/Ausgabe
  screenshots/             ausführbares Werkzeug, dünne Hülle um ScreenshotCore
Tests/ScreenshotCoreTests/ Unit-Tests mit Fixtures
Example/                   Beispiel-App (iOS/iPadOS, tvOS, watchOS, macOS) mit screenshots.json
```

**[V]** Der Produktname der Testbibliothek bleibt `ScreenshotAutomator`, damit die Paketverknüpfung in den vier Apps bestehen bleibt und nur die Version wechselt.

### 6.1 Testbibliothek `ScreenshotAutomator`

Aufgabe: App starten, Screenshot als Testanhang mit maschinenlesbarem Namen ablegen. Sonst nichts.

- `ScreenshotTestCase: XCTestCase` mit `app`, `launch(extraArguments:)`, `shot(_:)`, `tap(id:)`, `waitFor(_:timeout:)`.
- Standard-Startargumente bleiben die vier bekannten; überschreibbar über eine Klassen-Eigenschaft, `extraArguments` wird **angehängt** (in 1.x haben Apps die Liste versehentlich ersetzt).
- `shot()` schreibt **nichts** auf die Platte. Es hängt das Bild als `XCTAttachment` mit dem Namen `sa2v2__<name>` an (Präfix enthält die Protokollversion; Shot-Namen bestehen nur aus Buchstaben, Ziffern, `_` und `-`). Auf dem Mac nimmt es das vorderste Fenster auf, sonst den Bildschirm.
- Jede Testmethode ist ein eigener Lauf: Scheitert eine, entstehen die Bilder der anderen trotzdem.
- **Gestrichen:** `tabLabels`, die sechsstufige iPad-Kaskade, `tapPlusButton`, `dismissSheet`, `exitEditModeIfNeeded`, `ensureMainViewVisible`, der eingebaute Composer, `screenshotsURL`, alle Gerätelisten. Ersatz ist ein stabiler Vertrag: Die App vergibt `accessibilityIdentifier`, der Test nutzt `tap(id:)` oder normale XCUITest-Abfragen.
- Systemdialoge: Das Werkzeug erteilt Berechtigungen vorab per `simctl privacy` (Liste in der Konfiguration); zusätzlich registriert die Basisklasse einen sprachunabhängigen Unterbrechungs-Handler.

### 6.2 `ScreenshotCore`

| Teil | Aufgabe |
|---|---|
| `Config` | `screenshots.json` lesen, prüfen, mit verständlichen Fehlermeldungen (Feld und Grund). |
| `StoreSizes` | Die **einzige** handgepflegte Tabelle: Größen-ID → akzeptierte Pixelgrößen, Pflicht ja/nein, Plattform. Eine Datei, mit Datum und Quell-URL. |
| `DeviceCatalog` | Liest installierte Gerätetypen samt Displays (Pixel, Skalierung, vier Eckenradien, Dynamic Island) aus `simctl` und den Profil-Plists. |
| `Planner` | Bildet Konfiguration auf Läufe ab: Größe × Sprache × Appearance → konkreter Simulator. Wählt den neuesten installierten Gerätetyp, dessen Display eine akzeptierte Pixelgröße der Größe hat. Kein passender installiert → Fehler mit Hinweis, **kein** Ausweichen auf eine andere Größe. |
| `Runner` | Je Target einmal `build-for-testing`, dann je Lauf `test-without-building` mit `-parallel-testing-enabled NO` (behebt Issue #5). Simulator per UDID starten, auf Bootende warten, Statusleiste und Appearance setzen, Berechtigungen erteilen, danach aufräumen. Ergebnis über den echten Exit-Code und die exportierten Anhänge beurteilen. |
| `Exporter` | `xcresulttool export attachments`, Anhänge mit Präfix `sa2v2__` nach `raw/` einsortieren. |
| `Composer` | CoreGraphics: Hintergrund, Rahmen, Titel, Ausgabe in exakter Zielgröße als PNG ohne Alpha. Ersetzt beide Composer aus 1.x. Screenshot wird nie verzerrt (Seitenverhältnis-Abweichung = Fehler). |
| `Validator` | Pixelgröße, Alphakanal, Anzahl je Größe, Pflichtgrößen, gleiche Bildmenge in allen Sprachen. |
| `Report` | `index.html` mit allen fertigen Bildern nach Sprache und Größe. |

### 6.3 Werkzeug `screenshots`

Dünne Hülle: Argumente lesen, `ScreenshotCore` aufrufen, Fortschritt und Fehler ausgeben. **[V]** Einzige Abhängigkeit: `swift-argument-parser`. **[V]** Installation über `Scripts/install.sh` (Release-Build, Verknüpfung nach `~/.local/bin`). Das Werkzeug vergleicht seine Protokollversion mit der der Testbibliothek und meldet eine Abweichung klar.

### 6.4 Beispiel-App

Eine kleine SwiftUI-App mit Tabs, Liste, Detail und Sheet, Mock-Daten und Zielen für iOS/iPadOS, tvOS, watchOS und macOS. Sie ist zugleich Dokumentation, Ende-zu-Ende-Test und der einzige Beleg für Watch. **[V]** Projekt aus einer `project.yml` (XcodeGen ist installiert) erzeugt, das erzeugte `.xcodeproj` wird eingecheckt, damit Nutzer kein Zusatzwerkzeug brauchen.

## 7. Plattform-Besonderheiten

- **iPhone Duo.** Zwei Größen (`iphone-duo-outer`, `iphone-duo-inner`), ein Simulator. Offen ist, wie der Lauf bestimmt, auf welchem Display die App erscheint. Das klärt ein Vorversuch (Abschnitt 9, V1). Entscheidungsregel für den Umsetzer: Gibt es einen programmatischen Weg umzuschalten, laufen die Tests je Display einmal. Gibt es keinen, nimmt das Werkzeug das Innendisplay von außen per `simctl io … --display=primary-1` auf, ausgelöst durch ein Signal aus `shot()`. Führt beides nicht zu verlässlichen Bildern, wird Duo-innen in 2.0 als „manuell bereitstellen" dokumentiert und der Rest ausgeliefert; das ist dann mit Matthias abzustimmen.
- **Mac.** Kein Simulator. Der Test läuft mit `platform=macOS`, `shot()` nimmt das App-Fenster auf, der Composer setzt es auf eine 16:10-Fläche (Standard 2880×1800). Statusleisten-Schritt entfällt, Dunkelmodus über Startargument.
- **Apple Watch.** Eigenes watchOS-UI-Test-Target, eigener Target-Eintrag in der Konfiguration. Genau eine Größe für alle Sprachen (Apples Vorgabe); der Validator erzwingt das.
- **Apple TV.** Wie iPhone, nur Querformat und ohne Eckenradius. Navigation bleibt Sache des Tests (Fernbedienung über `XCUIRemote`) oder des direkten Zustandsstarts.
- **Ausrichtung.** **[V]** Pro Größe `orientation: portrait | landscape`; Standard Hochformat, bei TV und Mac fest quer.

## 8. Was aus 1.x verschwindet

`Scripts/run_screenshots.sh`, `Scripts/compose_mockup.swift`, `Templates/`, `Sources/ScreenshotComposer.swift`, `Sources/ScreenshotTestBase.swift` (ersetzt), die beiden Beispiel-Tests, sowie die drei sich überlappenden Dokumente. Neu: eine README (Schnellstart) und eine Referenz (Konfiguration, Größen, Rahmenstile, Fehlerbilder).

## 9. Risiken und Vorversuche

Diese vier Versuche stehen am Anfang der Umsetzung, weil ihr Ergebnis den Bau der jeweiligen Plattform bestimmt:

| | Frage | Wenn es nicht geht |
|---|---|---|
| V1 | Duo: Auf welchem Display läuft die App, wie schaltet man um, sieht XCUITest beide Bildschirme? | siehe Entscheidungsregel in Abschnitt 7 |
| V2 | Mac: Liefert XCUITest einen sauberen Fenster-Screenshot (runde Ecken, Transparenz), und lässt sich die Fenstergröße festlegen? | Fenster von außen per `screencapture` aufnehmen |
| V3 | Watch: Laufen UI-Tests im Watch-Simulator stabil, kommen die Anhänge im Export an? | Watch auf 2.1 verschieben, mit Matthias abstimmen |
| V4 | Bleibt die Statusleisten-Überschreibung über Teststarts hinweg erhalten (iOS 27, tvOS 27)? | vor jedem Lauf neu setzen |

Weitere Risiken: Aufnahme bleibt langsam (bewusst hingenommen; `build-for-testing` nur einmal mildert es). Apples Größentabelle ändert sich etwa jährlich; deshalb genau eine Datei mit Datum.

## 10. Tests und Abnahme

- Unit-Tests für `ScreenshotCore` über `swift test`: Konfigurationsfehler, Größenzuordnung gegen Fixture-Gerätelisten (einschließlich Duo), Geometrie, Composer über gezielte Pixelproben an einfarbigen Testbildern (keine eingecheckten Referenzbilder, weil Schriftdarstellung je macOS-Version abweicht), Validator.
- Ende-zu-Ende: `screenshots run` in `Example/` erzeugt für iPhone 6,3", Duo außen, iPad 13", Apple TV, Mac und Watch je mindestens zwei Sprachen; `screenshots check` ist danach grün.
- **[V]** CI nur für `swift build` und `swift test` (kein Simulatorlauf in CI).
- Abnahme für 2.0: Die Beispiel-App läuft durch, und **Spndx** ist als erste echte App migriert (sie nutzt 1.x fast unverändert aus dem Schnellstart und ist damit der ehrlichste Test).

## 11. Migration der vier Apps

Reihenfolge **[V]**: Spndx → Plantner → ThreadScanner (bringt Mac) → gameservice (bringt tvOS und Zustandsstarts). Jede Migration ist eine eigene, kleine Aufgabe im jeweiligen App-Repo: Paket auf 2.0 heben, Test auf `ScreenshotTestCase` umstellen, `accessibilityIdentifier` für Tabs vergeben, `screenshots.json` anlegen, altes Skript und Rahmen-PNGs löschen. Spndx gehört zur Abnahme von 2.0; die anderen drei folgen danach.

## 12. Dem Umsetzer überlassen **[U]**

- Genaue Typ- und Methodennamen jenseits der in 5.2 gezeigten Oberfläche.
- Aufteilung von `ScreenshotCore` in Dateien.
- Darstellung der Dynamic Island im Stil `outline`/`bezel` (eigene Kapselform, kein Apple-Material).
- Schriftwahl-Mechanik für Titel (Standard Systemschrift fett, eigene Schrift per Dateipfad), automatische Verkleinerung bei langen Texten.
- Aufbau des Assistenten in `init` (reine Texteingabe genügt).
- Format der Fortschrittsausgabe und der `index.html`.
- Mindestversionen der Plattformen in `Package.swift`; **[V]** Werkzeug setzt Xcode 27 voraus.
