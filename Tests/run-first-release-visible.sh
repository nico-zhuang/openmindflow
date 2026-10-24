#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash build.sh
base="$(mktemp -d /tmp/mindmap-first-release-visible-XXXXXXXX)"
base="$(realpath "$base")"
[[ "$base" == /private/tmp/mindmap-first-release-visible-* ]]
chmod 700 "$base"
printf 'mindmap-owned-first-release-visible\n' > "$base/.owner"
app="$base/MindMap-First-Release-Synthetic.app"
report="$base/report.txt"
png="$base/whole-map.png"
test "$(realpath "$base")" = "$base"
test ! -e "$app"
ditto build/MindMap.app "$app"
swiftc -D HEADLESS_TEST Sources/*.swift Tests/FirstReleaseVisibleJourney.swift -framework AppKit -o "$app/Contents/MacOS/MindMap"
plutil -replace CFBundleIdentifier -string "local.mindmap.first-release-visible-$$" "$app/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string 'MindMap Synthetic First Release' "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app" >/dev/null
SELFTEST_APP="$app" SELFTEST_REPORT="$report" SELFTEST_PNG="$png" swift -e '
import AppKit
let env = ProcessInfo.processInfo.environment
let config = NSWorkspace.OpenConfiguration()
config.createsNewApplicationInstance = true
config.activates = true
config.arguments = [env["SELFTEST_REPORT"]!, env["SELFTEST_PNG"]!]
NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: env["SELFTEST_APP"]!), configuration: config) { app, error in
    if let app { print("SYNTHETIC_PID=\(app.processIdentifier)") }
    else { fputs("LAUNCH_FAIL=\(error?.localizedDescription ?? "unknown")\n", stderr) }
}
RunLoop.main.run(until: Date().addingTimeInterval(10))
if let text = try? String(contentsOfFile: env["SELFTEST_REPORT"]!, encoding: .utf8) {
    print(text, terminator: "")
    exit(text.hasPrefix("PASS visible=true key=true active=true") ? 0 : 1)
}
fputs("SYNTHETIC_VISIBLE_NO_REPORT\n", stderr)
exit(1)
'
test -s "$png"
printf 'OWNED_SYNTHETIC_GUI=%s\n' "$base"
