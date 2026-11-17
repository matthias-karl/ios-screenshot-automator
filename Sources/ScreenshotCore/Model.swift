import Foundation

public struct PixelSize: Hashable, Codable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var swapped: PixelSize { PixelSize(width: height, height: width) }
    public var isLandscape: Bool { width > height }
}

public enum Platform: String, Codable, CaseIterable, Sendable {
    case iOS, tvOS, watchOS, macOS
}

public enum Appearance: String, Codable, Sendable {
    case light, dark
}

public enum LocaleCode {
    /// Splits an App Store language code into language and region.
    /// The last component is a region only if it is exactly two uppercase ASCII letters.
    public static func split(_ code: String) -> (language: String, region: String?) {
        guard let dash = code.lastIndex(of: "-") else { return (code, nil) }
        let tail = code[code.index(after: dash)...]
        let isRegion = tail.count == 2 && tail.unicodeScalars.allSatisfy { $0 >= "A" && $0 <= "Z" }
        guard isRegion else { return (code, nil) }
        return (String(code[..<dash]), String(tail))
    }
}
