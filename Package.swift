// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ios-screenshot-automator",
    platforms: [
        .iOS(.v16),
        .tvOS(.v16)
    ],
    products: [
        .library(
            name: "ScreenshotAutomator",
            targets: ["ScreenshotAutomator"]
        )
    ],
    targets: [
        .target(
            name: "ScreenshotAutomator",
            path: "Sources"
        )
    ]
)
