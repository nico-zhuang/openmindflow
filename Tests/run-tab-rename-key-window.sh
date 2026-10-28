#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo"
umask 077
scratch="$(mktemp -d /private/tmp/omf-rename-key-window.XXXXXXXX)"
[[ "$(realpath "$scratch")" == "$scratch" && ! -L "$scratch" && "$(stat -f '%u:%Lp' "$scratch")" == "$(id -u):700" ]]
app="$scratch/TabRenameKeyWindowTests.app"
mkdir -p "$app/Contents/MacOS"
identifier="local.openmindflow.test.tabrename.$(uuidgen | tr -d '-')"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$identifier</string>
<key>CFBundleExecutable</key><string>TabRenameKeyWindowTests</string>
<key>CFBundleName</key><string>TabRenameKeyWindowTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
EOF
swiftc -suppress-warnings -D HEADLESS_TEST Sources/*.swift Tests/TabRenameKeyWindowTests.swift \
    -framework AppKit -framework AVKit -framework AVFoundation \
    -o "$app/Contents/MacOS/TabRenameKeyWindowTests" > "$scratch/compile.log" 2>&1
codesign --force --sign - "$app"
report="$scratch/result.txt"
# `open -W` can succeed even when the app exits nonzero: the written result is authoritative.
open -W -n "$app" --args "$report" || true
/usr/bin/python3 - "$report" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
if not path.is_file():
    raise SystemExit(f'FAIL no key-window result; private fixture: {path.parent}')
value = path.read_text()
print(value)
if value != 'PASS real key-window double-click kept field editor and committed typed title':
    raise SystemExit(f'key-window regression failed; private fixture: {path.parent}')
PY
printf 'KEY_WINDOW_RENAME_PASS fixture=%s\n' "$scratch"
