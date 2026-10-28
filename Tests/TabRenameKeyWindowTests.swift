import AppKit
import Darwin
import Foundation

/// Run only through run-tab-rename-key-window.sh: a separately bundled, signed native process.
/// This is not a global AX/HID test and must never interact with another app's windows.
@main enum TabRenameKeyWindowTests {
    static let report = URL(fileURLWithPath: CommandLine.arguments[1])
    static func finish(_ message: String, success: Bool) -> Never {
        try? message.write(to: report, atomically: true, encoding: .utf8)
        Darwin.exit(success ? 0 : 1)
    }
    static func main() {
        let app = DocumentDragApplication.shared
        let defaults = UserDefaults(suiteName: "local.openmindflow.key-rename-test.\(UUID())")!
        let delegate = AppDelegate(defaults: defaults)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: app, queue: .main) { _ in
            guard let owner = delegate.windowSessions.first else { finish("FAIL missing synthetic window", success: false) }
            owner.window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            func testWhenKey(_ attempts: Int) {
                guard NSApp.isActive, owner.window.isKeyWindow else {
                    guard attempts < 40 else { finish("FAIL isolated window never became key active=\(NSApp.isActive) key=\(owner.window.isKeyWindow) visible=\(owner.window.isVisible) activation=\(NSApp.activationPolicy().rawValue)", success: false) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { testWhenKey(attempts + 1) }
                    return
                }
                let strip = owner.tabStrip
                guard let row = strip.subviews.first(where: { $0.subviews.count >= 2 && $0.subviews.first is NSButton }),
                      let button = row.subviews.first as? NSButton else { finish("FAIL missing title button", success: false) }
                let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                let click = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                    timestamp: 10, windowNumber: owner.window.windowNumber, context: nil,
                    eventNumber: 2, clickCount: 2, pressure: 1)!
                button.mouseDown(with: click)
                guard let field = row.subviews.compactMap({ $0 as? NSTextField }).first,
                      let editor = field.currentEditor(), owner.window.firstResponder === editor,
                      field.superview === row else {
                    finish("FAIL double-click destroyed editable field or keyboard focus", success: false)
                }
                guard editor.selectedRange.length == (editor.string as NSString).length else {
                    finish("FAIL existing tab title was not selected", success: false)
                }
                editor.insertText("KeyWindowRenamed")
                guard owner.window.makeFirstResponder(strip),
                      owner.active?.displayTabTitle(defaults: defaults) == "KeyWindowRenamed" else {
                    finish("FAIL typed rename did not commit on blur", success: false)
                }
                finish("PASS real key-window double-click kept field editor and committed typed title", success: true)
            }
            testWhenKey(0)
        }
        app.run()
    }
}
