import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: create-app-icon.swift <iconset-directory>\n", stderr)
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

/// Draws the EchoFetch icon on a 1024-point canvas, in the same family as EchoFlow's: a navy
/// rounded square (lighter at the top) on the standard macOS icon grid, a cyan-to-blue arrow
/// pointing down, and a white tray it drops into.
func drawIcon() {
    // macOS icon grid: an 824-point body centered on the 1024 canvas, with a soft drop shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0, 0, 0, 0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    color(0.07, 0.09, 0.16).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Slate at the top fading to near-black navy by the middle.
    let background = NSGradient(
        colors: [color(0.05, 0.07, 0.13), color(0.08, 0.11, 0.19), color(0.30, 0.36, 0.49)],
        atLocations: [0, 0.55, 1],
        colorSpace: .deviceRGB
    )
    background?.draw(in: bodyPath, angle: 90)
    color(1, 1, 1, 0.08).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
    rim.lineWidth = 3
    rim.stroke()

    // Arrow: a rounded shaft and a wide head pointing down, blue at the bottom to cyan at the top.
    let arrowGradient = NSGradient(
        colors: [color(0.17, 0.49, 0.94), color(0.35, 0.72, 1.0), color(0.55, 0.88, 1.0)],
        atLocations: [0, 0.5, 1],
        colorSpace: .deviceRGB
    )
    let arrowBounds = NSRect(x: 340, y: 318, width: 344, height: 452)
    let shaft = NSBezierPath(roundedRect: NSRect(x: 468, y: 470, width: 88, height: 300), xRadius: 44, yRadius: 44)
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 512, y: 500))
    head.appendArc(from: NSPoint(x: 684, y: 500), to: NSPoint(x: 512, y: 318), radius: 26)
    head.appendArc(from: NSPoint(x: 512, y: 318), to: NSPoint(x: 340, y: 500), radius: 34)
    head.appendArc(from: NSPoint(x: 340, y: 500), to: NSPoint(x: 512, y: 500), radius: 26)
    head.close()
    // Both parts share one gradient so the colors run on smoothly from the shaft into the head.
    for part in [shaft, head] {
        NSGraphicsContext.saveGraphicsState()
        part.addClip()
        arrowGradient?.draw(in: arrowBounds, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
    }

    // Tray: an open-topped rounded "U" under the arrow.
    color(0.97, 0.98, 1.0).setStroke()
    let tray = NSBezierPath()
    tray.move(to: NSPoint(x: 262, y: 380))
    tray.line(to: NSPoint(x: 262, y: 262))
    tray.appendArc(from: NSPoint(x: 262, y: 222), to: NSPoint(x: 302, y: 222), radius: 40)
    tray.line(to: NSPoint(x: 722, y: 222))
    tray.appendArc(from: NSPoint(x: 762, y: 222), to: NSPoint(x: 762, y: 262), radius: 40)
    tray.line(to: NSPoint(x: 762, y: 380))
    tray.lineWidth = 40
    tray.lineCapStyle = .round
    tray.lineJoinStyle = .round
    tray.stroke()
}

func renderIcon(pixelSize: Int, fileName: String) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "EchoFetchIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create icon bitmap"])
    }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "EchoFetchIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create icon graphics context"])
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(pixelSize) / 1024, y: CGFloat(pixelSize) / 1024)

    drawIcon()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "EchoFetchIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG"])
    }
    try data.write(to: iconsetURL.appendingPathComponent(fileName), options: .atomic)
}

let icons: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]
for (size, name) in icons {
    try renderIcon(pixelSize: size, fileName: name)
}
