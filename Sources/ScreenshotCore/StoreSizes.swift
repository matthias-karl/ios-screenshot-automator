import Foundation

/// One App Store screenshot size (a "slot" in App Store Connect).
public struct StoreSize: Equatable, Sendable {
    public var id: String
    public var platform: Platform
    public var label: String
    /// Accepted pixel sizes in portrait (width < height), preferred first.
    /// tvOS and macOS sizes are always used in landscape (`swapped`).
    public var pixelSizes: [PixelSize]
    public var family: Family
    /// Whether this size must be delivered when any size of its family is.
    public var requiredWithinFamily: Bool

    public enum Family: String, Sendable {
        case iPhone, iPad, appleTV, mac, watch
    }

    public init(
        id: String, platform: Platform, label: String, pixelSizes: [PixelSize],
        family: Family, requiredWithinFamily: Bool
    ) {
        self.id = id
        self.platform = platform
        self.label = label
        self.pixelSizes = pixelSizes
        self.family = family
        self.requiredWithinFamily = requiredWithinFamily
    }
}

/// The only hand-maintained table of App Store pixel sizes.
/// Apple changes it about once a year: update `lastVerified` together with the rows.
public enum StoreSizes {
    public static let lastVerified = "2026-11-14"
    public static let source = "https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications"

    public static func size(id: String) -> StoreSize? {
        all.first { $0.id == id }
    }

    private static func px(_ w: Int, _ h: Int) -> PixelSize { PixelSize(width: w, height: h) }

    public static let all: [StoreSize] = [
        StoreSize(id: "iphone-6.3", platform: .iOS, label: "iPhone 6.3\"",
                  pixelSizes: [px(1206, 2622), px(1179, 2556)], family: .iPhone, requiredWithinFamily: true),
        StoreSize(id: "iphone-6.9", platform: .iOS, label: "iPhone 6.9\"",
                  pixelSizes: [px(1320, 2868), px(1290, 2796), px(1260, 2736)], family: .iPhone, requiredWithinFamily: false),
        StoreSize(id: "iphone-duo-outer", platform: .iOS, label: "iPhone Duo (outer display)",
                  pixelSizes: [px(1398, 2034)], family: .iPhone, requiredWithinFamily: false),
        StoreSize(id: "iphone-duo-inner", platform: .iOS, label: "iPhone Duo (inner display)",
                  pixelSizes: [px(2007, 2853)], family: .iPhone, requiredWithinFamily: false),
        StoreSize(id: "ipad-13", platform: .iOS, label: "iPad 13\"",
                  pixelSizes: [px(2064, 2752), px(2048, 2732)], family: .iPad, requiredWithinFamily: true),
        StoreSize(id: "ipad-11", platform: .iOS, label: "iPad 11\"",
                  pixelSizes: [px(1668, 2420), px(1668, 2388), px(1640, 2360), px(1488, 2266), px(1512, 2316)],
                  family: .iPad, requiredWithinFamily: false),
        StoreSize(id: "appletv", platform: .tvOS, label: "Apple TV",
                  pixelSizes: [px(1080, 1920), px(2160, 3840)], family: .appleTV, requiredWithinFamily: true),
        StoreSize(id: "mac", platform: .macOS, label: "Mac",
                  pixelSizes: [px(1800, 2880), px(1600, 2560), px(900, 1440), px(800, 1280)],
                  family: .mac, requiredWithinFamily: true),
        StoreSize(id: "watch-ultra", platform: .watchOS, label: "Apple Watch Ultra",
                  pixelSizes: [px(422, 514), px(410, 502)], family: .watch, requiredWithinFamily: false),
        StoreSize(id: "watch-series", platform: .watchOS, label: "Apple Watch Series",
                  pixelSizes: [px(416, 496), px(396, 484)], family: .watch, requiredWithinFamily: false),
        StoreSize(id: "watch-se", platform: .watchOS, label: "Apple Watch SE",
                  pixelSizes: [px(368, 448)], family: .watch, requiredWithinFamily: false),
    ]
}
