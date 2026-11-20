import CoreGraphics
import Foundation
@testable import ScreenshotCore

/// Synthetic images for pixel probes. Origin is the top-left corner.
enum TestImage {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func solid(_ size: PixelSize, _ color: RGBA) -> CGImage {
        let context = CGContext(
            data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(
            colorSpace: colorSpace,
            components: [CGFloat(color.red) / 255, CGFloat(color.green) / 255, CGFloat(color.blue) / 255, CGFloat(color.alpha) / 255])!)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()!
    }

    /// Like `solid`, but without an alpha channel.
    static func opaque(_ size: PixelSize, _ color: RGBA) -> CGImage {
        let context = CGContext(
            data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(
            colorSpace: colorSpace,
            components: [CGFloat(color.red) / 255, CGFloat(color.green) / 255, CGFloat(color.blue) / 255, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()!
    }

    /// A black, fully opaque `size` image with a fully transparent rectangle (`hole`, top-left origin).
    static func frameWithHole(_ size: PixelSize, hole: CGRect) -> CGImage {
        let context = CGContext(
            data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 0, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.setBlendMode(.clear)
        context.fill(CGRect(x: hole.minX, y: CGFloat(size.height) - hole.maxY, width: hole.width, height: hole.height))
        return context.makeImage()!
    }

    struct Bitmap {
        let width: Int, height: Int
        fileprivate let bytes: [UInt8]

        subscript(x: Int, y: Int) -> RGBA {
            let i = (y * width + x) * 4
            return RGBA(red: bytes[i], green: bytes[i + 1], blue: bytes[i + 2], alpha: bytes[i + 3])
        }

        /// Whether any pixel inside `rect` satisfies `predicate`.
        func contains(in rect: CGRect, where predicate: (RGBA) -> Bool) -> Bool {
            let x0 = max(0, Int(rect.minX)), x1 = min(width, Int(rect.maxX))
            let y0 = max(0, Int(rect.minY)), y1 = min(height, Int(rect.maxY))
            for y in y0..<max(y0, y1) { for x in x0..<max(x0, x1) where predicate(self[x, y]) { return true } }
            return false
        }
    }

    static func bitmap(_ image: CGImage) -> Bitmap {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Bitmap(width: image.width, height: image.height, bytes: bytes)
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA {
        bitmap(image)[x, y]
    }
}

extension RGBA {
    static let pWhite = RGBA(red: 255, green: 255, blue: 255)
    static let pBlack = RGBA(red: 0, green: 0, blue: 0)
    static let pRed = RGBA(red: 255, green: 0, blue: 0)

    func isClose(to other: RGBA, tolerance: Int = 6) -> Bool {
        abs(Int(red) - Int(other.red)) <= tolerance && abs(Int(green) - Int(other.green)) <= tolerance
            && abs(Int(blue) - Int(other.blue)) <= tolerance
    }
}
