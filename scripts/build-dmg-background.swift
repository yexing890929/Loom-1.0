import AppKit

// Figma 8666:15674 at 50%: 600 × 400 pt, rendered at 2×.
let output = CommandLine.arguments[1]
let arrowURL = URL(fileURLWithPath: CommandLine.arguments[2])
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: 600, height: 400)
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(srgbRed: 244/255, green: 245/255, blue: 248/255, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 600, height: 400).fill()
guard let arrow = NSImage(contentsOf: arrowURL) else { fatalError("Missing installation arrow") }
arrow.draw(in: NSRect(x: 273.75, y: 400 - 171 - 9.205, width: 52.5, height: 18.41))
let slogan = NSAttributedString(string: "Loom - 窗口随心，布局从容", attributes: [
    .font: NSFont.systemFont(ofSize: 9),
    .foregroundColor: NSColor(srgbRed: 128/255, green: 128/255, blue: 128/255, alpha: 1),
    .kern: 3.6
])
let textSize = slogan.size()
slogan.draw(at: NSPoint(x: (600 - textSize.width) / 2, y: 400 - 363.5 - textSize.height))
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
