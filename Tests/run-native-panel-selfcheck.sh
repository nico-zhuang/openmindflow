#!/bin/bash
set -euo pipefail
if [[ $# -gt 1 || ( $# -eq 1 && $1 != --cancel && $1 != --open-cancel && $1 != --save-failure && $1 != --check-open-guard && $1 != --outline-return && $1 != --toolbar-new-child ) ]]; then printf 'Usage: %s [--cancel|--open-cancel|--save-failure|--check-open-guard|--outline-return|--toolbar-new-child]\n' "$0" >&2; exit 2; fi
cd "$(dirname "$0")/.."
if [[ ${1:-} == --check-open-guard ]]; then
  swift -e 'import Foundation
let source = try String(contentsOfFile: "Sources/App.swift", encoding: .utf8)
guard let start = source.range(of: "@objc private func openFile("),
      let end = source.range(of: "@objc private func openMindNode(", range: start.upperBound..<source.endIndex) else { exit(1) }
let open = source[start.lowerBound..<end.lowerBound]
guard open.contains("#if HEADLESS_TEST\n        guard let directory = ownedPanelFixtureDirectory() else { return }\n        panel.directoryURL = directory\n        #endif"),
      open.contains("guard url.resolvingSymlinksInPath() == directory.appendingPathComponent(\"Untitled.mindmap.json\") else { return }") else {
    fputs("FAIL HEADLESS Open exact owned-file guard missing\n", stderr); exit(1)
}
print("HEADLESS Open exact owned-file guard present")'
  exit
fi
test -f build/MindMap.app/Contents/Info.plist || bash build.sh
base="$(mktemp -d /tmp/mindmap-native-panel-XXXXXXXX)"
chmod 700 "$base"
printf 'mindmap-owned-native-panel\n' > "$base/.owner"
app="$base/MindMap-Native-Panel-SelfCheck.app"
ditto build/MindMap.app "$app"
swiftc -D HEADLESS_TEST Sources/*.swift Tests/NativePanelSelfCheck.swift -framework AppKit -o "$app/Contents/MacOS/MindMap"
plutil -replace CFBundleIdentifier -string "local.mindmap.native-editor.panel-selfcheck-$$" "$app/Contents/Info.plist"
printf 'OWNED_PANEL_FIXTURE=%s\n' "$base"
SELFTEST_APP="$app" SELFTEST_DIR="$base" SELFTEST_CANCEL="${1:-}" swift -e '
import AppKit
import ApplicationServices
let env = ProcessInfo.processInfo.environment
let opening = env["SELFTEST_CANCEL"] == "--open-cancel"
let failing = env["SELFTEST_CANCEL"] == "--save-failure"
let outlineReturn = env["SELFTEST_CANCEL"] == "--outline-return"
let toolbarNewChild = env["SELFTEST_CANCEL"] == "--toolbar-new-child"
let cancelling = env["SELFTEST_CANCEL"] == "--cancel" || opening
let directory = URL(fileURLWithPath: env["SELFTEST_DIR"]!).resolvingSymlinksInPath()
let ownApp = URL(fileURLWithPath: env["SELFTEST_APP"]!).resolvingSymlinksInPath()
let report = directory.appendingPathComponent("report.txt")
let ready = directory.appendingPathComponent("panel-ready")
let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
guard (outlineReturn || AXIsProcessTrusted()),
      (try? String(contentsOf: directory.appendingPathComponent(".owner"), encoding: .utf8)) == "mindmap-owned-native-panel\n",
      attributes?[.ownerAccountID] as? NSNumber == NSNumber(value: getuid()),
      (attributes?[.posixPermissions] as? NSNumber)?.intValue == 0o700,
      let bundleID = Bundle(url: ownApp)?.bundleIdentifier else { exit(1) }
func attribute(_ item: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(item, key as CFString, &value) == .success ? value : nil
}
func toolbarNewChildButton(for pid: pid_t) -> AXUIElement? {
    func children(_ item: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(item, kAXChildrenAttribute as CFString, &value) {
        case .success: return value as? [AXUIElement]
        case .noValue, .attributeUnsupported: return []
        default: return nil // Never mistake a failed AX query for a leaf.
        }
    }
    guard let windows = attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] else { return nil }
    let ownWindows = windows.filter { attribute($0, kAXTitleAttribute) as? String == "Untitled — MindMap" }
    guard ownWindows.count == 1 else { return nil }
    var queue = [ownWindows[0]], toolbars: [AXUIElement] = [], index = 0
    while index < queue.count {
        guard index < 400 else { return nil }
        let item = queue[index]; index += 1
        guard let role = attribute(item, kAXRoleAttribute) as? String,
              let next = children(item) else { return nil }
        if role == kAXToolbarRole { toolbars.append(item) }
        queue += next
    }
    guard toolbars.count == 1 else { return nil }
    queue = [toolbars[0]]; index = 0
    var matches: [AXUIElement] = []
    while index < queue.count {
        guard index < 100 else { return nil }
        let item = queue[index]; index += 1
        guard let role = attribute(item, kAXRoleAttribute) as? String,
              let next = children(item) else { return nil }
        let exactLabel = attribute(item, kAXTitleAttribute) as? String == "New Child" ||
                         attribute(item, kAXDescriptionAttribute) as? String == "New Child"
        if role == kAXButtonRole,
           exactLabel, (attribute(item, kAXEnabledAttribute) as? NSNumber)?.boolValue == true {
            matches.append(item)
        }
        queue += next
    }
    return matches.count == 1 ? matches[0] : nil
}
func panelButton(for pid: pid_t, wanted: String) -> AXUIElement? {
    let ax = AXUIElementCreateApplication(pid)
    for window in attribute(ax, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        var queue = [window]
        var i = 0
        var candidate: AXUIElement?
        var confirm = false
        var cancel = false
        while i < queue.count && i < 400 {
            let item = queue[i]
            i += 1
            if attribute(item, kAXRoleAttribute) as? String == kAXButtonRole {
                let title = attribute(item, kAXTitleAttribute) as? String
                if title == (opening ? "Open" : "Save") { confirm = true }
                if title == "Cancel" { cancel = true }
                if title == wanted { candidate = item }
            }
            queue += attribute(item, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        if confirm, cancel, let candidate { return candidate }
    }
    return nil
}
func failureAlertButton(for pid: pid_t) -> AXUIElement? {
    var matches: [AXUIElement] = []
    for window in attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        var queue = [window], index = 0, message = false
        var buttons: [AXUIElement] = []
        while index < queue.count && index < 400 {
            let item = queue[index]; index += 1
            let role = attribute(item, kAXRoleAttribute) as? String
            if role == kAXStaticTextRole,
               attribute(item, kAXValueAttribute) as? String == "Could not save map" { message = true }
            if role == kAXButtonRole,
               attribute(item, kAXTitleAttribute) as? String == "OK" { buttons.append(item) }
            queue += attribute(item, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        if message, buttons.count == 1 { matches.append(buttons[0]) }
    }
    return matches.count == 1 ? matches[0] : nil
}
let configuration = NSWorkspace.OpenConfiguration()
configuration.createsNewApplicationInstance = true
configuration.activates = true
configuration.environment = ["MINDMAP_SELFTEST_REPORT": report.path,
                             "MINDMAP_SELFTEST_PANEL_DIR": directory.path,
                             "MINDMAP_PANEL_ACTION": toolbarNewChild ? "toolbar-new-child" : outlineReturn ? "outline-return" : failing ? "save-failure" : opening ? "open-cancel" : cancelling ? "cancel" : "save"]
NSWorkspace.shared.openApplication(at: ownApp, configuration: configuration) { app, error in
    if let app { print("PANEL_LAUNCH_REQUEST=\(app.bundleIdentifier ?? "unknown")") }
    else { fputs("PANEL_LAUNCH_FAILED=\(error?.localizedDescription ?? "unknown")\n", stderr) }
}
func ownedRunning() -> NSRunningApplication? {
    let matches = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter {
        $0.processIdentifier > 0 && $0.bundleURL?.resolvingSymlinksInPath() == ownApp
    }
    return matches.count == 1 ? matches[0] : nil
}
var pressed = false
var alertDismissed = false
let deadline = Date().addingTimeInterval(toolbarNewChild ? 24 : 18)
while Date() < deadline {
    if let text = try? String(contentsOf: report, encoding: .utf8) {
        print(text, terminator: "")
        let expected = toolbarNewChild ? "nativeToolbarNewChild=true selectedChild=true dirty=true nativeEditor=true"
                       : outlineReturn ? "nativeOutlineReturn=true sameNode=true noSibling=true key=true"
                       : failing ? "nativeSaveFailure=true ownModelRetained=true dirtyRetained=true ownJSONAbsent=true"
                       : opening ? "nativeOpenCancel=true ownModelRetained=true dirtyRetained=true"
                       : cancelling ? "nativeSaveCancel=true ownModelRetained=true dirtyRetained=true"
                                    : "nativeSavePanel=true ownJSONDecoded=true nativeOpenPanel=unverified"
        exit(text.contains(expected) && (outlineReturn || pressed) && (!failing || alertDismissed) ? 0 : 1)
    }
    if toolbarNewChild, !pressed, (try? String(contentsOf: ready, encoding: .utf8)) == "ready\n",
       let owned = ownedRunning(),
       NSWorkspace.shared.frontmostApplication?.processIdentifier == owned.processIdentifier,
       let button = toolbarNewChildButton(for: owned.processIdentifier) {
        let status = AXUIElementPerformAction(button, kAXPressAction as CFString)
        print("OWNED_TOOLBAR_NEW_CHILD_AX_PRESS=\(status.rawValue) pid=\(owned.processIdentifier)")
        guard status == .success else { _ = owned.terminate(); exit(1) }
        pressed = true
    }
    if !outlineReturn, !toolbarNewChild, !pressed, (try? String(contentsOf: ready, encoding: .utf8)) == "ready\n",
       let owned = ownedRunning(), let button = panelButton(for: owned.processIdentifier,
                                                        wanted: cancelling ? "Cancel" : "Save") {
        let status = AXUIElementPerformAction(button, kAXPressAction as CFString)
        print("OWNED_\(cancelling ? "CANCEL" : "SAVE")_AX_PRESS=\(status.rawValue) pid=\(owned.processIdentifier)")
        guard status == .success else { _ = owned.terminate(); exit(1) }
        pressed = true
    }
    if failing, pressed, !alertDismissed, let owned = ownedRunning(),
       let button = failureAlertButton(for: owned.processIdentifier) {
        let status = AXUIElementPerformAction(button, kAXPressAction as CFString)
        print("OWNED_SAVE_FAILURE_ALERT_AX_PRESS=\(status.rawValue) pid=\(owned.processIdentifier)")
        guard status == .success else { _ = owned.terminate(); exit(1) }
        alertDismissed = true
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}
if let owned = ownedRunning() { _ = owned.terminate() }
fputs("PANEL_SELFTEST_TIMEOUT_READY=\(FileManager.default.fileExists(atPath: ready.path)) PRESSED=\(pressed)\n", stderr)
exit(1)
'