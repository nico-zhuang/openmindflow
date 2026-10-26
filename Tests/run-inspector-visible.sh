#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

safe_focus() {
    local frontmost idle
    frontmost="$(swift -e 'import AppKit; print(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")' 2>/dev/null)"
    idle="$(ioreg -c IOHIDSystem -d 4 | awk '/HIDIdleTime/ { for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+$/) { print int($i/1000000000); exit } }')"
    [[ "$frontmost" == com.apple.finder && "${idle:-0}" -ge 180 ]]
}
if ! safe_focus; then
    printf 'SKIP visible GUI: Finder must be frontmost and input idle at least 180 seconds\n'
    exit 77
fi
base="$(realpath "$(mktemp -d /tmp/mindmap-inspector-visible-XXXXXXXX)")"
[[ "$base" == /private/tmp/mindmap-inspector-visible-* ]]
chmod 700 "$base"
printf 'mindmap-owned-inspector-visible\n' > "$base/.owner"
app="$base/MindMap-Inspector-Synthetic.app"
report="$base/report.txt"
test ! -e "$app"
ditto build/MindMap.app "$app"
swiftc -D HEADLESS_TEST Sources/*.swift Tests/InspectorVisibleJourney.swift -framework AppKit -framework AVKit -framework AVFoundation -o "$app/Contents/MacOS/MindMap"
plutil -replace CFBundleIdentifier -string "local.mindmap.inspector-synthetic-$$" "$app/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string 'MindMap Synthetic Inspector' "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app" >/dev/null
if ! safe_focus; then
    printf 'SKIP visible GUI: desktop activity changed during synthetic build\n'
    exit 77
fi
MINDMAP_OWNED_FOCUS_PRECHECK=yes SELFTEST_APP="$app" SELFTEST_REPORT="$report" swift -e '
import AppKit
let env = ProcessInfo.processInfo.environment
let configuration = NSWorkspace.OpenConfiguration()
configuration.createsNewApplicationInstance = true
configuration.activates = false // Fixture rechecks Finder before its own activation.
configuration.environment = ["MINDMAP_OWNED_FOCUS_PRECHECK": "yes"]
configuration.arguments = [env["SELFTEST_REPORT"]!]
NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: env["SELFTEST_APP"]!), configuration: configuration) { app, error in
    if let app { print("SYNTHETIC_PID=\(app.processIdentifier)") }
    else { fputs("LAUNCH_FAIL=\(error?.localizedDescription ?? "unknown")\n", stderr) }
}
RunLoop.main.run(until: Date().addingTimeInterval(8))
let report = env["SELFTEST_REPORT"]!
guard let result = try? String(contentsOfFile: report, encoding: .utf8) else {
    fputs("SYNTHETIC_VISIBLE_NO_REPORT\n", stderr)
    exit(1)
}
print(result, terminator: "")
if result.hasPrefix("SKIP unsafe desktop focus") { exit(77) }
exit(result.hasPrefix("PASS visible=true key=true frontmost=true") ? 0 : 1)
'
printf 'OWNED_SYNTHETIC_GUI=%s\n' "$base"
