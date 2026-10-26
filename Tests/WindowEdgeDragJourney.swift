import AppKit
import ApplicationServices
import Darwin
import IOKit

// Standalone, disposable executable. Never targets an existing app or a saved document.
@main enum WindowEdgeDragJourney {
    private static var ownedApp: NSApplication?
    private static var ownedDefaultsSuite: String?

    private static func finish(_ message: String, _ code: Int32) -> Never {
        // exit() does not execute Swift defers: release our own GUI explicitly.
        if let app = ownedApp {
            for window in app.windows { window.orderOut(nil) } // Never close: delegate requests termination.
            app.hide(nil)
        }
        if let suite = ownedDefaultsSuite { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        print(message)
        fflush(stdout)
        exit(code)
    }

    private static func desktopGate() -> String? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            return "Finder is not frontmost"
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return "cannot read HID idle time" }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString,
                                                           kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else {
            return "HID idle time unavailable"
        }
        let seconds = value.doubleValue / 1_000_000_000
        guard seconds >= 180 else { return "HID idle only \(Int(seconds)) seconds (need 180)" }
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess(), CGPreflightListenEventAccess() else {
            return "Accessibility or Input Monitoring trust unavailable (no permission request made)"
        }
        return nil
    }

    private static func frontmostIsSelf() -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
    }

    // WindowServer's front-to-back list is checked before each posted event; another
    // app's window, sheet, Dock or menu at a proposed point is NEVER a drag target.
    private static func ownWindowIsTopmost(_ windowNumber: Int, at point: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]] else { return false }
        for item in list {
            guard let number = item[kCGWindowNumber as String] as? Int,
                  let bounds = item[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"] else { continue }
            // WindowServer bounds use top-left screen coordinates; AppKit uses bottom-left.
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let rect = CGRect(x: x, y: top - y - height, width: width, height: height)
            if rect.contains(point) { return number == windowNumber }
        }
        return false
    }

    private static func post(_ kind: CGEventType, at point: CGPoint, screenTop: CGFloat) -> Bool {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: kind,
                                  mouseCursorPosition: CGPoint(x: point.x, y: screenTop - point.y),
                                  mouseButton: .left) else { return false }
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.12)
        return true
    }

    static func main() {
        // Also used by the runner as its GUI-free preflight safety check.
        // In normal mode repeat BEFORE NSApplication.shared, AppDelegate.init and launch.
        if let reason = desktopGate() { finish("SKIP 77: \(reason)", 77) }
        if CommandLine.arguments.contains("--preflight") { finish("PREFLIGHT safe (no GUI)", 0) }
        let app = NSApplication.shared
        ownedApp = app
        if let reason = desktopGate() { finish("SKIP 77: \(reason)", 77) }
        app.setActivationPolicy(.regular)
        let suite = "local.mindmap.edge-journey.\(UUID())"
        ownedDefaultsSuite = suite
        guard let defaults = UserDefaults(suiteName: suite) else { finish("FAIL: synthetic defaults unavailable", 1) }
        defaults.setVolatileDomain(["language": "en"], forName: UserDefaults.argumentDomain)
        let delegate = AppDelegate(defaults: defaults)
        // Immediately before this call: AppDelegate creates/orders/activates its own window.
        if let reason = desktopGate() { finish("SKIP 77: \(reason)", 77) }
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification,
                                                              object: app))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        guard let window = app.windows.first(where: { $0.contentViewController is NSSplitViewController }),
              let split = window.contentViewController as? NSSplitViewController,
              split.splitViewItems.count > 1,
              let canvas = split.splitViewItems[1].viewController.view as? MapCanvas,
              let root = canvas.model.roots.first else {
            finish("FAIL: own AppDelegate workbench unavailable", 1)
        }
        guard frontmostIsSelf(), window.isVisible, window.isKeyWindow,
              window.styleMask.contains(.resizable), !window.isZoomed,
              window.minSize.width == 640, window.minSize.height == 400 else {
            finish("FAIL: synthetic window not frontmost/key/unmaximized/resizable", 1)
        }
        guard canvas.model.setNote("Synthetic resize sentinel", for: root.id) else {
            finish("FAIL: cannot seed synthetic note", 1)
        }
        let beforeNodes = canvas.model.roots // Full recursive value snapshot includes world locations and notes.
        let before = window.frame
        let start = CGPoint(x: before.maxX - 3, y: before.minY + 3)
        guard let screen = window.screen,
              screen.visibleFrame.contains(CGPoint(x: start.x + 22, y: start.y - 22)),
              ownWindowIsTopmost(window.windowNumber, at: start), frontmostIsSelf() else {
            finish("SKIP 77: edge not safely within own visible desktop window", 77)
        }
        // Native AppKit tracking can block the main run loop until mouse-up. Dispatch HID
        // events from a worker while the main thread delivers the real window events.
        let windowNumber = window.windowNumber
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        var result: String?
        DispatchQueue.global(qos: .userInitiated).async {
            var last = start
            var message = "pointer sequence finished"
            if !frontmostIsSelf() || !ownWindowIsTopmost(windowNumber, at: start) ||
                !post(.leftMouseDown, at: start, screenTop: screenTop) {
                message = "own-window target/focus lost before pointer-down"
            } else {
                for i in 1...10 {
                    let next = CGPoint(x: start.x + CGFloat(i * 2), y: start.y - CGFloat(i * 2))
                    // Never post a drag if another app is under this proposed point.
                    if !frontmostIsSelf() || !ownWindowIsTopmost(windowNumber, at: next) {
                        message = "own-window target/focus lost; cancelled before crossing"
                        break
                    }
                    if !post(.leftMouseDragged, at: next, screenTop: screenTop) {
                        message = "cannot make pointer-drag"
                        break
                    }
                    last = next
                }
                // Release only while this point still belongs to our own topmost window.
                if frontmostIsSelf() && ownWindowIsTopmost(windowNumber, at: last) {
                    if !post(.leftMouseUp, at: last, screenTop: screenTop) {
                        message = "cannot make pointer-up"
                    }
                } else {
                    message = "focus/own-window target lost before pointer-up"
                }
            }
            DispatchQueue.main.async { result = message }
        }
        while result == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        guard result == "pointer sequence finished" else { finish("FAIL: \(result ?? "no pointer result")", 1) }
        window.contentView?.layoutSubtreeIfNeeded()
        let after = window.frame
        guard after.width > before.width + 8, after.height > before.height + 8,
              canvas.model.roots == beforeNodes,
              canvas.model.roots.first?.note == "Synthetic resize sentinel" else {
            finish("FAIL: native edge resize or world-position/note preservation: before=\(before), after=\(after), nodesUnchanged=\(canvas.model.roots == beforeNodes)", 1)
        }
        finish("PASS: native own-window pointer edge drag grew both dimensions; world nodes and notes unchanged", 0)
    }
}
