import XCTest
import ScreenshotAutomator

final class Screenshots: ScreenshotTestCase {

    /// SwiftUI's `TabView` does not pass `accessibilityIdentifier` to the tab bar buttons
    /// (the identifier ends up on the tab's content), so tabs are picked by position,
    /// which is independent of the language.
    private func selectTab(_ index: Int) {
        let button = app.tabBars.buttons.element(boundBy: index)
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
