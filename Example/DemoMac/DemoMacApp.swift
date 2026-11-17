import SwiftUI

@main
struct DemoMacApp: App {
    var body: some Scene {
        WindowGroup {
            if LaunchOptions.isUITest {
                // A fixed window size makes the screenshots identical on every Mac.
                RootView().frame(width: 1280, height: 800)
            } else {
                RootView()
            }
        }
        .windowResizability(LaunchOptions.isUITest ? .contentSize : .automatic)
    }
}
