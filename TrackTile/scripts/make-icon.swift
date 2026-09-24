#!/usr/bin/env swift
// Builds Resources/AppIcon.png and Resources/AppIcon.icns from the artwork in
// Resources/AppIcon-source.png.
//
// The source is an opaque square with the icon tile on a light background. The
// tile is found by its dark pixels, cropped, and redrawn on a transparent
// canvas following the macOS icon grid (824 pt tile, 100 pt margin at 1024).
//
// Usage: swift scripts/make-icon.swift   (from the TrackTile directory)
import AppKit
import CoreGraphics
import Foundation

let resources = URL(fileURLWithPath: "Resources")
let sourceURL = resources.appendingPathComponent("AppIcon-source.png")
let pngURL = resources.appendingPathComponent("AppIcon.png")
let icnsURL = resources.appendingPathComponent("AppIcon.icns")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard let source = NSImage(contentsOf: sourceURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("Can't read \(sourceURL.path)")
}

// Read pixels as RGBA8 to find the tile's bounding box.
let width = source.width
let height = source.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
pixels.withUnsafeMutableBytes { buffer in
    let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
}

var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
        // The tile background is a dark indigo/violet; the checkerboard is light gray.
        if r + g + b < 360, b > r + 20 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
guard maxX > minX, maxY > minY else { fail("Couldn't find the icon tile in the source image") }

// Pixel rows above were read top-down; CGImage cropping also uses top-left origin.
let inset = 2
let tileRect = CGRect(
    x: minX + inset, y: minY + inset, width: maxX - minX - 2 * inset, height: maxY - minY - 2 * inset
)
guard let tile = source.cropping(to: tileRect) else { fail("Crop failed") }
print("Tile found at \(tileRect)")

func render(size: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    let scale = CGFloat(size) / 1024
    let box = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let radius = 185.4 * scale

    // Soft drop shadow like the system template.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setFillColor(NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.4, alpha: 1).cgColor)
    context.fillPath()
    context.restoreGState()

    context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    // Slightly overscale so the source's own rounded corners fall outside the clip.
    context.draw(tile, in: box.insetBy(dx: -8 * scale, dy: -8 * scale))
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("PNG encoding failed") }
    try! data.write(to: url)
}

writePNG(render(size: 1024), to: pngURL)

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(render(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fail("iconutil failed") }
print("Wrote \(pngURL.path) and \(icnsURL.path)")
