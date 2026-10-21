// Regenerate: swift Tools/GenerateAppIcon.swift
// Package: iconutil -c icns .build/AppIcon.iconset -o App/Resources/AppIcon.icns
// The approved artwork is the source of truth; preserve its transparency.
import AppKit

let source = URL(fileURLWithPath: "App/Resources/AppIcon.png")
let output = URL(fileURLWithPath: ".build/AppIcon.iconset")
guard let image = NSImage(contentsOf: source) else {
    fatalError("Cannot load App/Resources/AppIcon.png")
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let pixels = size * factor
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                   from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = factor == 2 ? "@2x" : ""
        let destination = output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
    }
}
