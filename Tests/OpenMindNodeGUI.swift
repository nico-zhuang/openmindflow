import AppKit
import ApplicationServices

// Run with exactly one built MindMap app open and Accessibility permission for this process.
precondition(AXIsProcessTrusted(), "Grant Accessibility access to the terminal running this check")
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "local.mindmap.native-editor")
precondition(apps.count == 1, "Launch exactly one own MindMap app")
let app = AXUIElementCreateApplication(apps[0].processIdentifier)
func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
}
func find(_ element: AXUIElement, title: String) -> AXUIElement? {
    if value(element, kAXTitleAttribute) as? String == title { return element }
    for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let found = find(child, title: title) { return found }
    }
    return nil
}
guard let menuBar = value(app, kAXMenuBarAttribute),
      let file = find(menuBar as! AXUIElement, title: "File") else { fatalError("File menu missing") }
precondition(AXUIElementPerformAction(file, kAXPressAction as CFString) == .success, "Cannot open File menu")
guard let item = find(file, title: "Open MindNode (Read-only)…") else { fatalError("Import action missing") }
precondition(AXUIElementPerformAction(item, kAXPressAction as CFString) == .success, "Cannot invoke import")
var cancel: AXUIElement?
for _ in 0..<30 {
    let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    cancel = windows.lazy.compactMap { find($0, title: "Cancel") }.first
    if cancel != nil { break }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
guard let cancel else { fatalError("MindNode open panel missing") }
precondition(AXUIElementPerformAction(cancel, kAXPressAction as CFString) == .success, "Cannot cancel open panel")
print("MindNode File menu and native open panel passed; package selection not exercised by this check")
