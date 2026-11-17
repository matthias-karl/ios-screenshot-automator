import XCTest
import ScreenshotAutomator

final class Screenshots: ScreenshotTestCase {

    /// SwiftUI's `TabView` does not pass `accessibilityIdentifier` to its tab buttons (it ends up on the
    /// tab's content), so tabs are picked without identifiers of our own — independent of the language:
    /// on iPhone by position in the tab bar, on iPad (floating tab bar without a `TabBar` element)
    /// by the SF Symbol name the system uses as the button's identifier.
    private func selectTab(_ index: Int) {
        let symbols = ["house.fill", "leaf.fill", "gearshape.fill"]
        let tabBar = app.tabBars.firstMatch
        let button = waitFor(tabBar, timeout: 3)
            ? tabBar.buttons.element(boundBy: index)
            : app.buttons[symbols[index]].firstMatch
        XCTAssertTrue(waitFor(button), "Tab \(index) not found")
        button.tap()
    }

    func testTabs() {
        launch()
        shot("01_Home")
        selectTab(1)
        shot("02_Items")
        selectTab(2)
        shot("04_Settings")
    }

    func testDetail() {
        launch(extraArguments: ["-SCREEN", "detail"])
        shot("03_Detail")
    }
}
