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
        var pending: ((Data?, URLResponse?, Error?) -> Void)?
        delegate.releaseChecker = ReleaseChecker(fetch: { request, completion in
            assert(request.url == ReleaseChecker.endpoint)
            pending = completion
        })
        var opened: [URL] = []
        delegate.openReleaseURL = { opened.append($0) }
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
        func allViews(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + allViews($0) } }
        let views = allViews(panel.contentView!)
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
        assert(pending == nil, "Opening Settings must not contact GitHub")
        let channel = views.first(where: { $0.identifier?.rawValue == "about-channel" }) as! NSPopUpButton
        let status = views.first(where: { $0.identifier?.rawValue == "about-status" }) as! NSTextField
        let browser = views.first(where: { $0.identifier?.rawValue == "about-open-releases" }) as! NSButton
        assert(channel.selectedItem?.representedObject as? String == "stable")
        func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
        func deliver(_ code: Int, _ json: String = "[]") {
            let callback = pending!
            pending = nil
            callback(Data(json.utf8), HTTPURLResponse(url: ReleaseChecker.endpoint,
                statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil), nil)
            pump()
        }
        for restricted in [403, 404] {
            assert(NSApp.sendAction(check.action!, to: check.target, from: check))
            assert(status.stringValue == "Checking for updates…")
            deliver(restricted)
            assert(status.stringValue.contains("Sign in") && status.stringValue.contains("GitHub"),
                   "Private 403/404 must give truthful inline sign-in fallback: \(status.stringValue)")
            assert(opened.isEmpty && browser.isEnabled, "Never open browser without explicit click")
        }
        assert(NSApp.sendAction(browser.action!, to: browser.target, from: browser))
        assert(opened == [ReleaseChecker.releasesPage], "Fallback URL must be canonical GitHub Releases")
        assert(NSApp.sendAction(check.action!, to: check.target, from: check))
        deliver(200)
        assert(status.stringValue.contains("No published"), "Empty release list is not up-to-date")
        let stable = "{\"tag_name\":\"v999.0.0\",\"html_url\":\"\(ReleaseChecker.releasesPage.absoluteString)/tag/v999.0.0\",\"draft\":false,\"prerelease\":false}"
        let beta = "{\"tag_name\":\"v999.0.0-beta.1\",\"html_url\":\"\(ReleaseChecker.releasesPage.absoluteString)/tag/v999.0.0-beta.1\",\"draft\":false,\"prerelease\":true}"
        assert(NSApp.sendAction(check.action!, to: check.target, from: check))
        deliver(200, "[\(beta)]")
        assert(status.stringValue.contains("No published"), "Stable must ignore Beta release")
        channel.select(channel.itemArray.first { $0.representedObject as? String == "beta" })
        assert(NSApp.sendAction(channel.action!, to: channel.target, from: channel))
        assert(defaults.string(forKey: "updateChannel") == "beta")
        assert(NSApp.sendAction(check.action!, to: check.target, from: check))
        deliver(200, "[\(beta)]")
        assert(status.stringValue.contains("999.0.0-beta.1"))
        assert(opened == [ReleaseChecker.releasesPage], "A newer result must still require browser click")
        assert(NSApp.sendAction(browser.action!, to: browser.target, from: browser))
        assert(opened.last == URL(string: "\(ReleaseChecker.releasesPage.absoluteString)/tag/v999.0.0-beta.1")!,
               "View Release must open the checker-validated exact release URL")
        assert(NSApp.sendAction(check.action!, to: check.target, from: check))
        deliver(200, "[\(stable)]")
        assert(status.stringValue.contains("999.0.0"))
        assert(NSApp.sendAction(check.action!, to: check.target, from: check))
        deliver(200, "[{\"tag_name\":\"v0.0.0\",\"html_url\":\"\(ReleaseChecker.releasesPage.absoluteString)/tag/v0.0.0\",\"draft\":false,\"prerelease\":false}]")
        assert(status.stringValue.contains("up to date"), "Explicit up-to-date result stays inline")
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
        // Two same-channel requests can complete in reverse order; only the latest wins.
        var callbacks: [(Data?, URLResponse?, Error?) -> Void] = []
        delegate.releaseChecker = ReleaseChecker(fetch: { _, completion in callbacks.append(completion) })
        let oldCheck = callbacks.count
        assert(NSApp.sendAction(check.action!, to: check.target, from: check))
        assert(NSApp.sendAction(check.action!, to: check.target, from: check))
        assert(callbacks.count == oldCheck + 2)
        func finish(_ callback: (Data?, URLResponse?, Error?) -> Void, _ json: String) {
            callback(Data(json.utf8), HTTPURLResponse(url: ReleaseChecker.endpoint,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil), nil)
            pump()
        }
        finish(callbacks[1], "[\(stable)]")
        let newest = status.stringValue
        finish(callbacks[0], "[]")
        assert(status.stringValue == newest && newest.contains("999.0.0"),
               "Older same-channel callback must not overwrite newest check")
        // Leaving and returning to a channel must also invalidate its old request.
        callbacks.removeAll()
        assert(NSApp.sendAction(check.action!, to: check.target, from: check))
        channel.select(channel.itemArray.first { $0.representedObject as? String == "stable" })
        assert(NSApp.sendAction(channel.action!, to: channel.target, from: channel))
        channel.select(channel.itemArray.first { $0.representedObject as? String == "beta" })
        assert(NSApp.sendAction(channel.action!, to: channel.target, from: channel))
        assert(NSApp.sendAction(check.action!, to: check.target, from: check))
        finish(callbacks[1], "[\(beta)]")
        let returned = status.stringValue
        finish(callbacks[0], "[]")
        assert(status.stringValue == returned && returned.contains("999.0.0-beta.1"),
               "Away/back channel selection must invalidate the original request")
        panel.orderOut(nil)

        // Exercise actual synthetic startup semantics, not an explicit Settings/manual check.
        let startupSuite = "local.openmindflow.startup-update.\(UUID())"
        let startupDefaults = UserDefaults(suiteName: startupSuite)!
        defer { startupDefaults.removePersistentDomain(forName: startupSuite) }
        assert(L10n.setLanguage("en", defaults: startupDefaults))
        let startup = AppDelegate(defaults: startupDefaults)
        var automatic: ((Data?, URLResponse?, Error?) -> Void)?
        startup.releaseChecker = ReleaseChecker(fetch: { _, completion in automatic = completion })
        NSApp.dockTile.badgeLabel = nil
        startup.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApp))
        assert(automatic == nil && NSApp.dockTile.badgeLabel == nil,
               "Default-off startup must neither request nor display an update badge")
        startupDefaults.set(true, forKey: "checkUpdatesAutomatically")
        // A second isolated delegate simulates the next opt-in launch.
        let opted = AppDelegate(defaults: startupDefaults)
        opted.releaseChecker = ReleaseChecker(fetch: { _, completion in automatic = completion })
        opted.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApp))
        assert(automatic != nil && NSApp.dockTile.badgeLabel == nil)
        finish(automatic!, "[\(stable)]")
        assert(NSApp.dockTile.badgeLabel != nil, "Opt-in startup update needs a non-modal visible signal")
        let startupSettings = NSApp.mainMenu!.items[0].submenu!.item(withTitle: "Settings…")!
        assert(NSApp.sendAction(startupSettings.action!, to: startupSettings.target, from: startupSettings))
        let startupPanel = NSApp.windows.last { $0.title == "Settings" }!
        let startupTabs = startupPanel.contentView!.subviews.compactMap { $0 as? NSSegmentedControl }.first!
        startupTabs.selectedSegment = 2
        assert(NSApp.sendAction(startupTabs.action!, to: startupTabs.target, from: startupTabs))
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let cached = descendants(startupPanel.contentView!).first { $0.identifier?.rawValue == "about-status" } as! NSTextField
        assert(cached.stringValue.contains("999.0.0"), "Settings must display cached startup outcome without another request")
        let startupViews = descendants(startupPanel.contentView!)
        let startupCheck = startupViews.first { $0.identifier?.rawValue == "about-check-now" } as! NSButton
        assert(NSApp.sendAction(startupCheck.action!, to: startupCheck.target, from: startupCheck))
        finish(automatic!, "[{\"tag_name\":\"v0.0.0\",\"html_url\":\"\(ReleaseChecker.releasesPage.absoluteString)/tag/v0.0.0\",\"draft\":false,\"prerelease\":false}]")
        assert(NSApp.dockTile.badgeLabel == nil, "Definitive up-to-date manual check must clear stale automatic badge")
        opted.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApp))
        finish(automatic!, "[\(stable)]")
        assert(NSApp.dockTile.badgeLabel == "!", "New automatic result keeps badge until resolved")
        assert(NSApp.sendAction(startupCheck.action!, to: startupCheck.target, from: startupCheck))
        finish(automatic!, "[]")
        assert(NSApp.dockTile.badgeLabel == nil, "No published release must clear stale automatic badge")
        opted.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApp))
        finish(automatic!, "[\(stable)]")
        assert(NSApp.dockTile.badgeLabel == "!")
        assert(NSApp.sendAction(startupCheck.action!, to: startupCheck.target, from: startupCheck))
        let transient = automatic!
        automatic = nil
        transient(nil, nil, URLError(.notConnectedToInternet))
        pump()
        assert(NSApp.dockTile.badgeLabel == "!", "Transient network failure must not claim the update is gone")
        startupPanel.orderOut(nil)

        // Turning off automatic checks invalidates its in-flight result without cancelling manual requests.
        let raceSuite = "local.openmindflow.auto-race.\(UUID())"
        let raceDefaults = UserDefaults(suiteName: raceSuite)!
        defer { raceDefaults.removePersistentDomain(forName: raceSuite) }
        assert(L10n.setLanguage("en", defaults: raceDefaults))
        raceDefaults.set(true, forKey: "checkUpdatesAutomatically")
        let race = AppDelegate(defaults: raceDefaults)
        var racePending: ((Data?, URLResponse?, Error?) -> Void)?
        race.releaseChecker = ReleaseChecker(fetch: { _, completion in racePending = completion })
        NSApp.dockTile.badgeLabel = nil
        race.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApp))
        let staleAutomatic = racePending!
        let raceSettings = NSApp.mainMenu!.items[0].submenu!.item(withTitle: "Settings…")!
        assert(NSApp.sendAction(raceSettings.action!, to: raceSettings.target, from: raceSettings))
        let racePanel = NSApp.windows.last { $0.title == "Settings" }!
        let raceViews = descendants(racePanel.contentView!)
        let raceAuto = raceViews.first { $0.identifier?.rawValue == "about-auto-updates" } as! NSButton
        let raceCheck = raceViews.first { $0.identifier?.rawValue == "about-check-now" } as! NSButton
        raceAuto.state = .off
        assert(NSApp.sendAction(raceAuto.action!, to: raceAuto.target, from: raceAuto))
        finish(staleAutomatic, "[\(stable)]")
        assert(NSApp.dockTile.badgeLabel == nil, "Opted-out in-flight automatic result must not restore badge")
        assert(NSApp.sendAction(raceCheck.action!, to: raceCheck.target, from: raceCheck))
        let manualPending = racePending!
        raceAuto.state = .on
        assert(NSApp.sendAction(raceAuto.action!, to: raceAuto.target, from: raceAuto))
        raceAuto.state = .off
        assert(NSApp.sendAction(raceAuto.action!, to: raceAuto.target, from: raceAuto))
        finish(manualPending, "[\(stable)]")
        let raceStatus = raceViews.first { $0.identifier?.rawValue == "about-status" } as! NSTextField
        assert(raceStatus.stringValue.contains("999.0.0"), "Disabling automatic checks must not invalidate pending manual check")
        assert(NSApp.dockTile.badgeLabel == nil, "Manual newer result must not set an automatic Dock badge")
        racePanel.orderOut(nil)
        for owner in startup.windowSessions + opted.windowSessions + race.windowSessions { owner.window.orderOut(nil) }
        NSApp.dockTile.badgeLabel = nil
        print("About updates, request ordering, validated URLs, opt-in startup and localization passed (offscreen)")
    }
}
