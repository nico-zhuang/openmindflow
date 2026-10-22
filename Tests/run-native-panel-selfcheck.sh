#!/bin/bash
set -euo pipefail
if [[ $# -gt 1 || ( $# -eq 1 && $1 != --cancel && $1 != --open-cancel && $1 != --check-open-guard ) ]]; then printf 'Usage: %s [--cancel|--open-cancel|--check-open-guard]\n' "$0" >&2; exit 2; fi
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
let cancelling = env["SELFTEST_CANCEL"] == "--cancel" || opening
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
let configuration = NSWorkspace.OpenConfiguration()
configuration.createsNewApplicationInstance = true
configuration.activates = true
configuration.environment = ["MINDMAP_SELFTEST_REPORT": report.path,
                             "MINDMAP_SELFTEST_PANEL_DIR": directory.path,
                             "MINDMAP_PANEL_ACTION": opening ? "open-cancel" : cancelling ? "cancel" : "save"]
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
let deadline = Date().addingTimeInterval(18)
while Date() < deadline {
    if let text = try? String(contentsOf: report, encoding: .utf8) {
        print(text, terminator: "")
        let expected = opening ? "nativeOpenCancel=true ownModelRetained=true dirtyRetained=true"
                       : cancelling ? "nativeSaveCancel=true ownModelRetained=true dirtyRetained=true"
                                    : "nativeSavePanel=true ownJSONDecoded=true nativeOpenPanel=unverified"
        exit(text.contains(expected) && pressed ? 0 : 1)
    }
    if !pressed, (try? String(contentsOf: ready, encoding: .utf8)) == "ready\n",
       let owned = ownedRunning(), let button = panelButton(for: owned.processIdentifier,
                                                        wanted: cancelling ? "Cancel" : "Save") {
        let status = AXUIElementPerformAction(button, kAXPressAction as CFString)
        print("OWNED_\(cancelling ? "CANCEL" : "SAVE")_AX_PRESS=\(status.rawValue) pid=\(owned.processIdentifier)")
        guard status == .success else { _ = owned.terminate(); exit(1) }
        pressed = true
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}
if let owned = ownedRunning() { _ = owned.terminate() }
fputs("PANEL_SELFTEST_TIMEOUT_READY=\(FileManager.default.fileExists(atPath: ready.path)) PRESSED=\(pressed)\n", stderr)
exit(1)
'