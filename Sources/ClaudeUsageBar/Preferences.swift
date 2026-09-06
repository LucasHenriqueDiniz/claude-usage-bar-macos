// What the user picked, and where that is kept.
//
// Three independent parts on the bar: the badge saying which profile is open,
// the 5-hour window and the weekly window. Each has its own shape, and the
// windows also have an on/off.

import Foundation

/// How the "which profile is open" badge appears. Hidden by default: one
/// profile is the stock setup, and a badge that always says the same thing is
/// just pixels. It earns its place once `profilesDirectory` is configured.
enum ProfileShape: String, CaseIterable {
    case hexagon
    case dot
    case hexagonName
    case name
    case hidden

    var label: String {
        switch self {
        case .hexagon:     return "Hexagon"
        case .dot:         return "Dot"
        case .hexagonName: return "Hexagon + name"
        case .name:        return "Name only"
        case .hidden:      return "Nothing"
        }
    }
}

/// How a usage window appears. Graphic and text come combined in a single enum
/// so you pick a finished look, instead of crossing two lists in your head to
/// work out what will end up on the bar.
enum WindowShape: String, CaseIterable {
    case ringNumber
    case ring
    case barNumber
    case bar
    case number
    case percent
    case labelled

    var label: String {
        switch self {
        case .ringNumber: return "Ring + number"
        case .ring:       return "Ring only"
        case .barNumber:  return "Bar + number"
        case .bar:        return "Bar only"
        case .number:     return "Number only"
        case .percent:    return "Number with %"
        case .labelled:   return "Label + number"
        }
    }
}

/// Which of the two usage windows. The rawValue goes into the UserDefaults key.
enum Window: String, CaseIterable {
    case fiveHour
    case weekly

    var label: String { self == .fiveHour ? "5h" : "7d" }
    var menuTitle: String { self == .fiveHour ? "5-hour window" : "Weekly window (7d)" }

    /// The weekly one starts off: it moves slowly and is rarely what runs out
    /// first — whoever wants it can read it in the menu, without spending bar.
    var shownByDefault: Bool { self == .fiveHour }

    /// Turn the weekly one on and it comes in compact: a second number on the
    /// bar doubles the digit count, and the ring already carries the reading.
    var defaultShape: WindowShape { self == .fiveHour ? .ringNumber : .ring }
}

/// Preferences in UserDefaults, i.e. ~/Library/Preferences/<domain>.plist.
///
/// Shape and visibility get menu items. The colour thresholds do not: they are
/// fine tuning almost nobody touches, and a submenu of numbers would weigh more
/// than it is worth — they live in `defaults write`, documented in the README.
enum Preferences {
    static var profileShape: ProfileShape {
        get { ProfileShape(rawValue: string("profileShape")) ?? .hidden }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "profileShape") }
    }

    static func shows(_ w: Window) -> Bool {
        UserDefaults.standard.object(forKey: "show-\(w.rawValue)") as? Bool ?? w.shownByDefault
    }
    static func set(_ w: Window, shows: Bool) {
        UserDefaults.standard.set(shows, forKey: "show-\(w.rawValue)")
    }

    static func shape(_ w: Window) -> WindowShape {
        WindowShape(rawValue: string("shape-\(w.rawValue)")) ?? w.defaultShape
    }
    static func set(_ w: Window, shape: WindowShape) {
        UserDefaults.standard.set(shape.rawValue, forKey: "shape-\(w.rawValue)")
    }

    static var attentionThreshold: Int { integer("attentionThreshold", fallback: 60) }
    static var tightThreshold: Int     { integer("tightThreshold",     fallback: 80) }
    static var criticalThreshold: Int  { integer("criticalThreshold",  fallback: 95) }

    /// Changes when any visible preference changes, so the button is redrawn
    /// without needing one observer per key.
    static var signature: String {
        var parts = [profileShape.rawValue]
        for w in Window.allCases { parts.append("\(shows(w))\(shape(w).rawValue)") }
        parts.append("\(attentionThreshold)/\(tightThreshold)/\(criticalThreshold)")
        return parts.joined(separator: "|")
    }

    private static func string(_ key: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }
    private static func integer(_ key: String, fallback: Int) -> Int {
        guard let n = UserDefaults.standard.object(forKey: key) as? Int,
              (1...100).contains(n) else { return fallback }
        return n
    }
}
