// Menu bar tones. The menu bar follows the wallpaper, not the system theme, so
// every colour here has to resolve at draw time.

import Cocoa

/// Menu bar text size.
let bodySize: CGFloat = 13

/// Hence the dynamicProvider, rather than picking one of two branches once.
func dynamic(light: UInt32, dark: UInt32) -> NSColor {
    NSColor(name: nil) { appearance in
        let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                       green:   CGFloat((hex >> 8) & 0xff) / 255,
                       blue:    CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

// On a light menu bar the system warning colours vanish — systemYellow over
// white is nearly invisible. Each step carries a dark tone for the light bar and
// a light tone for the dark one, reading the same on both.
let attentionColor = dynamic(light: 0x8A5200, dark: 0xFFC24B)
let tightColor     = dynamic(light: 0xA83200, dark: 0xFF8A4B)
let criticalColor  = dynamic(light: 0xB00020, dark: 0xFF6B6B)

/// Profile tints, picked so they stay legible on either bar. Assigned by a
/// stable hash of the name rather than hardcoded, so any profile name gets a
/// colour and nobody has to edit this file to add one.
private let profilePalette: [(light: UInt32, dark: UInt32)] = [
    (0x0A50C8, 0x6AB4FF),   // blue
    (0x0B6E36, 0x54DD92),   // green
    (0x7A3E9D, 0xC79BF0),   // purple
    (0xA8501E, 0xFFB073),   // amber
    (0x0F6E70, 0x5FD6D8),   // teal
    (0xA02060, 0xF58BC0),   // magenta
]

/// FNV-1a, so the colour of a profile does not drift between launches the way
/// Swift's per-process-seeded hashValue would.
private func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return h
}

func profileColor(_ profile: String?) -> NSColor {
    guard let profile else { return NSColor.tertiaryLabelColor }
    let tone = profilePalette[Int(stableHash(profile) % UInt64(profilePalette.count))]
    return dynamic(light: tone.light, dark: tone.dark)
}

/// Support grey for labels, and the track behind ring and bar.
/// secondaryLabelColor washes out on the translucent bar — an explicit alpha
/// over labelColor recedes without disappearing.
let supportColor = NSColor.labelColor.withAlphaComponent(0.75)
let trackColor   = NSColor.labelColor.withAlphaComponent(0.18)

/// Stays the ordinary text colour while there is room, and warms up as things
/// tighten.
func usageColor(_ pct: Int) -> NSColor {
    // Monochrome drops the tones but not the warning: usageWeight() still bolds
    // at the critical step, which is the signal that survives a colour-blind
    // reader anyway.
    if Preferences.colorScheme == .monochrome { return NSColor.labelColor }
    if pct >= Preferences.criticalThreshold  { return criticalColor }
    if pct >= Preferences.tightThreshold     { return tightColor }
    if pct >= Preferences.attentionThreshold { return attentionColor }
    return NSColor.labelColor
}

/// At the critical step the weight changes along with the tone: on a dark bar
/// orange and red sit too close for hue alone to carry the difference — and to
/// anyone who cannot tell the two apart, hue carries nothing at all.
func usageWeight(_ pct: Int) -> NSFont.Weight {
    pct >= Preferences.criticalThreshold ? .bold : .medium
}
