import Foundation

/// Fixed mock data so every run produces the same screenshots.
struct Item: Identifiable, Hashable {
    let id: Int
    let name: String
    let note: String
    let symbol: String
}

enum Mock {
    static let items: [Item] = [
        Item(id: 1, name: "Monstera", note: "Bright, indirect light", symbol: "leaf.fill"),
        Item(id: 2, name: "Ficus", note: "Water every 7 days", symbol: "tree.fill"),
        Item(id: 3, name: "Aloe Vera", note: "Likes the sun", symbol: "sun.max.fill"),
        Item(id: 4, name: "Orchid", note: "Mist the leaves", symbol: "drop.fill"),
        Item(id: 5, name: "Cactus", note: "Water rarely", symbol: "sparkles"),
        Item(id: 6, name: "Fern", note: "Keep the soil moist", symbol: "cloud.rain.fill"),
    ]
}

/// Launch arguments understood by the demo app, on top of the four standard ones
/// (`-UITEST`, `-LOAD_MOCK_DATA`, `-DISABLE_ANIMATIONS`, `-SKIP_ONBOARDING`).
enum LaunchOptions {
    /// `-SCREEN detail` starts directly in the detail screen.
    static var screen: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-SCREEN"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static var isUITest: Bool { CommandLine.arguments.contains("-UITEST") }
}
