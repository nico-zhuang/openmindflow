#!/bin/bash
set -euo pipefail

# Build only into a brand-new app in a caller-owned private /tmp fixture.
if [[ $# != 1 || "$1" != /* || "$1" != *.app ]]; then
  echo 'Usage: build-openmindflow-local.sh /tmp/openmindflow-local-XXXXXXXX/NewName.app' >&2
  exit 2
fi
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
requested="$1"
parent="${requested%/*}"
name="${requested##*/}"
if [[ ! -d "$parent" || -L "$parent" ]]; then echo 'Output parent must be an existing private directory' >&2; exit 2; fi
parent="$(cd "$parent" && pwd -P)"
if [[ "$parent" != /private/tmp/openmindflow-local-* || "$name" == MindMap.app || "$name" == MindMap-Feedback-20261026.app || "$name" == OpenMindFlow-Candidate-20261026.app || "$name" == OpenMindFlow-WindowFix-20261027.app || "$name" == OpenMindFlow-First-Signed-Preview.app || "$(stat -f %u "$parent")" != "$(id -u)" || "$(stat -f %Lp "$parent")" != 700 ]]; then
  echo 'Output must be a private owned scratch app, never a protected candidate' >&2
  exit 2
fi
app="$parent/$name"
if [[ -e "$app" || -L "$app" ]]; then echo 'Refusing to overwrite existing output' >&2; exit 2; fi
icon="$repo/Assets/OpenMindFlow.icns"
expected=3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3
if [[ ! -f "$icon" || "$(shasum -a 256 "$icon" | awk '{print $1}')" != "$expected" ]]; then
  echo 'Verified fallback icon missing or altered' >&2; exit 1
fi
mkdir "$app" # Atomic no-overwrite claim. On failure, keep only this newly claimed scratch output.
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
(cd "$repo" && swiftc Sources/*.swift -framework AppKit -framework AVKit -framework AVFoundation -o "$app/Contents/MacOS/OpenMindFlow")
cp "$icon" "$app/Contents/Resources/OpenMindFlow.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.openmindflow.native-editor</string>
  <key>CFBundleName</key><string>OpenMindFlow</string>
  <key>CFBundleDisplayName</key><string>OpenMindFlow</string>
  <key>CFBundleExecutable</key><string>OpenMindFlow</string>
  <key>CFBundleIconFile</key><string>OpenMindFlow.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
[[ "$(shasum -a 256 "$app/Contents/Resources/OpenMindFlow.icns" | awk '{print $1}')" == "$expected" ]]
codesign --sign - --timestamp=none "$app"
codesign --verify --deep --strict --verbose=2 "$app"
printf 'Built signed private app: %s\n' "$app"
