// How much of the plan has been spent. The number comes from
// <profile>/plan-usage-history.json, which Claude Desktop itself writes about
// every 15 minutes.
//
// It does NOT come from Claude Code's status line: the app's Code tab never
// executes the `statusLine` command — only the terminal TUI does — so anything
// meant to be visible while using the app has to read this file instead.

import Foundation

/// A sample older than this never reaches the screen. A stale file means the
/// app has been closed, and a usage window may have reset since — showing the
/// last number would be showing a lie. Three missed samples.
private let freshness: TimeInterval = 45 * 60

/// One usage sample. `fiveHour` is the 5-hour window, `weekly` the 7-day one,
/// both percentages. The file records no reset time, only the percentage.
struct Usage {
    let fiveHour: Int
    let weekly: Int?
    let measuredAt: Date

    /// Changes when something visible changes, so the menu is not rebuilt every
    /// tick.
    var signature: String { "\(fiveHour)/\(weekly ?? -1)" }

    func details() -> [String] {
        var lines = ["5h: \(fiveHour)%"]
        if let w = weekly { lines.append("7d: \(w)%") }
        lines.append("measured \(age()) · the app samples every 15 min")
        return lines
    }

    private func age() -> String {
        let seconds = Int(Date().timeIntervalSince(measuredAt))
        if seconds < 90 { return "just now" }
        return "\(seconds / 60) min ago"
    }
}

/// Reads the last sample from the app's history, re-parsing only when the file
/// changes: it accumulates 30 days of samples and the bar wakes every 3 seconds.
final class UsageReader {
    private var profile: String?
    private var modified: Date?
    private var cached: Usage?

    func read(_ profile: String) -> Usage? {
        let path = profilePath(profile) + "/plan-usage-history.json"
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let m = attrs?[.modificationDate] as? Date

        if profile != self.profile || m != modified {
            self.profile = profile
            modified = m
            cached = UsageReader.lastSample(path)
        }
        // Freshness is checked on read, not on parse: the file can sit still
        // while the sample ages, with no write to invalidate the cache.
        guard let u = cached, Date().timeIntervalSince(u.measuredAt) < freshness else { return nil }
        return u
    }

    private static func lastSample(_ path: String) -> Usage? {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let json = obj as? [String: Any],
              let samples = json["samples"] as? [[String: Any]],
              let last = samples.last,
              let ms = last["t"] as? Double,
              let u = last["u"] as? [String: Any],
              let fh = integer(u["fh"]) else { return nil }
        return Usage(fiveHour: fh, weekly: integer(u["sd"]),
                     measuredAt: Date(timeIntervalSince1970: ms / 1000))
    }

    /// The app writes integers today, but usage is a percentage: round rather
    /// than drop the sample should it ever arrive fractional.
    private static func integer(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber else { return nil }
        return Int(n.doubleValue.rounded())
    }
}
