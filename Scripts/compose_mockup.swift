#!/usr/bin/env swift

import Foundation
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - Apple App Store Device Presets
// Source: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
// As of 2024, only one iPhone and one iPad size is required — Apple scales automatically.

enum DevicePreset: String, CaseIterable {
    // iPhones
    case iphone69   = "iphone69"    // iPhone 16 Plus / Pro Max — REQUIRED
    case iphone65   = "iphone65"    // iPhone 14 Plus / 13 Pro Max (legacy fallback)
    case iphone61   = "iphone61"    // iPhone 16 / 15 / 14
    case iphone55   = "iphone55"    // iPhone 8 Plus (legacy)
    case iphone47   = "iphone47"    // iPhone SE 3rd gen
    // iPads
    case ipad13     = "ipad13"      // iPad Pro 13" — REQUIRED for iPad
    case ipad11     = "ipad11"      // iPad Pro 11" / iPad Air 11"
    case ipad105    = "ipad105"     // iPad Pro 10.5" (legacy)
    case ipad97     = "ipad97"      // iPad / iPad mini (legacy)
    // Apple TV
    case appletv    = "appletv"     // Apple TV (1920×1080)

    // Portrait canvas size (Apple-required pixel dimensions)
    // Apple TV uses landscape-native 1920×1080, so portraitSize stores width < height.
    var portraitSize: CGSize {
        switch self {
        case .iphone69:  return CGSize(width: 1320, height: 2868)
        case .iphone65:  return CGSize(width: 1242, height: 2688)
        case .iphone61:  return CGSize(width: 1179, height: 2556)
        case .iphone55:  return CGSize(width: 1242, height: 2208)
        case .iphone47:  return CGSize(width: 750,  height: 1334)
        case .ipad13:    return CGSize(width: 2064, height: 2752)
        case .ipad11:    return CGSize(width: 1668, height: 2388)
        case .ipad105:   return CGSize(width: 1668, height: 2224)
        case .ipad97:    return CGSize(width: 1536, height: 2048)
        case .appletv:   return CGSize(width: 1080, height: 1920)
        }
    }

    var landscapeSize: CGSize {
        CGSize(width: portraitSize.height, height: portraitSize.width)
    }

    var displayName: String {
        switch self {
        case .iphone69:  return "iPhone 6.9\" (16 Plus/Pro Max) ⭐ Required"
        case .iphone65:  return "iPhone 6.5\" (14 Plus/13 Pro Max)"
        case .iphone61:  return "iPhone 6.1\" (16/15/14)"
        case .iphone55:  return "iPhone 5.5\" (8 Plus)"
        case .iphone47:  return "iPhone 4.7\" (SE 3rd gen)"
        case .ipad13:    return "iPad 13\" (Pro 13\") ⭐ Required"
        case .ipad11:    return "iPad 11\" (Pro 11\" / Air 11\")"
        case .ipad105:   return "iPad 10.5\" (Pro 10.5\")"
        case .ipad97:    return "iPad 9.7\" (iPad / mini)"
        case .appletv:   return "Apple TV (1920×1080)"
        }
    }
}

// MARK: - Configuration

struct Config {
    let framePath: String
    let screenshotPath: String
    let outputPath: String
    let gradientStart: NSColor
    let gradientEnd: NSColor
    let canvasSize: CGSize
    let screenRect: CGRect?         // nil = auto-detect from frame PNG
    let gradientAngle: Double
    let orientation: Orientation
    let minMargin: CGFloat          // minimum margin around frame in pixels
    let device: DevicePreset

    enum Orientation { case portrait, landscape }
}

// MARK: - Gradient

