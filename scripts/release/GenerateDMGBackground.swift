import AppKit
import CoreImage

let arguments = CommandLine.arguments
let numbers = arguments.dropFirst(3).compactMap { Double($0) }.map { CGFloat($0) }
guard arguments.count == 9, numbers.count == 6, let painting = NSImage(contentsOfFile: arguments[1]) else {
    fatalError(
        "Usage: swift scripts/release/GenerateDMGBackground.swift painting.png output-directory width height icon-size icon-y app-x applications-x"
    )
}
let output = URL(fileURLWithPath: arguments[2])
let (width, height, iconSize, iconY, appX, applicationsX) = (
    numbers[0], numbers[1], numbers[2], numbers[3], numbers[4], numbers[5]
)

let surface = NSColor(deviceWhite: 0.035, alpha: 1)
let accent = NSColor(deviceWhite: 0.92, alpha: 1)
let secondary = NSColor(deviceWhite: 0.62, alpha: 1)

let pillSize = NSSize(width: 120, height: 26)
let pillTop = iconY + iconSize / 2 + 6
let panelPadding: CGFloat = 48
let panelInset: CGFloat = 60

// Finder measures y down from the top of the window, AppKit up from the bottom.
func flipped(_ y: CGFloat) -> CGFloat { height - y }

func coverRect(for size: NSSize, in bounds: NSRect, anchorY: CGFloat) -> NSRect {
    let scale = max(bounds.width / size.width, bounds.height / size.height)
    let w = size.width * scale
    let h = size.height * scale
    return NSRect(x: bounds.midX - w / 2, y: bounds.minY - (h - bounds.height) * anchorY, width: w, height: h)
}

// Finder draws icon labels in black on any custom background, in light and dark mode, so each label sits on a light pill.
func pill(centerX: CGFloat) {
    let rect = NSRect(
        x: centerX - pillSize.width / 2, y: flipped(pillTop + pillSize.height),
        width: pillSize.width, height: pillSize.height)
    accent.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
}

func arrow() {
    let y = flipped(iconY)
    let mid = (appX + applicationsX) / 2
    let half: CGFloat = 26
    let head: CGFloat = 9
    let path = NSBezierPath()
    path.move(to: NSPoint(x: mid - half, y: y))
    path.line(to: NSPoint(x: mid + half, y: y))
    path.move(to: NSPoint(x: mid + half - head, y: y + head))
    path.line(to: NSPoint(x: mid + half, y: y))
    path.line(to: NSPoint(x: mid + half - head, y: y - head))
    path.lineWidth = 2
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    secondary.setStroke()
    path.stroke()
}

func blurred(_ image: NSImage, sigma: Double) -> NSImage {
    guard let data = image.tiffRepresentation, let source = CIImage(data: data) else {
        fatalError("The painting cannot be read as an image.")
    }
    let soft = source.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: source.extent)
    // Without the software renderer, a machine with no GPU access draws nothing and reports no error.
    let context = CIContext(options: [.useSoftwareRenderer: true])
    guard let rendered = context.createCGImage(soft, from: source.extent) else {
        fatalError("Core Image could not blur the painting.")
    }
    return NSImage(cgImage: rendered, size: image.size)
}
let sky = blurred(painting, sigma: 10)

func draw() {
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    sky.draw(
        in: coverRect(for: painting.size, in: bounds, anchorY: 0.45), from: .zero, operation: .sourceOver,
        fraction: 1)
    let panelTop = iconY - iconSize / 2 - panelPadding
    let panelBottom = pillTop + pillSize.height + panelPadding
    let panel = NSRect(
        x: panelInset, y: flipped(panelBottom), width: width - 2 * panelInset, height: panelBottom - panelTop)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    surface.setFill()
    NSBezierPath(roundedRect: panel, xRadius: 16, yRadius: 16).fill()
    NSGraphicsContext.restoreGraphicsState()
    pill(centerX: appX)
    pill(centerX: applicationsX)
    arrow()
}

for scale in [1, 2] {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let name = "background\(scale == 2 ? "@2x" : "").png"
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
