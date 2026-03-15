// MockDataProviderExample.swift
// ios-screenshot-automator / Templates
//
// Template for providing mock data during screenshot test runs.
//
// HOW TO USE
// ----------
// 1. Copy this file into your main app target (not the UITest target).
// 2. Rename the file (e.g. ScreenshotMockData.swift).
// 3. Replace `MyApp` and all placeholder types with your own data models.
// 4. Remove the outer block-comment markers (/* ... */) from the implementation.
// 5. In your app's startup code (e.g. AppDelegate / @main struct), load the
//    mock data when the "-LOAD_MOCK_DATA" launch argument is present:
//
//      if CommandLine.arguments.contains("-LOAD_MOCK_DATA") {
//          let mock = MyAppScreenshotMockData.createMockData()
//          // Inject mock.items, mock.categories, etc. into your data layer
//      }
//
// The test runner (run_screenshots.sh) passes "-LOAD_MOCK_DATA" automatically
// via the app's launchArguments set in ScreenshotTestBase.setUp().
//
// SUPPORTED LAUNCH ARGUMENTS (set by ScreenshotTestBase)
// -------------------------------------------------------
//   -UITEST            The app is running under a UI test – skip production-only code.
//   -LOAD_MOCK_DATA    Inject screenshot mock data instead of live data.
//   -DISABLE_ANIMATIONS  Disable Core Animation transitions for stable screenshots.
//   -SKIP_ONBOARDING   Skip the onboarding/tutorial flow.
// -----------------------------------------------------------------------

import Foundation

// MARK: - MockDataProvider Protocol
// Implement this protocol to provide mock data for screenshot tests.
// Your implementation is referenced by the app via CommandLine.arguments.contains("-LOAD_MOCK_DATA").

protocol ScreenshotMockDataProvider {
    // Declare the mock entity arrays your app needs. Examples:
    // var items: [Item] { get }
    // var categories: [Category] { get }
    // var users: [User] { get }
}

// MARK: - Template Implementation
// Rename this struct and fill in your own data types.
// Remove the /* and */ comment markers when you are ready to use it.

/*
struct MyAppScreenshotMockData: ScreenshotMockDataProvider {

    // MARK: - Properties
    // Replace with the data types your app uses, e.g.:
    // let items: [Item]
    // let categories: [Category]

    // MARK: - Factory

    static func createMockData() -> MyAppScreenshotMockData {
        return MyAppScreenshotMockData(
            // items: createSampleItems(),
            // categories: createSampleCategories()
        )
    }

    // MARK: - Sample data helpers

    // private static func createSampleItems() -> [Item] {
    //     return [
    //         Item(id: "1", title: "First Item",  description: "A vivid description"),
    //         Item(id: "2", title: "Second Item", description: "Another description"),
    //         Item(id: "3", title: "Third Item",  description: "Yet another description"),
    //     ]
    // }

    // private static func createSampleCategories() -> [Category] {
    //     return [
    //         Category(id: "a", name: "Category A"),
    //         Category(id: "b", name: "Category B"),
    //     ]
    // }
}
*/

// MARK: - App Startup Integration Example
//
// In your @main App struct or AppDelegate, add:
//
//   init() {
//       if CommandLine.arguments.contains("-LOAD_MOCK_DATA") {
//           let mock = MyAppScreenshotMockData.createMockData()
//           // e.g. dataStore.items      = mock.items
//           //      dataStore.categories = mock.categories
//       }
//       if CommandLine.arguments.contains("-DISABLE_ANIMATIONS") {
//           UIView.setAnimationsEnabled(false)
//       }
//   }
