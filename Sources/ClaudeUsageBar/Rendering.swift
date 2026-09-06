// How preferences turn into the drawing on the bar button.
//
// Everything is drawn, text included: the parts can interleave (badge, ring,
// number, ring, number) and image + attributedTitle only manages "graphic
// first, text after". The price is losing the accessibility title for free —
// hence summary() at the bottom.

import Cocoa

private let hexRadius: CGFloat = 4.6
private let dotRadius: CGFloat = 4.0
private let ringRadius: CGFloat = 7.0
private let ringWidth: CGFloat = 2.6
private let barWidth: CGFloat = 18
private let barHeight: CGFloat = 3.4

/// Inside a window the gap is tight, so graphic and number read as one thing;
/// between parts it is wider, so they do not become a single block.
private let innerGap: CGFloat = 4
private let outerGap: CGFloat = 7

/// Half the stroke falls outside the radius: without this the ring touches the
/// image edge and its top comes out clipped.
private let inset = ringRadius + ringWidth / 2
private let iconHeight: CGFloat = 18

/// One piece of the drawing: knows the width it takes and how to draw itself
/// from an x, given the vertical centre.
private struct Piece {
    let width: CGFloat
    let draw: (CGFloat, CGFloat) -> Void
}

/// Lays pieces out horizontally.
private func group(_ pieces: [Piece], gap: CGFloat) -> Piece {
    let total = pieces.map(\.width).reduce(0, +) + gap * CGFloat(max(pieces.count - 1, 0))
    return Piece(width: total) { x, cy in
        var cursor = x
        for p in pieces {
            p.draw(cursor, cy)
            cursor += p.width + gap
        }
    }
}

private func textPiece(_ text: String, color: NSColor,
                       weight: NSFont.Weight = .medium, mono: Bool = true) -> Piece {
    let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: bodySize, weight: weight)
                    : NSFont.systemFont(ofSize: bodySize, weight: weight)
    let s = NSAttributedString(string: text, attributes: [.foregroundColor: color, .font: font])
    let size = s.size()
    return Piece(width: ceil(size.width)) { x, cy in
        s.draw(at: NSPoint(x: x, y: cy - size.height / 2))
    }
}

/// Point-up hexagon, the same shape as the ⬢ the terminal status line uses.
private func hexagonPiece(_ profile: String?) -> Piece {
    Piece(width: hexRadius * 2) { x, cy in
        let path = NSBezierPath()
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3 + .pi / 2
            let point = NSPoint(x: x + hexRadius + hexRadius * cos(a), y: cy + hexRadius * sin(a))
            i == 0 ? path.move(to: point) : path.line(to: point)
        }
        path.close()
        profileColor(profile).setFill()
        path.fill()
    }
}

private func dotPiece(_ profile: String?) -> Piece {
    Piece(width: dotRadius * 2) { x, cy in
        profileColor(profile).setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: cy - dotRadius,
                                    width: dotRadius * 2, height: dotRadius * 2)).fill()
    }
}

/// Progress arc starting at the top, clockwise, over a track.
private func ringPiece(_ pct: Int) -> Piece {
    Piece(width: inset * 2) { x, cy in
        let centre = NSPoint(x: x + inset, y: cy)
        let track = NSBezierPath()
        track.appendArc(withCenter: centre, radius: ringRadius, startAngle: 0, endAngle: 360)
        track.lineWidth = ringWidth
        trackColor.setStroke()
        track.stroke()

        guard pct > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: centre, radius: ringRadius, startAngle: 90,
                      endAngle: 90 - 360 * CGFloat(min(pct, 100)) / 100, clockwise: true)
        arc.lineWidth = ringWidth
        arc.lineCapStyle = .round
        usageColor(pct).setStroke()
        arc.stroke()
    }
}

/// Rounded bar filled in proportion. Minimum width is its own height, otherwise
/// 1% becomes a thin sliver that no longer reads as the same shape.
private func barPiece(_ pct: Int) -> Piece {
    Piece(width: barWidth) { x, cy in
        let rect = NSRect(x: x, y: cy - barHeight / 2, width: barWidth, height: barHeight)
        let radius = barHeight / 2
        trackColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        guard pct > 0 else { return }
        let w = max(barHeight, barWidth * CGFloat(min(pct, 100)) / 100)
        usageColor(pct).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: rect.minY, width: w, height: barHeight),
                     xRadius: radius, yRadius: radius).fill()
    }
}

