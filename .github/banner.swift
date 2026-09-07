// Regenerates .github/banner.png (1200x630, the OG image ratio).
//
//   swiftc -O -o /tmp/bannergen .github/banner.swift
//   /tmp/bannergen .github/banner.png
//
// The rings are drawn with the same construction as Rendering.swift — arc from
// the top, clockwise, over a faint track — so the banner cannot promise a look
// the product does not have.

import AppKit

let W: CGFloat = 1200, H: CGFloat = 630

func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: alpha)
}

let background = hex(0x0D0F12)
let foreground = hex(0xF2F4F7)
let muted      = hex(0x8B94A3)
let faint      = hex(0x6B7484)
let track      = hex(0xFFFFFF, 0.16)
let attention  = hex(0xFFC24B)
let critical   = hex(0xFF6B6B)

/// The same three steps the bar uses, at their default thresholds.
func color(for pct: Int) -> NSColor {
    if pct >= 95 { return critical }
    if pct >= 60 { return attention }
    return foreground
}

func ring(_ pct: Int, centre: NSPoint, radius: CGFloat, width: CGFloat) {
    let back = NSBezierPath()
    back.appendArc(withCenter: centre, radius: radius, startAngle: 0, endAngle: 360)
    back.lineWidth = width
    track.setStroke()
    back.stroke()

    guard pct > 0 else { return }
    let arc = NSBezierPath()
    arc.appendArc(withCenter: centre, radius: radius, startAngle: 90,
                  endAngle: 90 - 360 * CGFloat(min(pct, 100)) / 100, clockwise: true)
    arc.lineWidth = width
    arc.lineCapStyle = .round
    color(for: pct).setStroke()
    arc.stroke()
}

/// Draws the string and returns its width, so callers can lay out left to right
/// — or right to left, which is how the menu bar fills up.
@discardableResult
func write(_ text: String, at point: NSPoint, size: CGFloat,
           weight: NSFont.Weight = .regular, color: NSColor = foreground,
           mono: Bool = false) -> CGFloat {
    let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                    : NSFont.systemFont(ofSize: size, weight: weight)
    let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    s.draw(at: point)
    return s.size().width
}

let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)

background.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()

// The menu bar strip along the top, where the thing actually lives.
let stripHeight: CGFloat = 62
hex(0xFFFFFF, 0.05).setFill()
NSBezierPath(rect: NSRect(x: 0, y: H - stripHeight, width: W, height: stripHeight)).fill()
hex(0xFFFFFF, 0.09).setFill()
NSBezierPath(rect: NSRect(x: 0, y: H - stripHeight, width: W, height: 1)).fill()

// The indicator at 2x, pinned right, filling leftwards as the real bar does.
var x = W - 60.0
let cy = H - stripHeight / 2
x -= write("21:04", at: NSPoint(x: x - 76, y: cy - 14), size: 23, weight: .medium,
           color: muted, mono: true) + 46
for pct in [71, 34] {
    let numberWidth = write("\(pct)", at: NSPoint(x: x - 32, y: cy - 15), size: 25,
                            weight: .medium, color: color(for: pct), mono: true)
    x -= numberWidth + 12
    ring(pct, centre: NSPoint(x: x - 15, y: cy), radius: 15, width: 5.4)
    x -= 64
}

// Left column: the name and the promise.
write("claude-usage-bar", at: NSPoint(x: 92, y: 372), size: 68, weight: .semibold)
write("macos", at: NSPoint(x: 96, y: 318), size: 68, weight: .semibold, color: hex(0x4A5260))
write("Your Claude plan usage in the macOS menu bar —",
      at: NSPoint(x: 94, y: 254), size: 26, color: muted)
write("the 5-hour window and the weekly one, live.",
      at: NSPoint(x: 94, y: 216), size: 26, color: muted)
write("macOS 13+   ·   Swift   ·   no token, no network   ·   MIT",
      at: NSPoint(x: 94, y: 110), size: 20, weight: .medium, color: faint)

// Right column: colour carries the level, weight reinforces it at critical.
let legendX: CGFloat = 800
var legendY: CGFloat = 372
for (pct, label) in [(34, "room to spare"), (71, "getting tight"), (96, "critical")] {
    ring(pct, centre: NSPoint(x: legendX + 30, y: legendY + 14), radius: 30, width: 7.5)
    write("\(pct)", at: NSPoint(x: legendX + 78, y: legendY), size: 30,
          weight: pct >= 95 ? .bold : .medium, color: color(for: pct), mono: true)
    write(label, at: NSPoint(x: legendX + 130, y: legendY + 6), size: 17, color: faint)
    legendY -= 96
}

NSGraphicsContext.restoreGraphicsState()

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "banner.png"
try canvas.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
