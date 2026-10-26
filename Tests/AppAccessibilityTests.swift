import AppKit
import ApplicationServices

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "local.mindmap.native-editor")
assert(apps.count == 1, "Launch exactly one own MindMap app before running AX regression")
let app = AXUIElementCreateApplication(apps[0].processIdentifier)

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func findNode(_ element: AXUIElement, label: String = "Central idea") -> AXUIElement? {
    if attribute(element, kAXRoleAttribute) as? String == kAXButtonRole,
       attribute(element, kAXDescriptionAttribute) as? String == label { return element }
    for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []) {
        if let found = findNode(child, label: label) { return found }
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

if CommandLine.arguments.contains("--selection-refresh") {
    precondition(AXIsProcessTrusted(), "Grant Accessibility access to the terminal running this check")
    assert(AXUIElementPerformAction(node!, kAXPressAction as CFString) == .success)
    guard let field = attribute(app, kAXFocusedUIElementAttribute),
          attribute(field as! AXUIElement, kAXRoleAttribute) as? String == kAXTextFieldRole else {
        fatalError("Native editor must have focus before Tab")
    }
    apps[0].activate()
    for down in [true, false] {
        CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: down)?.post(tap: .cghidEventTap)
    }
    var child: AXUIElement?
    for _ in 0..<30 {
        child = findNode(app, label: "New idea")
        if child != nil { break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard let child else { fatalError("Tab must create a child AX node") }
    assert(attribute(child, kAXSelectedAttribute) as? Bool == true, "New child must be selected")
    assert(attribute(node!, kAXSelectedAttribute) as? Bool == false,
           "Retained old AX node must become unselected without re-fetching it")
    assert(AXUIElementPerformAction(node!, kAXPressAction as CFString) == .success)
    assert(attribute(node!, kAXSelectedAttribute) as? Bool == true, "Retained root must become selected again")
    assert(attribute(child, kAXSelectedAttribute) as? Bool == false, "Retained child must become unselected")
    print("own-app retained AX selection refresh passed")
}

if CommandLine.arguments.contains("--close-flow") {
    func windows() -> [AXUIElement] { attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
    func title(_ element: AXUIElement) -> String { attribute(element, kAXTitleAttribute) as? String ?? "" }
    func pressButton(_ window: AXUIElement, _ name: String) -> Bool {
        for child in (attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? []) where title(child) == name {
            return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
        }
        return false
    }
    func mapWindow() -> AXUIElement? { windows().first { title($0).contains("OpenMindFlow") } }
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
