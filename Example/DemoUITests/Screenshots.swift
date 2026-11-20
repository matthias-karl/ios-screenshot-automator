import XCTest
import ScreenshotAutomator

final class Screenshots: ScreenshotTestCase {

    /// SwiftUI's `TabView` ignores an `accessibilityIdentifier` on its tabs (it ends up on the tab's content),
    /// but the system exposes each tab button's SF Symbol name as its identifier on iPhone, iPad and iPhone Duo.
    /// The demo therefore gives every tab a symbol of its own (not used elsewhere) and taps it by name,
    /// which is independent of the language.
    private enum Tab { static let home = "house.fill", items = "list.bullet", settings = "gearshape.fill" }

    func testTabs() {
        launch()
        shot("01_Home")
        tap(id: Tab.items)
        shot("02_Items")
        tap(id: Tab.settings)
        shot("04_Settings")
    }

    func testDetail() {
        launch(extraArguments: ["-SCREEN", "detail"])
        shot("03_Detail")
    }
}
