import AppKit

// Package the original painting with the standard macOS icon inset and rounded silhouette.
guard CommandLine.arguments.count == 3,
    let painting = NSImage(contentsOfFile: CommandLine.arguments[1]),
    painting.size.width == painting.size.height
else {
    fatalError("Usage: swift scripts/GenerateIcon.swift square-painting.png output-directory")
}
let output = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let n = CGFloat(pixels)
        let rect = NSRect(x: n * 0.07, y: n * 0.07, width: n * 0.86, height: n * 0.86)
        let path = NSBezierPath(roundedRect: rect, xRadius: n * 0.20, yRadius: n * 0.20)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = n * 0.025
        shadow.shadowOffset = NSSize(width: 0, height: -n * 0.012)
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        painting.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.32).setStroke()
        path.lineWidth = max(0.5, n * 0.002)
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
