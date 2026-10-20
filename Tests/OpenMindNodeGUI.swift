import AppKit
import ApplicationServices
import CryptoKit

// Run with exactly one built own app and Accessibility permission for this process.
precondition(AXIsProcessTrusted(), "Grant Accessibility access to the terminal running this check")
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "local.mindmap.native-editor")
precondition(apps.count == 1, "Launch exactly one own MindMap app")
let running = apps[0]
let app = AXUIElementCreateApplication(running.processIdentifier)
let fm = FileManager.default
let scratch = fm.temporaryDirectory.appendingPathComponent("mindmap-gui-\(UUID().uuidString)", isDirectory: true)
try fm.createDirectory(at: scratch, withIntermediateDirectories: false)
let marker = scratch.appendingPathComponent(".test-owner")
let owner = UUID().uuidString
try owner.write(to: marker, atomically: true, encoding: .utf8)
defer {
    // Never remove a different directory if the temporary path is replaced during the check.
    if scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL,
       scratch.deletingLastPathComponent() == fm.temporaryDirectory.standardizedFileURL,
       (try? String(contentsOf: marker, encoding: .utf8)) == owner {
        try? fm.removeItem(at: scratch)
    }
}
let package = scratch.appendingPathComponent("fixture.mindnode", isDirectory: true)
try fm.createDirectory(at: package, withIntermediateDirectories: false)
let title = "Synthetic GUI root"
let root: [String: Any] = ["nodeID": UUID().uuidString, "title": ["text": "<p>\(title)</p>"], "subnodes": [], "hasFoldedSubnodes": false]
let plist: [String: Any] = ["version": 9, "canvas": ["mindMaps": [["mainNode": root]]]]
try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    .write(to: package.appendingPathComponent("contents.xml"))
func hashes(_ url: URL) throws -> [String: String] {
    let files = try fm.subpathsOfDirectory(atPath: url.path).sorted().filter {
        var isDirectory: ObjCBool = false
        return fm.fileExists(atPath: url.appendingPathComponent($0).path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
    return try Dictionary(uniqueKeysWithValues: files.map { path in
        let bytes = try Data(contentsOf: url.appendingPathComponent(path))
        return (path, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
    })
}
let before = try hashes(package)
precondition(!before.isEmpty)
let previous = scratch.appendingPathComponent("previous.mindmap.json")
let oldTitle = "Synthetic previous JSON"
let oldRoot: [String: Any] = ["id": UUID().uuidString, "title": oldTitle, "children": [], "folded": false]
try JSONSerialization.data(withJSONObject: [oldRoot]).write(to: previous)
let malformed = scratch.appendingPathComponent("malformed.mindnode", isDirectory: true)
try fm.createDirectory(at: malformed, withIntermediateDirectories: false)
try Data([0x01, 0x02]).write(to: malformed.appendingPathComponent("contents.xml"))
func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
}
func titleOf(_ element: AXUIElement) -> String { value(element, kAXTitleAttribute) as? String ?? "" }
func find(_ element: AXUIElement, title: String) -> AXUIElement? {
    if titleOf(element) == title || value(element, kAXValueAttribute) as? String == title ||
       value(element, kAXDescriptionAttribute) as? String == title { return element }
    for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let found = find(child, title: title) { return found }
    }
    return nil
}
func findRole(_ element: AXUIElement, _ role: String) -> AXUIElement? {
    if value(element, kAXRoleAttribute) as? String == role { return element }
    for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let found = findRole(child, role) { return found }
    }
    return nil
}
func listingItem(_ filename: String) -> AXUIElement? {
    guard let list = findRole(panel(), kAXListRole) else { return nil }
    return find(list, title: filename)
}
func windows() -> [AXUIElement] { value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
func wait(_ description: String, _ check: () -> AXUIElement?) -> AXUIElement {
    for _ in 0..<60 {
        if let item = check() { return item }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    fatalError("Timed out: \(description)")
}
func press(_ element: AXUIElement, _ description: String) {
    precondition(AXUIElementPerformAction(element, kAXPressAction as CFString) == .success, "Cannot press \(description)")
}
func key(_ code: CGKeyCode, modifiers: CGEventFlags = []) {
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { fatalError("No keyboard event") }
        event.flags = modifiers
        event.post(tap: .cghidEventTap)
    }
}
func menu(_ name: String) {
    let bar = wait("menu bar") { value(app, kAXMenuBarAttribute).map { $0 as! AXUIElement } }
    guard let file = find(bar, title: "File") else { fatalError("File menu missing") }
    press(file, "File menu")
    press(wait(name) { find(file, title: name) }, name)
}
func panel() -> AXUIElement { wait("open panel") { windows().first { find($0, title: "Cancel") != nil && (find($0, title: "Open") != nil || find($0, title: "Choose") != nil) } } }
func navigate(to url: URL) {
    _ = panel()
    running.activate()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    func focusedField() -> AXUIElement? {
        guard let rawFocused = value(app, kAXFocusedUIElementAttribute) else { return nil }
        let focused = rawFocused as! AXUIElement
        return value(focused, kAXRoleAttribute) as? String == kAXTextFieldRole ? focused : nil
    }
    var field: AXUIElement?
    for _ in 0..<3 where field == nil {
        key(5, modifiers: [.maskCommand, .maskShift]) // Go to Folder
        for _ in 0..<10 {
            field = focusedField()
            if field != nil { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }
    guard let field else { fatalError("Timed out: Go to Folder field") }
    precondition(AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, url.path as CFTypeRef) == .success,
                 "Cannot enter fixture directory")
    key(36) // Confirm the user-selected path inside the native panel.
}

menu("Open…")
navigate(to: previous)
_ = AXUIElementPerformAction(wait("JSON Open") { find(panel(), title: "Open") }, kAXPressAction as CFString)
let previousNode = wait("previous JSON root") { windows().lazy.compactMap { find($0, title: oldTitle) }.first }
precondition(value(previousNode, kAXSelectedAttribute) as? Bool == true, "Previous JSON not opened")
menu("Open MindNode (Read-only)…")
navigate(to: malformed)
_ = AXUIElementPerformAction(wait("malformed Open") { find(panel(), title: "Open") }, kAXPressAction as CFString)
let failure = wait("invalid package alert") { windows().first { find($0, title: "Could not open MindNode") != nil } }
press(wait("invalid OK") { find(failure, title: "OK") }, "invalid OK")
precondition(value(previousNode, kAXSelectedAttribute) as? Bool == true,
             "Invalid import must retain prior map and selection")
menu("Open MindNode (Read-only)…")
navigate(to: scratch)
let unrelated = wait("unrelated JSON in picker") { listingItem(previous.lastPathComponent) }
precondition(value(unrelated, kAXEnabledAttribute) as? Bool == false, "Unrelated file must be disabled in import picker")
let listedPackage = wait("directory package in picker") { listingItem(package.lastPathComponent) }
precondition(value(listedPackage, kAXEnabledAttribute) as? Bool == true, "Directory package must be selectable")
navigate(to: package)
_ = AXUIElementPerformAction(wait("Open button") { find(panel(), title: "Open") }, kAXPressAction as CFString) // A modal alert can return cannotComplete after accepting the action.
let warning = wait("import loss warning") { windows().first { find($0, title: "MindNode imported read-only") != nil } }
precondition(find(warning, title: "Only text, tree structure and fold state were copied. Styles, notes and attachments are not round-tripped. Save creates a new .mindmap.json file; it never overwrites the MindNode package.") != nil,
             "Import loss warning missing")
press(wait("warning OK") { find(warning, title: "OK") }, "warning OK")
let node = wait("imported node") { windows().lazy.compactMap { find($0, title: title) }.first }
precondition(value(node, kAXSelectedAttribute) as? Bool == true, "Imported root must be selected")
let importedHashes = try hashes(package)
precondition(importedHashes == before, "Import modified source package")
menu("Save")
let savePanel = wait("fresh Save panel") { windows().first { find($0, title: "Save") != nil && find($0, title: "Cancel") != nil } }
precondition(find(savePanel, title: "Untitled.mindmap.json") != nil ||
             (value(value(app, kAXFocusedUIElementAttribute) as! AXUIElement, kAXValueAttribute) as? String)?.hasSuffix(".mindmap.json") == true,
             "Save must propose new .mindmap.json destination")
press(wait("Save Cancel") { find(savePanel, title: "Cancel") }, "Save Cancel")
let finalHashes = try hashes(package)
precondition(finalHashes == before, "Source package changed after Save cancellation")
print("own-app synthetic package import, prior JSON retention, picker file filtering, selected node, loss warning, fresh Save panel and SHA-256 passed")
