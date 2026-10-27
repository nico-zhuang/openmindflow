#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
builder="scripts/build-openmindflow-local.sh"
[[ -x "$builder" ]] || { echo "RED: safe OpenMindFlow builder missing" >&2; exit 1; }
expected=3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3
[[ -f Assets/OpenMindFlow.icns && $(shasum -a 256 Assets/OpenMindFlow.icns | awk '{print $1}') == "$expected" ]]
fixture="$(mktemp -d /tmp/openmindflow-local-XXXXXXXX)"
chmod 700 "$fixture"
app="$fixture/OpenMindFlow-Test.app"
"$builder" "$app"
[[ -f "$app/Contents/MacOS/OpenMindFlow" ]]
[[ $(shasum -a 256 "$app/Contents/Resources/OpenMindFlow.icns" | awk '{print $1}') == "$expected" ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$app/Contents/Info.plist") == OpenMindFlow.icns ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$app/Contents/Info.plist") == OpenMindFlow ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") == local.openmindflow.nativeformat.20261027 ]]
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$version" == 0.4.0 && "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'FAIL: expected semantic version 0.4.0, got %s\n' "$version" >&2; exit 1; }
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist") == 5 ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :UTExportedTypeDeclarations:0:UTTypeIdentifier' "$app/Contents/Info.plist") == local.openmindflow.document ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :UTExportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension' "$app/Contents/Info.plist") == mflw ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:0:CFBundleTypeRole' "$app/Contents/Info.plist") == Editor ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist") == 26.0 ]]
plutil -lint "$app/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app"
if "$builder" "$app"; then echo 'FAIL: existing bundle overwritten' >&2; exit 1; fi
if "$builder" "$PWD/build/MindMap.app"; then echo 'FAIL: protected build path accepted' >&2; exit 1; fi
printf 'PASS icon=%s signedBundle=%s repeatRejected=true protectedRejected=true\n' "$expected" "$app"
