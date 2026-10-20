#!/bin/bash
set -euo pipefail

app="build/MindMap.app"
mkdir -p "$app/Contents/MacOS"
swiftc Sources/*.swift -framework AppKit -o "$app/Contents/MacOS/MindMap"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.mindmap.native-editor</string>
  <key>CFBundleName</key><string>MindMap</string>
  <key>CFBundleDisplayName</key><string>MindMap</string>
  <key>CFBundleExecutable</key><string>MindMap</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
printf 'Built %s\n' "$app"