private func windowPiece(_ shape: WindowShape, label: String, pct: Int) -> Piece {
    func number(_ text: String) -> Piece {
        textPiece(text, color: usageColor(pct), weight: usageWeight(pct))
    }
    switch shape {
    case .ringNumber: return group([ringPiece(pct), number("\(pct)")], gap: innerGap)
    case .ring:       return ringPiece(pct)
    case .barNumber:  return group([barPiece(pct), number("\(pct)")], gap: innerGap)
    case .bar:        return barPiece(pct)
    case .number:     return number("\(pct)")
    case .percent:    return number("\(pct)%")
    case .labelled:
        return group([textPiece(label, color: supportColor, mono: false), number("\(pct)%")], gap: 3)
    }
}

/// Placeholder while Claude is not running: something clickable that does not
/// pretend to be a reading.
private func dashPiece() -> Piece {
    Piece(width: 9) { x, cy in
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: cy - 1, width: 9, height: 2),
                     xRadius: 1, yRadius: 1).fill()
    }
}

private func profilePiece(_ shape: ProfileShape, profile: String?) -> Piece? {
    func name() -> Piece { textPiece(profile ?? "closed", color: profileColor(profile), mono: false) }
    switch shape {
    case .hexagon:     return hexagonPiece(profile)
    case .dot:         return dotPiece(profile)
    case .hexagonName: return group([hexagonPiece(profile), name()], gap: 5)
    case .name:        return name()
    case .hidden:      return nil
    }
}

/// A drawing block rather than a finished bitmap: that way the dynamic colours
/// resolve against the bar's appearance at draw time, and cacheMode .never makes
/// a wallpaper change redraw.
func barIcon(profile: String?, usage: Usage?) -> NSImage {
    var pieces: [Piece] = []
    if let p = profilePiece(Preferences.profileShape, profile: profile) { pieces.append(p) }
    if profile != nil, let usage {
        for (window, pct) in [(Window.fiveHour, usage.fiveHour), (Window.weekly, usage.weekly)] {
            guard let pct, Preferences.shows(window) else { continue }
            pieces.append(windowPiece(Preferences.shape(window), label: window.label, pct: pct))
        }
    }
    // A zero-width item cannot be clicked, so something always gets drawn. With
    // Claude closed that is a dash; with everything merely hidden, the badge.
    if pieces.isEmpty { pieces.append(profile == nil ? dashPiece() : hexagonPiece(profile)) }

    let row = group(pieces, gap: outerGap)
    let image = NSImage(size: NSSize(width: row.width, height: iconHeight), flipped: false) { _ in
        row.draw(0, iconHeight / 2)
        return true
    }
    image.cacheMode = .never
    return image
}

/// Turns one piece into a small image, for menu items.
private func image(of piece: Piece, height: CGFloat = 16) -> NSImage {
    let img = NSImage(size: NSSize(width: max(piece.width, 1), height: height), flipped: false) { _ in
        piece.draw(0, height / 2)
        return true
    }
    img.cacheMode = .never
    return img
}

/// A menu that offers seven shapes and describes them in words is a menu you
/// have to try one by one. These render the real thing, at a sample level, with
/// the thresholds and colour scheme currently in force.
func shapePreview(_ shape: WindowShape, label: String, pct: Int = 62) -> NSImage {
    image(of: windowPiece(shape, label: label, pct: pct))
}

func badgePreview(_ shape: ProfileShape, profile: String?) -> NSImage? {
    guard let piece = profilePiece(shape, profile: profile ?? "profile") else { return nil }
    return image(of: piece)
}

/// What the bar is saying, in words. Serves VoiceOver, and is the only way to
/// inspect the item from outside now that there is no title.
func summary(profile: String?, usage: Usage?) -> String {
    guard let profile else { return "Claude closed" }
    // With the badge hidden the profile is not on the bar, so it must not be in
    // the label either — a hexagon carries the profile by colour alone, which is
    // exactly when naming it earns its place.
    var parts = Preferences.profileShape == .hidden ? [] : [profile]
    if let usage {
        for (window, pct) in [(Window.fiveHour, usage.fiveHour), (Window.weekly, usage.weekly)] {
            guard let pct, Preferences.shows(window) else { continue }
            parts.append("\(window.label) \(pct)%")
        }
    }
    return parts.isEmpty ? "Claude running, no recent usage sample"
                         : parts.joined(separator: ", ")
}
