import AppKit
import ApplicationServices

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "local.mindmap.native-editor")
assert(apps.count == 1, "Launch exactly one own MindMap app before running AX regression")
let app = AXUIElementCreateApplication(apps[0].processIdentifier)

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func findNode(_ element: AXUIElement) -> AXUIElement? {
    if attribute(element, kAXRoleAttribute) as? String == kAXButtonRole,
       attribute(element, kAXDescriptionAttribute) as? String == "Central idea" { return element }
    for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []) {
        if let found = findNode(child) { return found }
    }
    return nil
}

let node = findNode(app)
assert(node != nil, "Own app must expose Central idea as a labeled AX button")
assert(attribute(node!, kAXSelectedAttribute) as? Bool == true, "Selected node must expose AXSelected")
var actions: CFArray?
assert(AXUIElementCopyActionNames(node!, &actions) == .success &&
       (actions as? [String])?.contains(kAXPressAction) == true,
       "Node must support AXPress to select and edit")
print("own-app AX node, selected state and Press action passed")

if CommandLine.arguments.contains("--close-flow") {
    func windows() -> [AXUIElement] { attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
    func title(_ element: AXUIElement) -> String { attribute(element, kAXTitleAttribute) as? String ?? "" }
    func pressButton(_ window: AXUIElement, _ name: String) -> Bool {
        for child in (attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? []) where title(child) == name {
            return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
        }
        return false
    }
    func mapWindow() -> AXUIElement? { windows().first { title($0).contains("MindMap") } }
    func alertWindow() -> AXUIElement? {
        windows().first { window in
            (attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? []).contains { title($0) == "Discard Changes" }
        }
    }
    func requestClose() {
        guard let window = mapWindow(), let close = attribute(window, kAXCloseButtonAttribute) else {
            fatalError("Own app map window close button missing")
        }
        // A modal NSAlert can make AXPress return cannotComplete; the visible alert is the assertion.
        _ = AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString)
        assert(alertWindow() != nil, "Unsaved close must offer Save, Cancel and Discard")
    }

    assert(AXUIElementPerformAction(node!, kAXPressAction as CFString) == .success)
    guard let field = attribute(app, kAXFocusedUIElementAttribute) else { fatalError("Native editor not focused") }
    assert(attribute(field as! AXUIElement, kAXRoleAttribute) as? String == kAXTextFieldRole)
    assert(AXUIElementSetAttributeValue(field as! AXUIElement, kAXValueAttribute as CFString,
                                      "Disposable close test" as CFTypeRef) == .success)
    requestClose()
    assert(pressButton(alertWindow()!, "Cancel"), "Cancel button must work")
    assert(mapWindow() != nil, "Cancel must preserve the edited map")
    requestClose()
    assert(pressButton(alertWindow()!, "Discard Changes"), "Discard button must work")
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    assert(NSRunningApplication.runningApplications(withBundleIdentifier: "local.mindmap.native-editor").isEmpty,
           "Confirmed close must terminate the single-window app")
    print("own-app close Save/Cancel/Discard prompt, cancel retention and confirmed exit passed")
}
