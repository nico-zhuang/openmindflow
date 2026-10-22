#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -f build/MindMap.app/Contents/Info.plist || bash build.sh
base="$(mktemp -d /tmp/mindmap-native-panel-XXXXXXXX)"
chmod 700 "$base"
printf 'mindmap-owned-native-panel\n' > "$base/.owner"
app="$base/MindMap-Native-Panel-SelfCheck.app"
ditto build/MindMap.app "$app"
swiftc -D HEADLESS_TEST Sources/*.swift Tests/NativePanelSelfCheck.swift -framework AppKit -o "$app/Contents/MacOS/MindMap"
plutil -replace CFBundleIdentifier -string "local.mindmap.native-editor.panel-selfcheck-$$" "$app/Contents/Info.plist"
printf 'OWNED_PANEL_FIXTURE=%s\n' "$base"
SELFTEST_APP="$app" SELFTEST_DIR="$base" swift -e '
import AppKit
import ApplicationServices
let env = ProcessInfo.processInfo.environment
let directory = URL(fileURLWithPath: env["SELFTEST_DIR"]!).resolvingSymlinksInPath()
let ownApp = URL(fileURLWithPath: env["SELFTEST_APP"]!).resolvingSymlinksInPath()
let report = directory.appendingPathComponent("report.txt")
let ready = directory.appendingPathComponent("panel-ready")
let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
guard AXIsProcessTrusted(),
      (try? String(contentsOf: directory.appendingPathComponent(".owner"), encoding: .utf8)) == "mindmap-owned-native-panel\n",
      attributes?[.ownerAccountID] as? NSNumber == NSNumber(value: getuid()),
      (attributes?[.posixPermissions] as? NSNumber)?.intValue == 0o700,
      let bundleID = Bundle(url: ownApp)?.bundleIdentifier else { exit(1) }
func attribute(_ item: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(item, key as CFString, &value) == .success ? value : nil
}
func saveButton(for pid: pid_t) -> AXUIElement? {
    let ax = AXUIElementCreateApplication(pid)
    for window in attribute(ax, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        var queue = [window]
        var i = 0
        var save: AXUIElement?
        var cancel = false
        while i < queue.count && i < 400 {
            let item = queue[i]
            i += 1
            if attribute(item, kAXRoleAttribute) as? String == kAXButtonRole {
                let title = attribute(item, kAXTitleAttribute) as? String
                if title == "Save" { save = item }
                if title == "Cancel" { cancel = true }
            }
            queue += attribute(item, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        if cancel, let save { return save }
    }
    return nil
}
let configuration = NSWorkspace.OpenConfiguration()
configuration.createsNewApplicationInstance = true
configuration.activates = true
configuration.environment = ["MINDMAP_SELFTEST_REPORT": report.path,
                             "MINDMAP_SELFTEST_PANEL_DIR": directory.path]
NSWorkspace.shared.openApplication(at: ownApp, configuration: configuration) { app, error in
    if let app { print("PANEL_LAUNCH_REQUEST=\(app.bundleIdentifier ?? "unknown")") }
    else { fputs("PANEL_LAUNCH_FAILED=\(error?.localizedDescription ?? "unknown")\n", stderr) }
}
func ownedRunning() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
        $0.processIdentifier > 0 && $0.bundleURL?.resolvingSymlinksInPath() == ownApp
    }
}
var pressed = false
let deadline = Date().addingTimeInterval(18)
while Date() < deadline {
    if let text = try? String(contentsOf: report, encoding: .utf8) {
        print(text, terminator: "")
        exit(text.contains("nativeSavePanel=true ownJSONDecoded=true nativeOpenPanel=unverified") && pressed ? 0 : 1)
    }
    if !pressed, (try? String(contentsOf: ready, encoding: .utf8)) == "ready\n",
       let owned = ownedRunning(), let button = saveButton(for: owned.processIdentifier) {
        let status = AXUIElementPerformAction(button, kAXPressAction as CFString)
        print("OWNED_SAVE_AX_PRESS=\(status.rawValue) pid=\(owned.processIdentifier)")
        guard status == .success else { _ = owned.terminate(); exit(1) }
        pressed = true
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}
if let owned = ownedRunning() { _ = owned.terminate() }
fputs("PANEL_SELFTEST_TIMEOUT_READY=\(FileManager.default.fileExists(atPath: ready.path)) PRESSED=\(pressed)\n", stderr)
exit(1)
'