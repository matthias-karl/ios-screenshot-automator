import XCTest
import ScreenshotAutomator

/// Apple TV has no touch: the test moves the focus with the remote.
/// In a `TabView` the tab content changes as soon as its tab gets the focus.
final class Screenshots: ScreenshotTestCase {

    private var remote: XCUIRemote { .shared }

    func testTabs() {
        launch()
        shot("01_Home")
        remote.press(.right)        // focus: Plants tab
        shot("02_Items")
        remote.press(.right)        // focus: Settings tab
        shot("04_Settings")
    }

    func testDetail() {
        launch(extraArguments: ["-SCREEN", "detail"])   // start directly in an app state
        shot("03_Detail")
    }
}
