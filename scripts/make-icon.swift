// Draws the app icon: a calendar sheet with a small spark, the selected text turning into an event.
// Usage: swift scripts/make-icon.swift <output.png>   (1024 x 1024; build.sh turns it into AppIcon.icns)
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

// Colours used by the icon, kept in one place.
let background = NSColor(srgbRed: 0.96, green: 0.93, blue: 0.88, alpha: 1)   // warm paper
let accent = NSColor(srgbRed: 0.85, green: 0.33, blue: 0.24, alpha: 1)       // coral
let sheet = NSColor.white
let ink = NSColor(srgbRed: 0.80, green: 0.76, blue: 0.70, alpha: 1)          // muted day marks

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: an 824 pt rounded square centred in the 1024 canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
background.setFill()
NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185).fill()

// Calendar sheet with a soft shadow.
let card = NSRect(x: 232, y: 222, width: 560, height: 560)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
sheet.setFill()
NSBezierPath(roundedRect: card, xRadius: 72, yRadius: 72).fill()
NSGraphicsContext.restoreGraphicsState()

// Header band in the accent colour, clipped to the sheet's rounded top.
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: card, xRadius: 72, yRadius: 72).addClip()
accent.setFill()
NSRect(x: card.minX, y: card.maxY - 132, width: card.width, height: 132).fill()
NSGraphicsContext.restoreGraphicsState()

// Day marks: three rows of four, one of them highlighted as the new event.
let columns = 4, rows = 3
let mark: CGFloat = 64, gapX: CGFloat = 48, gapY: CGFloat = 44
let gridWidth = CGFloat(columns) * mark + CGFloat(columns - 1) * gapX
let startX = card.midX - gridWidth / 2
let topY = card.maxY - 132 - 70 - mark
for row in 0..<rows {
    for column in 0..<columns {
        let rect = NSRect(x: startX + CGFloat(column) * (mark + gapX),
                          y: topY - CGFloat(row) * (mark + gapY), width: mark, height: mark)
        (row == 1 && column == 2 ? accent : ink).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18).fill()
    }
}

// Four-pointed spark at the upper right, in the accent colour with a white edge.
func spark(center: NSPoint, radius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let waist = radius * 0.28
    let points = [(0.0, 1.0), (1.0, 0.0), (0.0, -1.0), (-1.0, 0.0)]
    path.move(to: NSPoint(x: center.x, y: center.y + radius))
    for index in 0..<4 {
        let (x, y) = points[(index + 1) % 4]
        let (px, py) = points[index]
        let control = NSPoint(x: center.x + (px + x) * waist, y: center.y + (py + y) * waist)
        path.curve(to: NSPoint(x: center.x + x * radius, y: center.y + y * radius),
                   controlPoint1: control, controlPoint2: control)
    }
    path.close()
    return path
}
let sparkPath = spark(center: NSPoint(x: card.maxX - 40, y: card.maxY - 40), radius: 100)
NSColor.white.setStroke()
sparkPath.lineWidth = 24
sparkPath.stroke()
accent.setFill()
sparkPath.fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
