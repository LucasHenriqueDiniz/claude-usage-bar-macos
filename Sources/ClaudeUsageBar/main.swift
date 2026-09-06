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

        item.isVisible = !(profile == nil && Preferences.closedBehavior == .hidden)
        if let button = item.button {
            button.image = barIcon(profile: profile, usage: usage)
            button.imagePosition = .imageOnly   // the text is drawn too
            button.setAccessibilityLabel(summary(profile: profile, usage: usage))
        }
        item.menu = buildMenu(active: profile, usage: usage)
    }

    // MARK: - Menu

    private func buildMenu(active: String?, usage: Usage?) -> NSMenu {
        let menu = NSMenu()

        if active == nil {
            menu.addItem(disabled("Claude is not running"))
        } else {
            for line in usage?.details() ?? ["Usage: no recent sample from the app"] {
                menu.addItem(disabled(line))
            }
        }
        menu.addItem(.separator())

        for window in Window.allCases {
            let mi = NSMenuItem(title: window.menuTitle, action: nil, keyEquivalent: "")
            mi.submenu = windowMenu(window)
            menu.addItem(mi)
        }

        let appearance = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        appearance.submenu = appearanceMenu(active: active)
        menu.addItem(appearance)

        // Profiles are a niche of a niche: without a configured launcher there is
        // exactly one profile, and a menu about which one is open would always
        // give the same answer.
        let profiles = availableProfiles()
        if !profiles.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled(active.map { "Open profile: \($0)" } ?? "No profile open"))
            for profile in profiles {
                let mi = NSMenuItem(title: "Switch to \(profile)",
                                    action: #selector(switchTo(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = profile
                mi.state = (profile == active) ? .on : .off
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
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
            mi.image = shapePreview(shape, label: window.label)
            // With the window hidden the shape changes nothing on screen;
            // leaving it clickable would only produce a click with no effect.
            mi.isEnabled = Preferences.shows(window)
            sub.addItem(mi)
        }
        return sub
    }

    private func appearanceMenu(active: String?) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        for scheme in ColorScheme.allCases {
            let mi = NSMenuItem(title: scheme.label,
                                action: #selector(chooseColorScheme(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = scheme.rawValue
            mi.state = (scheme == Preferences.colorScheme) ? .on : .off
            sub.addItem(mi)
        }
        sub.addItem(.separator())

        let thresholds = NSMenuItem(title: "Colour steps", action: nil, keyEquivalent: "")
        thresholds.submenu = thresholdMenu()
        sub.addItem(thresholds)

        let closed = NSMenuItem(title: "When Claude is closed", action: nil, keyEquivalent: "")
        closed.submenu = closedMenu()
        sub.addItem(closed)

        // Only worth a submenu when there is more than one profile to tell apart.
        if !availableProfiles().isEmpty {
            let badge = NSMenuItem(title: "Profile badge", action: nil, keyEquivalent: "")
            badge.submenu = badgeMenu(active: active)
            sub.addItem(badge)
        }
        return sub
    }

    private func thresholdMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        for preset in ThresholdPreset.allCases {
            let mi = NSMenuItem(title: preset.label,
                                action: #selector(chooseThresholdPreset(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = preset.rawValue
            mi.state = (preset == Preferences.thresholdPreset) ? .on : .off
            sub.addItem(mi)
        }
        return sub
    }

    private func closedMenu() -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        for behavior in ClosedBehavior.allCases {
            let mi = NSMenuItem(title: behavior.label,
                                action: #selector(chooseClosedBehavior(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = behavior.rawValue
            mi.state = (behavior == Preferences.closedBehavior) ? .on : .off
            sub.addItem(mi)
        }
        sub.addItem(.separator())
        // Hiding the item hides the menu that undoes it. Say so before the click,
        // not after.
        sub.addItem(disabled("Hidden returns when Claude opens"))
        return sub
    }

    private func badgeMenu(active: String?) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        for shape in ProfileShape.allCases {
            let mi = NSMenuItem(title: shape.label,
                                action: #selector(chooseProfileShape(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = shape.rawValue
            mi.state = (shape == Preferences.profileShape) ? .on : .off
            mi.image = badgePreview(shape, profile: active)
            sub.addItem(mi)
        }
        return sub
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    // MARK: - Actions

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

    @objc private func chooseColorScheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let scheme = ColorScheme(rawValue: raw) else { return }
        Preferences.colorScheme = scheme
        refresh(force: true)
    }

    @objc private func chooseThresholdPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = ThresholdPreset(rawValue: raw) else { return }
        Preferences.thresholdPreset = preset
        refresh(force: true)
    }

    @objc private func chooseClosedBehavior(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let behavior = ClosedBehavior(rawValue: raw) else { return }
        Preferences.closedBehavior = behavior
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
