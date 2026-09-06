// Claude plan usage in the macOS menu bar.
//
// Claude Desktop's own UI cannot be extended — its `app.asar` hash is pinned in
// Info.plist and the bundle is sealed — so this lives OUTSIDE the app, reading
// the usage history file the app writes anyway.
//
// Layout: Profile.swift finds the open profile, Usage.swift reads the
// percentage, Preferences.swift holds the choices, Rendering.swift turns that
// into an image, and this file owns the NSStatusItem and the menu.

import Cocoa

final class Bar: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var timer: Timer?
    private var lastKey: String?
    private let reader = UsageReader()

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refresh(force: false)
        }
    }

    private func refresh(force: Bool) {
        let profile = activeProfile()
        let usage = profile.flatMap { reader.read($0) }
        // Only redraw on change, so the menu does not flicker every 3 s.
        let key = [profile ?? "-", usage?.signature ?? "-", Preferences.signature].joined(separator: "|")
        if !force, lastKey == key { return }
        lastKey = key

        if let button = item.button {
            button.image = barIcon(profile: profile, usage: usage)
            button.imagePosition = .imageOnly   // the text is drawn too
            button.setAccessibilityLabel(summary(profile: profile, usage: usage))
        }
        item.menu = buildMenu(active: profile, usage: usage)
    }

    private func buildMenu(active: String?, usage: Usage?) -> NSMenu {
        let menu = NSMenu()
        let header = NSMenuItem(
            title: active.map { "Open profile: \($0)" } ?? "Claude is not running",
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if active != nil {
            for line in usage?.details() ?? ["Usage: no recent sample from the app"] {
                let mi = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                mi.isEnabled = false
                menu.addItem(mi)
            }
        }

        // Only when a launcher is configured; there is no portable way to guess
        // how someone starts Claude with a given profile.
        let profiles = availableProfiles()
        if !profiles.isEmpty {
            menu.addItem(.separator())
            for profile in profiles {
                let mi = NSMenuItem(title: "Open \(profile)",
                                    action: #selector(switchTo(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = profile
                mi.state = (profile == active) ? .on : .off
                menu.addItem(mi)
            }
        }
        menu.addItem(.separator())

        let badge = NSMenuItem(title: "Profile badge", action: nil, keyEquivalent: "")
        badge.submenu = profileMenu()
        menu.addItem(badge)

        for window in Window.allCases {
            let mi = NSMenuItem(title: window.menuTitle, action: nil, keyEquivalent: "")
            mi.submenu = windowMenu(window)
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func profileMenu() -> NSMenu {
        let sub = NSMenu()
        let current = Preferences.profileShape
        for shape in ProfileShape.allCases {
            let mi = NSMenuItem(title: shape.label,
                                action: #selector(chooseProfileShape(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = shape.rawValue
            mi.state = (shape == current) ? .on : .off
            sub.addItem(mi)
        }
        return sub
    }

    /// Each window carries its own on/off at the top of its submenu: it is the
    /// same decision ("how the weekly one appears"), it does not deserve two
    /// places.
    private func windowMenu(_ window: Window) -> NSMenu {
        let sub = NSMenu()
        // Without this NSMenu re-enables everything on its own (autoenables only
        // checks whether the target responds to the action) and the isEnabled
        // below counts for nothing.
        sub.autoenablesItems = false
        let show = NSMenuItem(title: "Show on the bar",
                              action: #selector(toggleWindow(_:)), keyEquivalent: "")
        show.target = self
        show.representedObject = window.rawValue
        show.state = Preferences.shows(window) ? .on : .off
        sub.addItem(show)
        sub.addItem(.separator())

        let current = Preferences.shape(window)
        for shape in WindowShape.allCases {
            let mi = NSMenuItem(title: shape.label,
                                action: #selector(chooseWindowShape(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = ["window": window.rawValue, "shape": shape.rawValue]
            mi.state = (shape == current) ? .on : .off
            // With the window hidden the shape changes nothing on screen;
            // leaving it clickable would only produce a click with no effect.
            mi.isEnabled = Preferences.shows(window)
            sub.addItem(mi)
        }
        return sub
    }

    @objc private func chooseProfileShape(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let shape = ProfileShape(rawValue: raw) else { return }
        Preferences.profileShape = shape
        refresh(force: true)
    }

    @objc private func toggleWindow(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let window = Window(rawValue: raw) else { return }
        Preferences.set(window, shows: !Preferences.shows(window))
        refresh(force: true)
    }

    @objc private func chooseWindowShape(_ sender: NSMenuItem) {
        guard let d = sender.representedObject as? [String: String],
              let window = Window(rawValue: d["window"] ?? ""),
              let shape = WindowShape(rawValue: d["shape"] ?? "") else { return }
        Preferences.set(window, shape: shape)
        refresh(force: true)
    }

    @objc private func switchTo(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? String,
              let command = switchCommand, let tool = command.first else { return }
        let args = Array(command.dropFirst()) + [profile]
        DispatchQueue.global(qos: .userInitiated).async {
            _ = run(tool, args)
            DispatchQueue.main.async { self.refresh(force: true) }
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}

let app = NSApplication.shared
let bar = Bar()
app.delegate = bar
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
