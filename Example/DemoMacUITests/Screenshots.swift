import XCTest
import ScreenshotAutomator

/// WORK IN PROGRESS (Task 15): not yet run, because UI automation is not enabled on the development Mac
/// (see Docs/superpowers/specs/2026-11-14-v2-spike-results.md). The tab navigation still has to be
/// checked against the real macOS accessibility hierarchy.
final class Screenshots: ScreenshotTestCase {

    func testTabs() {
        launch()
        shot("01_Home")
        // TODO(macOS): select the "Plants" and "Settings" tabs (02_Items, 04_Settings).
    }

    func testDetail() {
        launch(extraArguments: ["-SCREEN", "detail"])
        shot("03_Detail")
    }
}