func drawGradient(in context: CGContext, size: CGSize, startColor: NSColor, endColor: NSColor, angle: Double) {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return }
    let start = startColor.usingColorSpace(.sRGB) ?? startColor
    let end   = endColor.usingColorSpace(.sRGB)   ?? endColor
    let colors = [start.cgColor, end.cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) else { return }
    let rad = angle * .pi / 180.0
    let cx = size.width / 2, cy = size.height / 2
    let halfLen = sqrt(size.width * size.width + size.height * size.height) / 2
    let startPt = CGPoint(x: cx - cos(rad) * halfLen, y: cy - sin(rad) * halfLen)
    let endPt   = CGPoint(x: cx + cos(rad) * halfLen, y: cy + sin(rad) * halfLen)
    context.drawLinearGradient(gradient, start: startPt, end: endPt,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// MARK: - Auto-detect transparent screen area

func detectScreenRect(in image: CGImage) -> CGRect? {
    let w = image.width, h = image.height
    guard let data = image.dataProvider?.data,
          let ptr  = CFDataGetBytePtr(data) else { return nil }
    let bpp = image.bitsPerPixel / 8
    let bpr = image.bytesPerRow

    func alpha(_ x: Int, _ y: Int) -> UInt8 {
        guard x >= 0 && x < w && y >= 0 && y < h else { return 255 }
        let offset = y * bpr + x * bpp
        return bpp >= 4 ? ptr[offset + 3] : 255
    }

    func pixelRGB(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        guard x >= 0 && x < w && y >= 0 && y < h else { return (255, 255, 255) }
        let offset = y * bpr + x * bpp
        return (Int(ptr[offset]), Int(ptr[offset + 1]), Int(ptr[offset + 2]))
    }

    // Strategy 1: Frame with transparent screen area
    // Scan from outside inward looking for: transparent → opaque bezel → transparent screen
    // Scan at x = w/4 (left quarter) to avoid the notch/Dynamic Island in the center
    let scanX = w / 4
    let scanY = h / 2

    var foundBezel = false
    var screenTop = 0
    // Scan from top
    foundBezel = false
    for y in 0..<h {
        let a = alpha(scanX, y)
        if !foundBezel && a > 200 { foundBezel = true }
        else if foundBezel && a < 10 { screenTop = y; break }
    }

    // Scan from bottom
    var screenBottom = h - 1
    foundBezel = false
    for y in stride(from: h - 1, through: 0, by: -1) {
        let a = alpha(scanX, y)
        if !foundBezel && a > 200 { foundBezel = true }
        else if foundBezel && a < 10 { screenBottom = y; break }
    }

    // Scan from left
    var screenLeft = 0
    foundBezel = false
    for x in 0..<w {
        let a = alpha(x, scanY)
        if !foundBezel && a > 200 { foundBezel = true }
        else if foundBezel && a < 10 { screenLeft = x; break }
    }

    // Scan from right
    var screenRight = w - 1
    foundBezel = false
    for x in stride(from: w - 1, through: 0, by: -1) {
        let a = alpha(x, scanY)
        if !foundBezel && a > 200 { foundBezel = true }
        else if foundBezel && a < 10 { screenRight = x; break }
    }

    let screenW = screenRight - screenLeft + 1
    let screenH = screenBottom - screenTop + 1
    if screenW > w / 3 && screenH > h / 3 {
        print("   ✅ Found transparent screen area (edge-scan)")
        return CGRect(x: screenLeft, y: screenTop, width: screenW, height: screenH)
    }

    // Strategy 2: Frame with black screen area (no transparency)
    // Scan from center outward to find where non-black pixels start
    let cx = w / 2, cy = h / 2
    let (cr, cg, cb) = pixelRGB(cx, cy)
    if cr < 10 && cg < 10 && cb < 10 {
        print("   ℹ️  No transparent screen area, looking for black screen area...")
        var left = cx, right = cx, top = cy, bottom = cy

        for x in stride(from: cx, through: 0, by: -1) {
            let (r, g, b) = pixelRGB(x, cy)
            if !(r < 10 && g < 10 && b < 10) { left = x + 1; break }
        }
        for x in cx..<w {
            let (r, g, b) = pixelRGB(x, cy)
            if !(r < 10 && g < 10 && b < 10) { right = x - 1; break }
        }
        for y in stride(from: cy, through: 0, by: -1) {
            let (r, g, b) = pixelRGB(cx, y)
            if !(r < 10 && g < 10 && b < 10) { top = y + 1; break }
        }
        for y in cy..<h {
            let (r, g, b) = pixelRGB(cx, y)
            if !(r < 10 && g < 10 && b < 10) { bottom = y - 1; break }
        }

        let rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        if rect.width > CGFloat(w) / 3 && rect.height > CGFloat(h) / 3 {
            print("   ✅ Found black screen area (center-scan)")
            return rect
        }
    }

    return nil
}

// Scale a rect detected in frame PNG native resolution → target canvas resolution
func scaleRect(_ rect: CGRect, from src: CGSize, to dst: CGSize) -> CGRect {
    CGRect(
        x: rect.origin.x * (dst.width  / src.width),
        y: rect.origin.y * (dst.height / src.height),
        width:  rect.width  * (dst.width  / src.width),
        height: rect.height * (dst.height / src.height)
    )
}

// MARK: - Compositing

/// Calculate the rect to draw the frame into, scaled to fit the canvas with minimum margin.
/// The frame is centered and scaled uniformly (aspect-fit).
func frameRect(frameSize: CGSize, canvasSize: CGSize, minMargin: CGFloat) -> CGRect {
    let availableWidth  = canvasSize.width  - 2 * minMargin
    let availableHeight = canvasSize.height - 2 * minMargin
    let scaleX = availableWidth  / frameSize.width
    let scaleY = availableHeight / frameSize.height
    let scale  = min(scaleX, scaleY) // aspect-fit
    let scaledW = frameSize.width  * scale
    let scaledH = frameSize.height * scale
    let originX = (canvasSize.width  - scaledW) / 2
    let originY = (canvasSize.height - scaledH) / 2
    return CGRect(x: originX, y: originY, width: scaledW, height: scaledH)
}

/// Map a rect from the frame's native pixel space to the canvas coordinate space,
/// given where the frame is drawn on the canvas.
func mapRectToCanvas(screenRectInFrame: CGRect, frameNativeSize: CGSize, frameRectOnCanvas: CGRect) -> CGRect {
    let scaleX = frameRectOnCanvas.width  / frameNativeSize.width
    let scaleY = frameRectOnCanvas.height / frameNativeSize.height
    return CGRect(
        x: frameRectOnCanvas.origin.x + screenRectInFrame.origin.x * scaleX,
        y: frameRectOnCanvas.origin.y + screenRectInFrame.origin.y * scaleY,
        width:  screenRectInFrame.width  * scaleX,
        height: screenRectInFrame.height * scaleY
    )
}

func composeMockup(config: Config) throws {
    // Load images
    guard let frameNSImage = NSImage(contentsOfFile: config.framePath),
          let frameCGImage = frameNSImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { throw err(1, "Cannot load frame: \(config.framePath)") }

    guard let ssNSImage = NSImage(contentsOfFile: config.screenshotPath),
          let ssCGImage = ssNSImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { throw err(2, "Cannot load screenshot: \(config.screenshotPath)") }

    let canvasSize = config.canvasSize
    let frameNativeSize = CGSize(width: frameCGImage.width, height: frameCGImage.height)

    // Calculate where the frame goes on the canvas (scaled, centered, with margin)
    let frameOnCanvas = frameRect(frameSize: frameNativeSize, canvasSize: canvasSize, minMargin: config.minMargin)
    print("📱 Frame  : \(Int(frameNativeSize.width))×\(Int(frameNativeSize.height)) px")
    print("📱 Scaled : \(Int(frameOnCanvas.width))×\(Int(frameOnCanvas.height)) px (margin: \(Int(config.minMargin))px)")
    print("📱 Position: (\(Int(frameOnCanvas.origin.x)), \(Int(frameOnCanvas.origin.y)))")

    // Detect where the screen area is in the frame's native pixels
    let screenRectOnCanvas: CGRect
    if let manualRect = config.screenRect {
        screenRectOnCanvas = manualRect
        print("📐 Screen rect (manual): \(screenRectOnCanvas)")
    } else {
        print("🔍 Auto-detecting screen area in frame...")
        if let detectedInFrame = detectScreenRect(in: frameCGImage) {
            screenRectOnCanvas = mapRectToCanvas(
                screenRectInFrame: detectedInFrame,
                frameNativeSize: frameNativeSize,
                frameRectOnCanvas: frameOnCanvas
            )
            print("   Detected in frame: \(Int(detectedInFrame.origin.x)),\(Int(detectedInFrame.origin.y)),\(Int(detectedInFrame.width)),\(Int(detectedInFrame.height))")
            print("   Mapped to canvas : \(Int(screenRectOnCanvas.origin.x)),\(Int(screenRectOnCanvas.origin.y)),\(Int(screenRectOnCanvas.width)),\(Int(screenRectOnCanvas.height))")
        } else {
            // Fallback: 60% width, 70% height, centered
            let w = canvasSize.width * 0.6
            let h = canvasSize.height * 0.7
            screenRectOnCanvas = CGRect(x: (canvasSize.width - w) / 2, y: (canvasSize.height - h) / 2, width: w, height: h)
            print("   ⚠️  Could not detect screen area, using fallback: \(screenRectOnCanvas)")
        }
    }

    // Create bitmap context with alpha for compositing
    let bw = Int(canvasSize.width), bh = Int(canvasSize.height)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil, width: bw, height: bh,
            bitsPerComponent: 8, bytesPerRow: bw * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { throw err(3, "Cannot create CGContext") }

    // CGContext uses bottom-left origin. Our detected rects are in top-left origin.
    // Convert all rects to bottom-left origin for drawing.
    func flipY(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x,
               y: canvasSize.height - rect.origin.y - rect.height,
               width: rect.width,
               height: rect.height)
    }

    let frameDrawRect  = flipY(frameOnCanvas)
    let screenDrawRect = flipY(screenRectOnCanvas)

    // Corner radius for the screenshot (device-specific: iPhones have rounder corners than iPads)
    let cornerRadiusFactor: CGFloat
    switch config.device {
    case .ipad13, .ipad11, .ipad105, .ipad97:
        cornerRadiusFactor = 0.02
    case .appletv:
        cornerRadiusFactor = 0.01
    default:
        cornerRadiusFactor = 0.15
    }
    let cornerRadius = screenDrawRect.width * cornerRadiusFactor

    // Draw layers:
    // 1. Gradient background (fills entire canvas)
    drawGradient(in: context, size: canvasSize,
                 startColor: config.gradientStart, endColor: config.gradientEnd,
                 angle: config.gradientAngle)

    // 2. Screenshot with rounded corners (clipped so corners don't peek through frame)
    context.saveGState()
    let roundedPath = CGPath(roundedRect: screenDrawRect,
                             cornerWidth: cornerRadius,
                             cornerHeight: cornerRadius,
                             transform: nil)
    context.addPath(roundedPath)
    context.clip()
    context.draw(ssCGImage, in: screenDrawRect)
    context.restoreGState()

    // 3. Device frame on top (transparency lets the screenshot show through)
    context.draw(frameCGImage, in: frameDrawRect)

    // Flatten to opaque PNG (App Store requires no alpha channel)
    guard let composited = context.makeImage() else { throw err(4, "Cannot create composited image") }

    guard let opaqueContext = CGContext(
            data: nil, width: bw, height: bh,
            bitsPerComponent: 8, bytesPerRow: bw * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          )
    else { throw err(4, "Cannot create opaque context") }
    opaqueContext.draw(composited, in: CGRect(x: 0, y: 0, width: bw, height: bh))

    guard let outputImage = opaqueContext.makeImage() else { throw err(4, "Cannot create output image") }
    let outputURL = URL(fileURLWithPath: config.outputPath)
    guard let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw err(5, "Cannot write to: \(config.outputPath)") }
    CGImageDestinationAddImage(dest, outputImage, nil)
    guard CGImageDestinationFinalize(dest) else { throw err(6, "Failed to finalize output file") }

    print("✅ Saved: \(config.outputPath)  [\(bw)×\(bh) px]")
}

