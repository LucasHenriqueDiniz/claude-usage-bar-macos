// Which Claude profile is open. Claude Desktop's own UI cannot be extended —
// its `app.asar` hash is pinned in Info.plist and the bundle is sealed — so the
// only way to know is to read the running process's `--user-data-dir`.

import Foundation

/// Name of the profile whose Claude is open right now, or nil if none is.
/// A named profile wins over the default one when both happen to be running.
func activeProfile() -> String? {
    var sawDefault = false
    for line in run("/bin/ps", ["-Ao", "command="]).split(separator: "\n") {
        let s = String(line)
        guard s.contains("Claude.app/Contents/MacOS/Claude") else { continue }
        guard let r = s.range(of: "--user-data-dir=") else {
            sawDefault = true          // no flag: the default profile
            continue
        }
        let path = String(s[r.upperBound...]).split(separator: " ").first.map(String.init) ?? ""
        guard let dir = profilesDirectory, path.hasPrefix(dir + "/") else {
            sawDefault = true
            continue
        }
        let name = (path as NSString).lastPathComponent
        if !name.isEmpty { return name }
    }
    return sawDefault ? defaultProfileName : nil
}

/// Profiles we could switch to. Empty unless a `profilesDirectory` is configured
/// — with a stock install there is nothing to switch between.
func availableProfiles() -> [String] {
    guard let dir = profilesDirectory, switchCommand != nil else { return [] }
    let items = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    var names = items.filter { !$0.hasPrefix(".") }.sorted()
    if FileManager.default.fileExists(atPath: defaultProfilePath) { names.append(defaultProfileName) }
    return names
}
