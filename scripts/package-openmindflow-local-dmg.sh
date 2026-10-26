#!/bin/bash
set -euo pipefail

# Only package a freshly built, locally signed app inside its own private scratch.
if [[ $# != 2 || "$1" != /* || "$2" != /* ]]; then
  echo 'Usage: package-openmindflow-local-dmg.sh /private/tmp/openmindflow-local-*/OpenMindFlow.app /private/tmp/openmindflow-local-*/*.dmg' >&2
  exit 2
fi
app="$1"
dmg="$2"
parent="${app%/*}"
[[ -d "$parent" && ! -L "$parent" ]] || { echo 'Private scratch missing' >&2; exit 2; }
canonical="$(cd "$parent" && pwd -P)"
if [[ "$parent" != "$canonical" || "$parent" != /private/tmp/openmindflow-local-* ||
      "$(stat -f %u "$parent")" != "$(id -u)" || "$(stat -f %Lp "$parent")" != 700 ||
      "$app" != "$parent/OpenMindFlow.app" || "$dmg" != "$parent/${dmg##*/}" ||
      "$dmg" != *.dmg || -e "$dmg" || -L "$dmg" ||
      ! -d "$app" || -L "$app" ]]; then
  echo 'Refusing non-private, escaped, malformed, or existing app/image path' >&2
  exit 2
fi
if [[ -n "$(find "$app" -type l -print -quit)" ]]; then
  echo 'Refusing app containing symlinks' >&2
  exit 2
fi
plist="$app/Contents/Info.plist"
icon="$app/Contents/Resources/OpenMindFlow.icns"
if [[ ! -f "$plist" || ! -f "$icon" || ! -f "$app/Contents/MacOS/OpenMindFlow" ||
      "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null)" != local.openmindflow.native-editor ||
      "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$plist" 2>/dev/null)" != OpenMindFlow ||
      "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null)" != OpenMindFlow ||
      "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist" 2>/dev/null)" != OpenMindFlow.icns ||
      "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null)" != 0.3.0 ||
      "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null)" != 4 ||
      "$(shasum -a 256 "$icon" | awk '{print $1}')" != 3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3 ]]; then
  echo 'Refusing unexpected app metadata or icon' >&2
  exit 2
fi
codesign --verify --deep --strict --verbose=2 "$app"
[[ "$(codesign -dv "$app" 2>&1 | awk -F= '/^Signature=/{print $2}')" == adhoc ]] || {
  echo 'Refusing non-ad-hoc or unsigned app' >&2; exit 2;
}

stage="$(mktemp -d "$parent/.openmindflow-dmg-stage-XXXXXXXX")"
[[ ! -L "$stage" && "$(cd "$stage" && pwd -P)" == "$stage" &&
   "$(stat -f %u "$stage")" == "$(id -u)" ]] || exit 2
cleanup() {
  # Never remove anything without re-verifying this exact fresh staging directory.
  if [[ -d "$stage" && ! -L "$stage" && "$stage" == "$parent"/.openmindflow-dmg-stage-* &&
        "$(cd "$stage" && pwd -P)" == "$stage" && "$(stat -f %u "$stage")" == "$(id -u)" ]]; then
    rm -rf -- "$stage"
  fi
}
trap cleanup EXIT
cp -R "$app" "$stage/OpenMindFlow.app"
ln -s /Applications "$stage/Applications"
# No -ov: an existing image is never overwritten.
hdiutil create -format UDZO -srcfolder "$stage" -volname OpenMindFlow "$dmg"
hdiutil verify "$dmg"
hdiutil imageinfo "$dmg"
printf 'Private drag-install DMG: %s\n' "$dmg"
