#!/bin/bash
set -euo pipefail

# Only a new, exactly named app inside a fresh caller-owned private scratch.
if [[ $# != 1 || "$1" != /* || "$1" != *.app ]]; then
  echo 'Usage: build-openmindflow-0.6.1-stable-local.sh /private/tmp/openmindflow-local-XXXXXXXX/OpenMindFlow-Stable-0.6.1.app' >&2
  exit 2
fi
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
requested="$1"
parent="${requested%/*}"
name="${requested##*/}"
if [[ ! -d "$parent" || -L "$parent" ]]; then echo 'Output parent must be a private scratch directory' >&2; exit 2; fi
canonical="$(cd "$parent" && pwd -P)"
if [[ "$canonical" != "$parent" ||
      "$(stat -f %u "$parent")" != "$(id -u)" || "$(stat -f %Lp "$parent")" != 700 ||
      "$name" != OpenMindFlow-Stable-0.6.1.app ]]; then
  echo 'Refusing escaped, non-private or protected output' >&2; exit 2
fi
[[ "$parent" =~ ^/private/tmp/openmindflow-local-[A-Za-z0-9]+$ ]] || {
  echo 'Refusing escaped, non-private or protected output' >&2; exit 2;
}
app="$parent/$name"
if [[ -e "$app" || -L "$app" ]]; then echo 'Refusing existing app or symlink' >&2; exit 2; fi
icon="$repo/Assets/OpenMindFlow.icns"
expected=3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3
if [[ ! -f "$icon" || -L "$icon" || "$(shasum -a 256 "$icon" | awk '{print $1}')" != "$expected" ]]; then
  echo 'Verified icon missing or altered' >&2; exit 1
fi
mkdir "$app" # Atomic no-overwrite claim; never remove a claimed output on failure.
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
(cd "$repo" && swiftc Sources/*.swift -framework AppKit -framework AVKit -framework AVFoundation -o "$app/Contents/MacOS/OpenMindFlow")
cp "$icon" "$app/Contents/Resources/OpenMindFlow.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.nicozhuang.openmindflow</string>
  <key>CFBundleName</key><string>OpenMindFlow</string>
  <key>CFBundleDisplayName</key><string>OpenMindFlow</string>
  <key>CFBundleExecutable</key><string>OpenMindFlow</string>
  <key>CFBundleIconFile</key><string>OpenMindFlow.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>8</string>
  <key>CFBundleShortVersionString</key><string>0.6.1</string>
  <key>OpenMindFlowReleaseVersion</key><string>0.6.1</string>
  <key>OpenMindFlowReleaseTag</key><string>v0.6.1</string>
  <key>OpenMindFlowReleaseChannel</key><string>stable</string>
  <key>UTExportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>local.openmindflow.document</string>
    <key>UTTypeDescription</key><string>OpenMindFlow Document</string>
    <key>UTTypeConformsTo</key><array><string>public.data</string></array>
    <key>UTTypeTagSpecification</key><dict>
      <key>public.filename-extension</key><string>mflw</string>
      <key>public.mime-type</key><string>application/vnd.openmindflow.mflw</string>
    </dict>
  </dict></array>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>OpenMindFlow Document</string>
    <key>LSItemContentTypes</key><array><string>local.openmindflow.document</string></array>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>LSHandlerRank</key><string>Owner</string>
  </dict></array>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
[[ "$(shasum -a 256 "$app/Contents/Resources/OpenMindFlow.icns" | awk '{print $1}')" == "$expected" ]]
codesign --sign - --timestamp=none "$app"
codesign --verify --deep --strict --verbose=2 "$app"
printf 'Built ad-hoc signed private 0.6.1 stable app: %s\n' "$app"
