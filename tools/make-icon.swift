// Renders the 1024px app icon PNG: a graphite squircle with a white broom (the menu bar glyph).
// Usage: swift tools/make-icon.swift <output.png>

import AppKit

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824px body centred on a 1024px canvas
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(calibratedWhite: 0.10, alpha: 1),
           ending: NSColor(calibratedWhite: 0.27, alpha: 1))!.draw(in: shape, angle: 90)
NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
shape.lineWidth = 4
shape.stroke()
// A soft violet light behind the glyph: the app's accent, space you can free
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor(srgbRed: 0.68, green: 0.60, blue: 1.0, alpha: 0.26), .clear])!
    .draw(fromCenter: NSPoint(x: 512, y: 470), radius: 0, toCenter: NSPoint(x: 512, y: 470), radius: 420, options: [])
NSGraphicsContext.restoreGraphicsState()

// The menu bar glyph at icon size (16pt grid scaled to a 560px square, y flipped)
let u: CGFloat = 560 / 16, ox: CGFloat = 232, oy: CGFloat = 232
func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * u, y: oy + (16 - y) * u) }
NSColor.white.setStroke()
let handle = NSBezierPath()
handle.move(to: p(14, 2))
handle.line(to: p(9.2, 6.8))
handle.lineWidth = 1.7 * u
handle.lineCapStyle = .round
handle.stroke()
// Bristles, with strands cut out of them (in their own layer, so the cut shows the background)
let cg = NSGraphicsContext.current!.cgContext
cg.beginTransparencyLayer(auxiliaryInfo: nil)
let head = NSBezierPath()
head.move(to: p(7.4, 5.6))
for (x, y) in [(10.4, 8.6), (6.4, 14.4), (1.6, 9.6)] as [(CGFloat, CGFloat)] { head.line(to: p(x, y)) }
head.close()
NSColor.white.setFill()
head.fill()
cg.setBlendMode(.clear)
for (a, b) in [((8.0, 7.2), (3.3, 11.4)), ((9.0, 8.2), (5.0, 12.9))] as [((CGFloat, CGFloat), (CGFloat, CGFloat))] {
    let cut = NSBezierPath()
    cut.move(to: p(a.0, a.1))
    cut.line(to: p(b.0, b.1))
    cut.lineWidth = 0.55 * u
    cut.stroke()
}
cg.endTransparencyLayer()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
