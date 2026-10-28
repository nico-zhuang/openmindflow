#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
builder="$repo/scripts/build-openmindflow-tabs-0.5-local.sh"
packager="$repo/scripts/package-openmindflow-tabs-0.5-dmg.sh"
[[ -f "$builder" && -f "$packager" ]] || { echo 'RED: separate builder or packager missing' >&2; exit 1; }
scratch="$(mktemp -d /private/tmp/openmindflow-local-XXXXXXXX)"
[[ "$scratch" == /private/tmp/openmindflow-local-* && ! -L "$scratch" &&
   "$(cd "$scratch" && pwd -P)" == "$scratch" &&
   "$(stat -f %u "$scratch")" == "$(id -u)" && "$(stat -f %Lp "$scratch")" == 700 ]] || exit 1
# Deliberately retain the fixture (including failures): no test fixture deletion.
printf 'Private fixture: %s\n' "$scratch"
protected=("$repo/scripts/build-openmindflow-local.sh" "$repo/scripts/package-openmindflow-local-dmg.sh"
           "$repo/Tests/run-icon-package-safe.sh" "$repo/Tests/run-local-dmg-safe.sh"
           "$repo/Tests/NativeDocumentBundleTests.swift")
for path in "$repo"/build/*.app/Contents/MacOS/* "$repo"/dist/*.dmg "$repo"/dist/*.zip; do
  [[ -f "$path" && ! -L "$path" ]] && protected+=("$path")
done
before="$(shasum -a 256 "${protected[@]}")"
reject() { local label="$1"; shift; if "$@"; then echo "FAIL: accepted $label" >&2; exit 1; fi; echo "PASS rejected: $label"; }
app="$scratch/OpenMindFlow-Tabs-0.5.app"
dmg="$scratch/OpenMindFlow-Tabs-0.5-$(date +%s)-$$.dmg"
bash "$builder" "$app"
plist="$app/Contents/Info.plist"
icon="$app/Contents/Resources/OpenMindFlow.icns"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == local.openmindflow.tabs.20261027 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == 0.5.0 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" == 6 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:0:CFBundleTypeRole' "$plist")" == Editor ]]
[[ "$(shasum -a 256 "$icon" | awk '{print $1}')" == 3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3 ]]
reject 'existing builder app' bash "$builder" "$app"
reject 'builder path escape' bash "$builder" "$scratch/../OpenMindFlow-Tabs-0.5.app"
reject 'protected builder path' bash "$builder" "$repo/build/OpenMindFlow-Tabs-0.5.app"
linkedScratch="$(mktemp -d /private/tmp/openmindflow-local-XXXXXXXX)"
[[ "$linkedScratch" == /private/tmp/openmindflow-local-* && ! -L "$linkedScratch" &&
   "$(cd "$linkedScratch" && pwd -P)" == "$linkedScratch" &&
   "$(stat -f %u "$linkedScratch")" == "$(id -u)" && "$(stat -f %Lp "$linkedScratch")" == 700 ]]
printf 'Secondary private fixture: %s\n' "$linkedScratch"
ln -s "$app" "$linkedScratch/OpenMindFlow-Tabs-0.5.app"
reject 'builder symlink' bash "$builder" "$linkedScratch/OpenMindFlow-Tabs-0.5.app"
bash "$packager" "$app" "$dmg"
[[ -s "$dmg" ]]
hdiutil verify "$dmg"
hash="$(shasum -a 256 "$dmg" | awk '{print $1}')"
reject 'existing image' bash "$packager" "$app" "$dmg"
[[ "$(shasum -a 256 "$dmg" | awk '{print $1}')" == "$hash" ]]
reject 'image path escape' bash "$packager" "$app" "$scratch/../escape.dmg"
ln -s "$dmg" "$scratch/OpenMindFlow-Tabs-0.5-linked.dmg"
reject 'image symlink' bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-linked.dmg"
reject 'invalid image extension' bash "$packager" "$app" "$scratch/out.zip"
cp -R "$app" "$scratch/Other.app"
reject 'arbitrary app name' bash "$packager" "$scratch/Other.app" "$scratch/OpenMindFlow-Tabs-0.5-arbitrary.dmg"
cp "$plist" "$scratch/original-info.plist"
cp "$icon" "$scratch/original-icon.icns"
for change in 'CFBundleIdentifier wrong.id' 'CFBundleShortVersionString 0.4.0' 'CFBundleVersion 7' 'UTExportedTypeDeclarations:0:UTTypeIdentifier wrong.uti' 'CFBundleDocumentTypes:0:CFBundleTypeRole Viewer'; do
  key="${change%% *}"; value="${change#* }"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist"
  codesign --force --sign - --timestamp=none "$app"
  reject "validly re-signed $key" bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-invalid-${key//:/-}.dmg"
  cp "$scratch/original-info.plist" "$plist"
  codesign --force --sign - --timestamp=none "$app"
done
printf altered >> "$icon"
codesign --force --sign - --timestamp=none "$app"
reject 'validly re-signed icon' bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-invalid-icon.dmg"
cp "$scratch/original-icon.icns" "$icon"
codesign --force --sign - --timestamp=none "$app"
printf altered >> "$app/Contents/MacOS/OpenMindFlow"
reject 'broken signature' bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-invalid-signature.dmg"
[[ "$(shasum -a 256 "${protected[@]}")" == "$before" ]]
printf 'GREEN: 0.5 package safety passed; DMG SHA-256 %s; protected files unchanged (%s)\n' "$hash" "${#protected[@]}"
