import AppKit

// Use AppKit's SVG renderer at build time. Ship PDF so runtime loading works
// through the public NSImage API on all supported macOS versions.
guard CommandLine.arguments.count == 3,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      image.size.width > 0, image.size.height > 0 else {
    fatalError("Cannot load menu bar SVG")
}
let output = URL(fileURLWithPath: CommandLine.arguments[2])
var bounds = CGRect(origin: .zero, size: image.size)
guard let context = CGContext(output as CFURL, mediaBox: &bounds, nil) else {
    fatalError("Cannot create menu bar PDF")
}
context.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
context.endPDFPage()
context.closePDF()
