import CoreGraphics
import Foundation

public enum FrameImageError: Error, Equatable, CustomStringConvertible {
    case noTransparentScreen

    public var description: String {
        "The frame image has no transparent screen area in its center."
    }
}

/// Helpers for custom frame PNGs (an opaque device frame with a transparent screen).
public enum FrameImage {
    /// The transparent screen area in frame pixels (top-left origin): walk from the image center
    /// in all four directions until the first (almost) opaque pixel.
    public static func screenRect(in frame: CGImage) throws -> CGRect {
        let width = frame.width, height = frame.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: Composer.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * width + x) * 4 + 3] }

        let cx = width / 2, cy = height / 2
        guard alpha(cx, cy) < 10 else { throw FrameImageError.noTransparentScreen }

        guard let left = stride(from: cx, through: 0, by: -1).first(where: { alpha($0, cy) > 200 }),
              let right = stride(from: cx, to: width, by: 1).first(where: { alpha($0, cy) > 200 }),
              let top = stride(from: cy, through: 0, by: -1).first(where: { alpha(cx, $0) > 200 }),
              let bottom = stride(from: cy, to: height, by: 1).first(where: { alpha(cx, $0) > 200 })
        else { throw FrameImageError.noTransparentScreen }

        return CGRect(x: left + 1, y: top + 1, width: right - left - 1, height: bottom - top - 1)
    }
}
