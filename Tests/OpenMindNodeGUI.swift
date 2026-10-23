import AppKit
import ApplicationServices
import CryptoKit

if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.loginwindow" {
    fputs("GUI gate unavailable: locked desktop (loginwindow foreground)\n", stderr)
    exit(2)
}
// Only a marked disposable own app may receive test actions; never select an old preview implicitly.
guard AXIsProcessTrusted(),
      let rawPID = ProcessInfo.processInfo.environment["MINDMAP_GUI_PID"],
      let selectedPID = Int32(rawPID),
      let running = NSRunningApplication.runningApplications(withBundleIdentifier: "local.mindmap.native-editor")
          .first(where: { $0.processIdentifier == selectedPID }),
      let stage = running.bundleURL?.deletingLastPathComponent(),
      stage.lastPathComponent.hasPrefix("mindmap-gui-run-"),
      (try? String(contentsOf: stage.appendingPathComponent(".owner"), encoding: .utf8)) == "mindmap-owned-gui-fixture\n" else {
    fputs("GUI gate unavailable: require Accessibility and MINDMAP_GUI_PID for a marked disposable MindMap app\n", stderr)
    exit(2)
}
if NSWorkspace.shared.frontmostApplication?.processIdentifier != running.processIdentifier {
    guard running.activate() else {
        fputs("GUI gate unavailable: cannot activate selected MindMap process\n", stderr)
        exit(2)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
}
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier else {
    fputs("GUI gate unavailable: selected MindMap process is not frontmost\n", stderr)
    exit(2)
}
let app = AXUIElementCreateApplication(running.processIdentifier)
let fm = FileManager.default
let base = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
let prestarted = ProcessInfo.processInfo.environment["MINDMAP_GUI_FIXTURE_DIR"].map { URL(fileURLWithPath: $0).standardizedFileURL }
let scratch = prestarted ?? base.appendingPathComponent("mindmap-gui-\(UUID().uuidString)", isDirectory: true)
if prestarted == nil {
    try fm.createDirectory(at: scratch, withIntermediateDirectories: false,
                           attributes: [.posixPermissions: 0o700])
}
let scratchAttributes = try fm.attributesOfItem(atPath: scratch.path)
let scratchInode = scratchAttributes[.systemFileNumber] as? NSNumber
guard scratchInode != nil, scratch.deletingLastPathComponent() == base,
      (prestarted == nil || (scratch.lastPathComponent.hasPrefix("mindmap-native-panel-") &&
       (try? String(contentsOf: scratch.appendingPathComponent(".owner"), encoding: .utf8)) == "mindmap-owned-native-panel\n")),
      scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL,
      scratchAttributes[.ownerAccountID] as? NSNumber == NSNumber(value: getuid()),
      (scratchAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
    fputs("GUI gate unavailable: synthetic fixture is not a canonical owned 0700 directory\n", stderr)
    exit(2)
}
let marker = scratch.appendingPathComponent(".test-owner")
let owner = UUID().uuidString
if prestarted == nil { try owner.write(to: marker, atomically: true, encoding: .utf8) }
func cleanupFixture() {
    // Externally owned fixtures are never removed by this AX runner.
    guard prestarted == nil else { return }
    let current = try? fm.attributesOfItem(atPath: scratch.path)
    if scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL,
       scratch.deletingLastPathComponent() == base,
       current?[.systemFileNumber] as? NSNumber == scratchInode,
       current?[.ownerAccountID] as? NSNumber == NSNumber(value: getuid()),
       (current?[.posixPermissions] as? NSNumber)?.intValue == 0o700,
       (try? String(contentsOf: marker, encoding: .utf8)) == owner {
        try? fm.removeItem(at: scratch)
    }
}
defer { cleanupFixture() }
func fail(_ reason: String) -> Never {
    cleanupFixture() // fatalError/precondition would skip defer.
    fputs("GUI gate failed: \(reason)\n", stderr)
    exit(1)
}
func ensure(_ condition: @autoclosure () -> Bool, _ description: String = "GUI check failed") {
    if !condition() { fail(description) }
}
let package = scratch.appendingPathComponent("fixture.mindnode", isDirectory: true)
if prestarted == nil { try fm.createDirectory(at: package, withIntermediateDirectories: false) }
let title = "Synthetic GUI root"
let root: [String: Any] = ["nodeID": UUID().uuidString, "title": ["text": "<p>\(title)</p>"], "subnodes": [], "hasFoldedSubnodes": false]
let plist: [String: Any] = ["version": 9, "canvas": ["mindMaps": [["mainNode": root]]]]
if prestarted == nil {
    try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        .write(to: package.appendingPathComponent("contents.xml"))
}
let directTitle = "Synthetic direct v9 root"
let directRoot: [String: Any] = ["nodeID": UUID().uuidString, "title": ["text": "<p>\(directTitle)</p>"],
                                 "subnodes": [], "hasFoldedSubnodes": false]
let directPlist: [String: Any] = ["version": 9, "canvas": ["mindMaps": [["mainNode": directRoot]]]]
let single = scratch.appendingPathComponent("single.mindnode")
if prestarted != nil { ensure(!fm.fileExists(atPath: single.path), "Refusing to overwrite prestarted fixture file") }
try PropertyListSerialization.data(fromPropertyList: directPlist, format: .binary, options: 0)
    .write(to: single, options: .atomic)
let singleAttributes = try fm.attributesOfItem(atPath: single.path)
ensure(single.resolvingSymlinksInPath().standardizedFileURL == single.standardizedFileURL &&
       single.deletingLastPathComponent() == scratch &&
       singleAttributes[.type] as? FileAttributeType == .typeRegular &&
       singleAttributes[.ownerAccountID] as? NSNumber == NSNumber(value: getuid()),
       "Direct v9 source must be a regular file inside the exact owned scratch path")
func fileHash(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}
let singleHash = try fileHash(single)
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
let before = prestarted == nil ? try hashes(package) : [:]
if prestarted == nil { ensure(!before.isEmpty) }
let previous = scratch.appendingPathComponent(prestarted == nil ? "previous.mindmap.json" : "Untitled.mindmap.json")
let oldTitle = "Synthetic previous JSON"
let oldRoot: [String: Any] = ["id": UUID().uuidString, "title": oldTitle, "children": [], "folded": false]
let malformed = scratch.appendingPathComponent("malformed.mindnode", isDirectory: true)
if prestarted == nil {
    try JSONSerialization.data(withJSONObject: [oldRoot]).write(to: previous)
    try fm.createDirectory(at: malformed, withIntermediateDirectories: false)
    try Data([0x01, 0x02]).write(to: malformed.appendingPathComponent("contents.xml"))
}
func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
}
func axElement(_ raw: CFTypeRef?) -> AXUIElement? {
    guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
    return (raw as! AXUIElement)
}
func titleOf(_ element: AXUIElement) -> String { value(element, kAXTitleAttribute) as? String ?? "" }
func search(_ element: AXUIElement, matching: (AXUIElement) -> Bool) -> AXUIElement? {
    var queue = [element]
    var seen: Set<AXUIElement> = [element]
    var index = 0
    // ponytail: 1,000 unique AX elements per lookup; inspect narrower native panels if this cap is reached.
    while index < queue.count {
        let current = queue[index]
        index += 1
        if matching(current) { return current }
        for child in value(current, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if queue.count == 1_000 { break }
            if seen.insert(child).inserted { queue.append(child) }
        }
    }
    if queue.count == 1_000 { fputs("AX lookup stopped at 1,000 unique elements\n", stderr) }
    return nil
}
func find(_ element: AXUIElement, title: String) -> AXUIElement? {
    search(element) { titleOf($0) == title || value($0, kAXValueAttribute) as? String == title ||
        value($0, kAXDescriptionAttribute) as? String == title }
}
func findRole(_ element: AXUIElement, _ role: String) -> AXUIElement? {
    search(element) { value($0, kAXRoleAttribute) as? String == role }
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
    fail("Timed out: \(description)")
}
func press(_ element: AXUIElement, _ description: String) {
    ensure(AXUIElementPerformAction(element, kAXPressAction as CFString) == .success, "Cannot press \(description)")
}
func key(_ code: CGKeyCode, modifiers: CGEventFlags = []) {
    ensure(NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier,
                 "Refusing to send keyboard events outside selected MindMap process")
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { fail("No keyboard event") }
        event.flags = modifiers
        event.postToPid(running.processIdentifier)
    }
}
func menu(_ name: String) {
    let bar = wait("menu bar") { axElement(value(app, kAXMenuBarAttribute)) }
    guard let file = find(bar, title: "File") else { fail("File menu missing") }
    press(file, "File menu")
    press(wait(name) { find(file, title: name) }, name)
}
func panel() -> AXUIElement { wait("open panel") { windows().first { find($0, title: "Cancel") != nil && (find($0, title: "Open") != nil || find($0, title: "Choose") != nil) } } }
func navigate(to url: URL) {
    _ = panel()
    running.activate()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    var observedRoles = Set<String>()
    func focusedField() -> AXUIElement? {
        let focused = axElement(value(app, kAXFocusedUIElementAttribute))
        let role = focused.flatMap { value($0, kAXRoleAttribute) as? String } ?? "<none>"
        if observedRoles.insert(role).inserted { fputs("Go to Folder focused role: \(role)\n", stderr) }
        return role == kAXTextFieldRole ? focused : nil
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
    guard let field else { fail("Timed out: Go to Folder field") }
    ensure(AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, url.path as CFTypeRef) == .success,
                 "Cannot enter fixture directory")
    key(36) // Confirm the user-selected path inside the native panel.
}

