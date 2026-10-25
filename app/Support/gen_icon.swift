// Intermezzo app-icon generator — rysuje ikonę (gradient + kubek + para)
// i zapisuje iconset; dalej iconutil robi .icns.
import AppKit

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func draw(_ s: CGFloat) -> Data? {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return nil }

    // Gradient rounded-rect background
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let radius = s * 0.2237 // Apple squircle approximation
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let grad = NSGradient(starting: NSColor(srgbRed: 0.05, green: 0.23, blue: 0.42, alpha: 1),
                          ending: NSColor(srgbRed: 0.00, green: 0.58, blue: 0.53, alpha: 1))
    grad?.draw(in: bg, angle: -90)

    NSColor.white.set()
    let u = s / 1024.0

    // Cup body (rounded trapezoid via rounded rect)
    let body = NSBezierPath(roundedRect: NSRect(x: 285 * u, y: 330 * u, width: 380 * u, height: 270 * u),
                            xRadius: 40 * u, yRadius: 20 * u)
    body.fill()

    // Handle (ring stroke on the right)
    let handle = NSBezierPath()
    handle.appendArc(withCenter: NSPoint(x: 700 * u, y: 465 * u),
                    radius: 110 * u, startAngle: -70, endAngle: 70)
    handle.lineWidth = 52 * u
    NSColor.white.setStroke()
    handle.stroke()

    // Saucer
    let saucer = NSBezierPath(ovalIn: NSRect(x: 190 * u, y: 215 * u, width: 570 * u, height: 95 * u))
    saucer.fill()

    // Steam — three wavy strokes
    NSColor(white: 1, alpha: 0.92).setStroke()
    for i in 0..<3 {
        let x = (390.0 + Double(i) * 105.0) * u
        let steam = NSBezierPath()
        steam.move(to: NSPoint(x: x, y: 640 * u))
        steam.curve(to: NSPoint(x: x, y: 760 * u),
                    controlPoint1: NSPoint(x: x - 55 * u, y: 680 * u),
                    controlPoint2: NSPoint(x: x + 55 * u, y: 720 * u))
        steam.lineWidth = 34 * u
        steam.lineCapStyle = .round
        steam.stroke()
    }

    img.unlockFocus()
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

for entry in sizes {
    guard let png = draw(CGFloat(entry.px)) else { fputs("FAIL \(entry.name)\n", stderr); continue }
    try? png.write(to: URL(fileURLWithPath: outDir + "/" + entry.name))
}
print("OK generated \(sizes.count) files into \(outDir)")
