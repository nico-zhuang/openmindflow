#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd -P)"
package="$repo/scripts/package-openmindflow-local-dmg.sh"
[[ -f "$package" ]] || { echo 'RED: local DMG packaging script missing' >&2; exit 1; }

scratch="$(mktemp -d /private/tmp/openmindflow-local-XXXXXXXX)"
[[ ! -L "$scratch" && "$(cd "$scratch" && pwd -P)" == "$scratch" &&
   "$(stat -f %u "$scratch")" == "$(id -u)" && "$(stat -f %Lp "$scratch")" == 700 ]] || exit 1
# Only remove the precise fresh fixture we own, after checking its resolved location.
cleanup() {
  status=$?
  if [[ "$status" != 0 ]]; then echo "Retaining failed private fixture for inspection: $scratch" >&2; return; fi
  if [[ ! -L "$scratch" && -d "$scratch" && "$(cd "$scratch" && pwd -P)" == "$scratch" &&
        "$scratch" == /private/tmp/openmindflow-local-* && "$(stat -f %u "$scratch")" == "$(id -u)" &&
        "$(stat -f %Lp "$scratch")" == 700 ]]; then rm -rf -- "$scratch"; fi
}
trap cleanup EXIT
export TMPDIR="$scratch/"

protected=("$repo/build/MindMap.app/Contents/MacOS/MindMap"
           "$repo/build/MindMap-Feedback-20261026.app/Contents/MacOS/MindMap"
           "$repo/build/OpenMindFlow-Candidate-20261026.app/Contents/MacOS/OpenMindFlow"
           "$repo/build/OpenMindFlow-WindowFix-20261027.app/Contents/MacOS/OpenMindFlow"
           "$repo/dist/MindMap-First-Release-Preview-20261024.zip"
           "$repo/dist/OpenMindFlow-WindowFix-20261027.zip")
before=()
for path in "${protected[@]}"; do
  if [[ -f "$path" && ! -L "$path" ]]; then before+=("$(shasum -a 256 "$path")"); fi
done

app="$scratch/OpenMindFlow.app"
dmg="$scratch/OpenMindFlow-local.dmg"
bash "$repo/scripts/build-openmindflow-local.sh" "$app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == local.openmindflow.native-editor ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == 0.3.0 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == 4 ]]
[[ "$(shasum -a 256 "$app/Contents/Resources/OpenMindFlow.icns" | awk '{print $1}')" == 3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3 ]]
codesign --verify --deep --strict --verbose=2 "$app"
[[ "$(codesign -dv "$app" 2>&1 | awk -F= '/^Signature=/{print $2}')" == adhoc ]]

bash "$package" "$app" "$dmg"
[[ -f "$dmg" && -s "$dmg" ]]
hdiutil verify "$dmg"
hdiutil imageinfo "$dmg"
first_hash="$(shasum -a 256 "$dmg" | awk '{print $1}')"
if bash "$package" "$app" "$dmg"; then echo 'ERROR: repeated output was overwritten' >&2; exit 1; fi
[[ "$(shasum -a 256 "$dmg" | awk '{print $1}')" == "$first_hash" ]]
if bash "$package" "$app" "$scratch/../outside.dmg"; then echo 'ERROR: path escape accepted' >&2; exit 1; fi
ln -s "$dmg" "$scratch/linked.dmg"
if bash "$package" "$app" "$scratch/linked.dmg"; then echo 'ERROR: output symlink accepted' >&2; exit 1; fi

cp "$app/Contents/Info.plist" "$scratch/valid-info.plist"
cp "$app/Contents/Resources/OpenMindFlow.icns" "$scratch/valid-icon.icns"
for metadata in 'CFBundleDisplayName NotOpenMindFlow' 'CFBundlePackageType BAD!' 'LSMinimumSystemVersion 10.12'; do
  field="${metadata%% *}"
  value="${metadata#* }"
  /usr/libexec/PlistBuddy -c "Set :$field $value" "$app/Contents/Info.plist"
  codesign --force --sign - --timestamp=none "$app"
  if bash "$package" "$app" "$scratch/invalid-$field.dmg"; then
    echo "ERROR: validly self-signed but wrong $field was accepted" >&2; exit 1
  fi
  cp "$scratch/valid-info.plist" "$app/Contents/Info.plist"
  codesign --force --sign - --timestamp=none "$app"
done
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier wrong.id' "$app/Contents/Info.plist"
if bash "$package" "$app" "$scratch/invalid-id.dmg"; then echo 'ERROR: invalid bundle ID accepted' >&2; exit 1; fi
cp "$scratch/valid-info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 5' "$app/Contents/Info.plist"
if bash "$package" "$app" "$scratch/invalid-version.dmg"; then echo 'ERROR: invalid version accepted' >&2; exit 1; fi
cp "$scratch/valid-info.plist" "$app/Contents/Info.plist"
printf altered >> "$app/Contents/Resources/OpenMindFlow.icns"
if bash "$package" "$app" "$scratch/invalid-icon.dmg"; then echo 'ERROR: invalid icon accepted' >&2; exit 1; fi
cp "$scratch/valid-icon.icns" "$app/Contents/Resources/OpenMindFlow.icns"
printf altered >> "$app/Contents/MacOS/OpenMindFlow"
if bash "$package" "$app" "$scratch/invalid-signature.dmg"; then echo 'ERROR: invalid signature accepted' >&2; exit 1; fi
[[ ! -e "$scratch/invalid-id.dmg" && ! -e "$scratch/invalid-version.dmg" &&
   ! -e "$scratch/invalid-icon.dmg" && ! -e "$scratch/invalid-signature.dmg" ]]
after=()
for path in "${protected[@]}"; do
  if [[ -f "$path" && ! -L "$path" ]]; then after+=("$(shasum -a 256 "$path")"); fi
done
[[ "${before[*]}" == "${after[*]}" ]]
printf 'GREEN: local DMG verified; SHA-256 %s; protected hashes unchanged (%s files)\n' "$first_hash" "${#before[@]}"