let warningDetail = "Only text, tree structure and fold state were copied. Styles, notes and attachments are not round-tripped. Save creates a new .mindmap.json file; it never overwrites the MindNode package."
if prestarted != nil {
    let startup = scratch.appendingPathComponent("panel-ready")
    let panelReady = scratch.appendingPathComponent("import-panel-ready")
    let done = scratch.appendingPathComponent("import-done")
    ensure(!fm.fileExists(atPath: panelReady.path) && !fm.fileExists(atPath: done.path),
           "Refusing stale importer panel or completion markers")
    for _ in 0..<60 where (try? String(contentsOf: startup, encoding: .utf8)) != "ready\n" {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    ensure((try? String(contentsOf: startup, encoding: .utf8)) == "ready\n", "Owned importer app not ready")
    menu("Open MindNode (Read-only)…")
    var approvedPanel = false
    for _ in 0..<60 {
        let attributes = try? fm.attributesOfItem(atPath: panelReady.path)
        approvedPanel = panelReady.resolvingSymlinksInPath().standardizedFileURL == panelReady.standardizedFileURL &&
            attributes?[.type] as? FileAttributeType == .typeRegular &&
            attributes?[.ownerAccountID] as? NSNumber == NSNumber(value: getuid()) &&
            (try? String(contentsOf: panelReady, encoding: .utf8)) == "1\n"
        if approvedPanel { break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    ensure(approvedPanel, "Owned app did not certify current Open panel directory")
    let knownFile = wait("exact direct v9 file row") { listingItem(single.lastPathComponent) }
    ensure(value(knownFile, kAXEnabledAttribute) as? Bool == true, "Owned direct v9 file row disabled")
    ensure(AXUIElementSetAttributeValue(knownFile, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success &&
           value(knownFile, kAXSelectedAttribute) as? Bool == true,
           "Cannot select exact direct v9 file row without navigation")
    _ = AXUIElementPerformAction(wait("direct v9 Open") { find(panel(), title: "Open") }, kAXPressAction as CFString)
    let directWarning = wait("direct import read-only warning") { windows().first { find($0, title: "MindNode imported read-only") != nil } }
    ensure(find(directWarning, title: warningDetail) != nil, "Direct import loss warning missing")
    press(wait("direct warning OK") { find(directWarning, title: "OK") }, "direct warning OK")
    let directNode = wait("direct imported node") { windows().lazy.compactMap { find($0, title: directTitle) }.first }
    ensure(value(directNode, kAXSelectedAttribute) as? Bool == true, "Direct v9 root must be selected")
    ensure((try? fileHash(single)) == singleHash, "Direct import modified synthetic source file")
    menu("Save")
    let directSave = wait("direct import fresh Save panel") { windows().first { find($0, title: "Save") != nil && find($0, title: "Cancel") != nil } }
    ensure(find(directSave, title: "Untitled.mindmap.json") != nil ||
           axElement(value(app, kAXFocusedUIElementAttribute)).flatMap { value($0, kAXValueAttribute) as? String }?.hasSuffix(".mindmap.json") == true,
           "Direct import Save must propose new .mindmap.json destination")
    press(wait("direct Save Cancel") { find(directSave, title: "Cancel") }, "direct Save Cancel")
    ensure((try? fileHash(single)) == singleHash, "Direct source changed after Save cancellation")
    try "direct-v9-pass\n".write(to: done, atomically: true, encoding: .utf8)
    print("own-app direct-v9 import, certified native panel, read-only source and fresh Save destination passed")
    exit(0)
}
menu("Open Own JSON…")
navigate(to: previous)
_ = AXUIElementPerformAction(wait("JSON Open") { find(panel(), title: "Open") }, kAXPressAction as CFString)
let previousNode = wait("previous JSON root") { windows().lazy.compactMap { find($0, title: oldTitle) }.first }
ensure(value(previousNode, kAXSelectedAttribute) as? Bool == true, "Previous JSON not opened")
menu("Open MindNode (Read-only)…")
navigate(to: malformed)
_ = AXUIElementPerformAction(wait("malformed Open") { find(panel(), title: "Open") }, kAXPressAction as CFString)
let failure = wait("invalid package alert") { windows().first { find($0, title: "Could not open MindNode") != nil } }
press(wait("invalid OK") { find(failure, title: "OK") }, "invalid OK")
ensure(value(previousNode, kAXSelectedAttribute) as? Bool == true,
             "Invalid import must retain prior map and selection")
menu("Open MindNode (Read-only)…")
navigate(to: scratch)
let unrelated = wait("own JSON in import picker") { listingItem(previous.lastPathComponent) }
ensure(value(unrelated, kAXEnabledAttribute) as? Bool == false, "JSON must be disabled in MindNode import picker")
let listedPackage = wait("directory package in picker") { listingItem(package.lastPathComponent) }
ensure(value(listedPackage, kAXEnabledAttribute) as? Bool == true, "Directory package must be selectable")
navigate(to: package)
_ = AXUIElementPerformAction(wait("Open button") { find(panel(), title: "Open") }, kAXPressAction as CFString) // A modal alert can return cannotComplete after accepting the action.
let warning = wait("import loss warning") { windows().first { find($0, title: "MindNode imported read-only") != nil } }
ensure(find(warning, title: warningDetail) != nil,
             "Import loss warning missing")
press(wait("warning OK") { find(warning, title: "OK") }, "warning OK")
let node = wait("imported node") { windows().lazy.compactMap { find($0, title: title) }.first }
ensure(value(node, kAXSelectedAttribute) as? Bool == true, "Imported root must be selected")
let importedHashes = try hashes(package)
ensure(importedHashes == before, "Import modified source package")
menu("Save")
let savePanel = wait("fresh Save panel") { windows().first { find($0, title: "Save") != nil && find($0, title: "Cancel") != nil } }
ensure(find(savePanel, title: "Untitled.mindmap.json") != nil ||
             (axElement(value(app, kAXFocusedUIElementAttribute))).flatMap { value($0, kAXValueAttribute) as? String }?.hasSuffix(".mindmap.json") == true,
             "Save must propose new .mindmap.json destination")
press(wait("Save Cancel") { find(savePanel, title: "Cancel") }, "Save Cancel")
let finalHashes = try hashes(package)
ensure(finalHashes == before, "Source package changed after Save cancellation")
menu("Open MindNode (Read-only)…")
navigate(to: scratch)
let listedSingle = wait("direct v9 file in picker") { listingItem(single.lastPathComponent) }
ensure(value(listedSingle, kAXEnabledAttribute) as? Bool == true, "Direct v9 file must be selectable")
navigate(to: single)
_ = AXUIElementPerformAction(wait("direct v9 Open") { find(panel(), title: "Open") }, kAXPressAction as CFString)
let directWarning = wait("direct import read-only warning") { windows().first { find($0, title: "MindNode imported read-only") != nil } }
ensure(find(directWarning, title: warningDetail) != nil, "Direct import loss warning missing")
press(wait("direct warning OK") { find(directWarning, title: "OK") }, "direct warning OK")
let directNode = wait("direct imported node") { windows().lazy.compactMap { find($0, title: directTitle) }.first }
ensure(value(directNode, kAXSelectedAttribute) as? Bool == true, "Direct v9 root must be selected")
let importedSingleHash = try fileHash(single)
ensure(importedSingleHash == singleHash, "Direct import modified synthetic source file")
menu("Save")
let directSave = wait("direct import fresh Save panel") { windows().first { find($0, title: "Save") != nil && find($0, title: "Cancel") != nil } }
ensure(find(directSave, title: "Untitled.mindmap.json") != nil ||
       axElement(value(app, kAXFocusedUIElementAttribute)).flatMap { value($0, kAXValueAttribute) as? String }?.hasSuffix(".mindmap.json") == true,
       "Direct import Save must propose new .mindmap.json destination")
press(wait("direct Save Cancel") { find(directSave, title: "Cancel") }, "direct Save Cancel")
let finalSingleHash = try fileHash(single)
let finalPackageHashes = try hashes(package)
ensure(finalSingleHash == singleHash && finalPackageHashes == before,
       "Synthetic source file or package changed after Save cancellation")
print("own-app synthetic directory and direct-v9 import, prior JSON retention, picker filtering, selected nodes, warnings, fresh Save panels and source SHA-256 passed")
