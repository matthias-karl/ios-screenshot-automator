// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ios-screenshot-automator",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        // Linked into the app's UI-test target.
        .library(name: "ScreenshotAutomator", targets: ["ScreenshotAutomator"]),
        // The command-line tool (`screenshots`).
        .executable(name: "screenshots", targets: ["screenshots"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        // Tiny contract shared by the test library and the tool.
        .target(name: "ScreenshotProtocol"),
        .target(name: "ScreenshotAutomator", dependencies: ["ScreenshotProtocol"]),
        .target(name: "ScreenshotCore", dependencies: ["ScreenshotProtocol"]),
        .executableTarget(
            name: "screenshots",
            dependencies: [
                "ScreenshotCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "ScreenshotProtocolTests", dependencies: ["ScreenshotProtocol"]),
        .testTarget(
            name: "ScreenshotCoreTests",
            dependencies: ["ScreenshotCore", "ScreenshotProtocol"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