func err(_ code: Int, _ msg: String) -> NSError {
    NSError(domain: "composeMockup", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
}

// MARK: - CLI

func printUsage() {
    let presetList = DevicePreset.allCases
        .map { "    \($0.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) \($0.displayName)" }
        .joined(separator: "\n")
    print("""
    Usage:
      swift compose_mockup.swift --frame <frame.png> --screenshot <screen.png> --output <out.png> [options]

    Required:
      --frame        Device frame PNG with transparent screen area
      --screenshot   App screenshot PNG
      --output       Output file path (.png)

    Device preset (determines Apple-required canvas resolution):
      --device       Preset name (default: iphone69)
      --landscape    Use landscape orientation

    Available presets:
    \(presetList)

    Gradient options:
      --gradient-start  Hex color (default: #667EEA)
      --gradient-end    Hex color (default: #764BA2)
      --angle           Degrees   (default: 135)

    Advanced overrides:
      --screen-rect   x,y,w,h in canvas pixels (skips auto-detect)
      --canvas-size   w,h pixels (overrides device preset)
      --margin        Minimum margin around frame in pixels (default: 30)

    Examples:
      swift compose_mockup.swift --frame iphone_frame.png --screenshot app.png --output mockup.png
      swift compose_mockup.swift --frame ipad_frame.png   --screenshot app.png --output mockup.png --device ipad13
      swift compose_mockup.swift --frame appletv_frame.png --screenshot app.png --output mockup.png --device appletv --landscape
      swift compose_mockup.swift --frame iphone_frame.png --screenshot app.png --output mockup.png \\
        --gradient-start '#FF6B6B' --gradient-end '#4ECDC4' --angle 120 --landscape
    """)
}

func hexToNSColor(_ hex: String) -> NSColor {
    var h = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    guard h.count == 6, let value = UInt64(h, radix: 16) else { return .systemBlue }
    let r: CGFloat = CGFloat((value >> 16) & 0xFF) / 255.0
    let g: CGFloat = CGFloat((value >> 8) & 0xFF) / 255.0
    let b: CGFloat = CGFloat(value & 0xFF) / 255.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
}

// MARK: - Entry Point

var args = CommandLine.arguments.dropFirst()
var framePath: String?
var screenshotPath: String?
var outputPath: String?
var gradientStart = "#667EEA"
var gradientEnd   = "#764BA2"
var angle         = 135.0
var deviceArg     = "iphone69"
var landscape     = false
var screenRectArg: String?
var canvasSizeArg: String?
var margin: CGFloat = 30.0

var iter = args.makeIterator()
while let arg = iter.next() {
    switch arg {
    case "--frame":           framePath     = iter.next()
    case "--screenshot":      screenshotPath = iter.next()
    case "--output":          outputPath    = iter.next()
    case "--device":          deviceArg     = iter.next() ?? deviceArg
    case "--landscape":       landscape     = true
    case "--gradient-start":  gradientStart = iter.next() ?? gradientStart
    case "--gradient-end":    gradientEnd   = iter.next() ?? gradientEnd
    case "--angle":           angle         = Double(iter.next() ?? "") ?? angle
    case "--screen-rect":     screenRectArg = iter.next()
    case "--canvas-size":     canvasSizeArg = iter.next()
    case "--margin":          margin        = CGFloat(Double(iter.next() ?? "") ?? 30.0)
    case "--help", "-h":      printUsage(); exit(0)
    default: break
    }
}

guard let frame = framePath, let screenshot = screenshotPath, let output = outputPath else {
    printUsage(); exit(1)
}

guard let preset = DevicePreset(rawValue: deviceArg) else {
    print("❌ Unknown device '\(deviceArg)'. Run --help for the full list.")
    exit(1)
}

var canvasSize = landscape ? preset.landscapeSize : preset.portraitSize
if let s = canvasSizeArg {
    let parts = s.split(separator: ",").compactMap { Double($0) }
    if parts.count == 2 { canvasSize = CGSize(width: parts[0], height: parts[1]) }
}

var screenRect: CGRect? = nil
if let s = screenRectArg {
    let parts = s.split(separator: ",").compactMap { Double($0) }
    if parts.count == 4 { screenRect = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]) }
}

print("📐 Device : \(preset.displayName)")
print("📐 Canvas : \(Int(canvasSize.width))×\(Int(canvasSize.height)) px (\(landscape ? "landscape" : "portrait"))")

let config = Config(
    framePath: frame,
    screenshotPath: screenshot,
    outputPath: output,
    gradientStart: hexToNSColor(gradientStart),
    gradientEnd: hexToNSColor(gradientEnd),
    canvasSize: canvasSize,
    screenRect: screenRect,
    gradientAngle: angle,
    orientation: landscape ? .landscape : .portrait,
    minMargin: margin,
    device: preset
)

do {
    try composeMockup(config: config)
} catch {
    print("❌ \(error.localizedDescription)")
    exit(1)
}
