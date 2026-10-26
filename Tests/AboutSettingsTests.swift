import AppKit

@main
enum AboutSettingsTests {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited) // Synthetic settings only; no desktop activation.
        let suite = "local.openmindflow.about-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        assert(L10n.setLanguage("en", defaults: defaults))
        let delegate = AppDelegate(defaults: defaults)
        delegate.installMenu()
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              let about = appMenu.item(withTitle: "About OpenMindFlow"),
              let settings = appMenu.item(withTitle: "Settings…") else {
            fputs("OpenMindFlow menu must expose a native About entry beside Settings\n", stderr)
            exit(1)
        }
        assert(NSApp.sendAction(settings.action!, to: settings.target, from: settings))
        guard let panel = NSApp.windows.first(where: { $0.title == "Settings" }),
              let tabs = panel.contentView?.subviews.compactMap({ $0 as? NSSegmentedControl }).first,
              tabs.segmentCount == 3 && tabs.label(forSegment: 2) == "About" else {
            fputs("Settings must contain General, Keyboard Shortcuts, and About\n", stderr)
            exit(1)
        }
        tabs.selectedSegment = 2
        assert(NSApp.sendAction(tabs.action!, to: tabs.target, from: tabs))
        let views = panel.contentView!.subviews
        guard let credits = views.first(where: { $0.identifier?.rawValue == "about-credits" }) as? NSTextField,
              let statement = views.first(where: { $0.identifier?.rawValue == "about-statement" }) as? NSTextField,
              let auto = views.first(where: { $0.identifier?.rawValue == "about-auto-updates" }) as? NSButton,
              let check = views.first(where: { $0.identifier?.rawValue == "about-check-now" }) as? NSButton else {
            fputs("About must present credits, independent-development notice and update controls\n", stderr)
            exit(1)
        }
        assert(!credits.isHidden && credits.stringValue == "NicoZhuang | KEEPCRAZY | YoSoAi")
        assert(!statement.isHidden && statement.stringValue.contains("independent") &&
               statement.stringValue.contains("MindNode") &&
               statement.stringValue.contains("IdeasOnCanvas") &&
               statement.stringValue.contains("not affiliated"),
               "About must state exact author attribution and no false format or affiliation claim")
        assert(!auto.isHidden && auto.state == .off && defaults.object(forKey: "checkUpdatesAutomatically") == nil,
               "Network checks must be off by default before user opt-in")
        assert(!check.isHidden && check.action != nil, "About must offer explicit Check for Updates")
        auto.state = .on
        assert(NSApp.sendAction(auto.action!, to: auto.target, from: auto) &&
               defaults.bool(forKey: "checkUpdatesAutomatically"), "Opt-in persists as a user choice")
        auto.state = .off
        assert(NSApp.sendAction(auto.action!, to: auto.target, from: auto) &&
               !defaults.bool(forKey: "checkUpdatesAutomatically"), "User can disable automatic checks")
        assert(NSApp.sendAction(about.action!, to: about.target, from: about) && tabs.selectedSegment == 2,
               "App menu About must navigate to the existing native settings window")
        let language = views.first(where: { $0.identifier?.rawValue == "general-language" }) as! NSPopUpButton
        language.select(language.itemArray.first { ($0.representedObject as? String) == "zh-Hans" }!)
        assert(NSApp.sendAction(language.action!, to: language.target, from: language))
        assert(L10n.choice(defaults: defaults) == "zh-Hans" &&
               tabs.label(forSegment: 2) == "关于" && statement.stringValue.contains("IdeasOnCanvas"),
               "Live Chinese language switching must relabel About without losing attribution")
        panel.orderOut(nil)
        print("About identity, opt-in control, menu routing and live localization passed (offscreen)")
    }
}
