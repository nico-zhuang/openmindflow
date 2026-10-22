#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -f build/MindMap.app/Contents/Info.plist || bash build.sh
base="$(mktemp -d /tmp/mindmap-native-selfcheck-XXXXXXXX)"
chmod 700 "$base"
printf 'mindmap-owned-native-selfcheck\n' > "$base/.owner"
app="$base/MindMap-Native-SelfCheck.app"
report="$base/report.txt"
ditto build/MindMap.app "$app"
swiftc -D HEADLESS_TEST Sources/*.swift Tests/NativeWindowSelfCheck.swift -framework AppKit -o "$app/Contents/MacOS/MindMap"
plutil -replace CFBundleIdentifier -string "local.mindmap.native-editor.selfcheck-$$" "$app/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string 'MindMap Synthetic Self Check' "$app/Contents/Info.plist"
SELFTEST_APP="$app" SELFTEST_REPORT="$report" swift -e '
import AppKit
let env = ProcessInfo.processInfo.environment
let config = NSWorkspace.OpenConfiguration()
config.createsNewApplicationInstance = true
config.activates = true
config.environment = ["MINDMAP_SELFTEST_REPORT": env["SELFTEST_REPORT"]!]
NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: env["SELFTEST_APP"]!), configuration: config) { app, error in
    if let app { print("SELFTEST_PID=\(app.processIdentifier)") }
    else { fputs("LAUNCH_FAIL=\(error?.localizedDescription ?? "unknown")\n", stderr) }
}
RunLoop.main.run(until: Date().addingTimeInterval(8))
if let text = try? String(contentsOfFile: env["SELFTEST_REPORT"]!, encoding: .utf8) {
    print(text, terminator: "")
    exit(text.contains("secondEdit=true") && text.contains("gapReorder=true") && text.contains("undo=true") ? 0 : 1)
}
fputs("SELFTEST_NO_REPORT\n", stderr)
exit(1)
'
test -s "$base/report.png"
test -s "$base/report.drag.png"
printf 'SYNTHETIC_GUI_IMAGES=%s\n' "$base"
