// Where things live on disk, and how to talk to `ps`.

import Cocoa

/// The Electron profile Claude Desktop uses when launched with no
/// `--user-data-dir`. On a stock install this is the only profile there is.
let defaultProfilePath = NSHomeDirectory() + "/Library/Application Support/Claude"

/// What we call that profile in the UI, since it has no directory name of its own.
let defaultProfileName = "default"

/// Optional. A directory holding extra Electron profiles, one subdirectory each.
/// Only meaningful if you launch Claude with `--user-data-dir`. Unset, the bar
/// tracks the default profile alone — which is the stock setup.
var profilesDirectory: String? {
    guard let raw = UserDefaults.standard.string(forKey: "profilesDirectory"),
          !raw.isEmpty else { return nil }
    return (raw as NSString).expandingTildeInPath
}

/// Optional. Command used to switch profiles: the profile name is appended as
/// the last argument. Without it the menu reports the open profile but cannot
/// change it — there is no portable way to guess how someone launches Claude.
var switchCommand: [String]? {
    let parts = UserDefaults.standard.stringArray(forKey: "switchCommand") ?? []
    return parts.isEmpty ? nil : parts
}

/// Directory of a profile, named or default.
func profilePath(_ name: String) -> String {
    guard name != defaultProfileName, let dir = profilesDirectory else { return defaultProfilePath }
    return dir + "/" + name
}

/// Runs a command and returns stdout. No shell: nothing interpolates a path.
func run(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}
