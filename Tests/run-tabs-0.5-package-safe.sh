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
# Successful detach must remove the original empty mktemp directory, not compare its
# inode to the mounted volume's root inode (which necessarily differs).
mountDirs=("$scratch"/.openmindflow-tabs-0.5-verify-mount-*)
[[ ! -e "${mountDirs[0]}" ]] || { echo 'FAIL: successful packaging left verification mount directory' >&2; exit 1; }
# The mock performs a real attachment and only corrupts the returned plist. This
# reproduces a partial/complete attach whose device cannot be parsed from stdout.
attachedImageSnapshot() {
  /usr/bin/hdiutil info -plist | /usr/bin/python3 -c '
import plistlib, sys
p = plistlib.loads(sys.stdin.buffer.read())
for image in p.get("images", []):
    path = image.get("image-path", "")
    devices = sorted(e.get("dev-entry", "") for e in image.get("system-entities", []) if e.get("dev-entry"))
    print(path + "\t" + ",".join(devices))
' | LC_ALL=C sort
}
beforeAttachments="$(attachedImageSnapshot)"
attachMock="$scratch/attach-mock-bin"
mkdir "$attachMock"
cat > "$attachMock/hdiutil" <<'MOCK'
#!/bin/bash
set -euo pipefail
if [[ "$1" != attach ]]; then exec /usr/bin/hdiutil "$@"; fi
image="${@: -1}"
[[ "$image" == "$FIXTURE_IMAGE" ]] || exit 84
if [[ "${FIXTURE_NO_MOUNT:-0}" == 1 ]]; then
  /usr/bin/hdiutil attach -readonly -nobrowse -nomount -plist "$image" > "$FIXTURE_SCRATCH/actual-attach-no-mount.plist"
else
  /usr/bin/hdiutil "$@" > "$FIXTURE_SCRATCH/actual-attach.plist"
fi
# Confirm a genuine image attachment, then make the caller see unusable plist.
/usr/bin/python3 - "$FIXTURE_IMAGE" <<'PY'
import plistlib, subprocess, sys
images = plistlib.loads(subprocess.check_output(['/usr/bin/hdiutil', 'info', '-plist']))['images']
assert len([i for i in images if i.get('image-path') == sys.argv[1]]) == 1
PY
printf '<not a valid plist>\n'
MOCK
chmod 700 "$attachMock/hdiutil"
invalidAttachedDmg="$scratch/OpenMindFlow-Tabs-0.5-attach-invalid-$$.dmg"
if env PATH="$attachMock:$PATH" FIXTURE_SCRATCH="$scratch" FIXTURE_IMAGE="$invalidAttachedDmg" bash "$packager" "$app" "$invalidAttachedDmg" > "$scratch/attach-invalid.log" 2>&1; then
  echo 'FAIL: accepted invalid attach plist' >&2; exit 1
fi
[[ -s "$invalidAttachedDmg" ]] || { echo 'FAIL: rejected invalid attach did not produce inspectable private image' >&2; exit 1; }
[[ "$(< "$scratch/attach-invalid.log")" == *'Missing mounted disk identity'* ]] || { echo 'FAIL: invalid attach rejected for unrelated reason' >&2; exit 1; }
[[ "$(attachedImageSnapshot)" == "$beforeAttachments" ]] || { echo 'FAIL: attach failure leaked a disk or touched unrelated attachment' >&2; exit 1; }
noMountDmg="$scratch/OpenMindFlow-Tabs-0.5-attach-no-mount-$$.dmg"
if env PATH="$attachMock:$PATH" FIXTURE_SCRATCH="$scratch" FIXTURE_IMAGE="$noMountDmg" FIXTURE_NO_MOUNT=1 bash "$packager" "$app" "$noMountDmg" > "$scratch/attach-no-mount.log" 2>&1; then
  echo 'FAIL: accepted attached image without mounted payload' >&2; exit 1
fi
[[ -s "$noMountDmg" ]] || { echo 'FAIL: unmounted attachment lacked private inspectable image' >&2; exit 1; }
[[ "$(< "$scratch/attach-no-mount.log")" == *'Missing mounted disk identity'* ]] || { echo 'FAIL: unmounted attach rejected for unrelated reason' >&2; exit 1; }
/usr/bin/python3 - "$scratch/actual-attach-no-mount.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as stream:
    entities = plistlib.load(stream)['system-entities']
assert entities and not any(entity.get('mount-point') for entity in entities)
PY
[[ "$(attachedImageSnapshot)" == "$beforeAttachments" ]] || { echo 'FAIL: unmounted attach leaked a disk or touched unrelated attachment' >&2; exit 1; }
mountDirs=("$scratch"/.openmindflow-tabs-0.5-verify-mount-*)
[[ ! -e "${mountDirs[0]}" ]] || { echo 'FAIL: attach failure left verification mount directory' >&2; exit 1; }
reject 'existing image' bash "$packager" "$app" "$dmg"
[[ "$(shasum -a 256 "$dmg" | awk '{print $1}')" == "$hash" ]]
# Mock cp only after a real stage copy: a same-UID writer alters metadata and re-signs it.
stageMock="$scratch/stage-mock-bin"
mkdir "$stageMock"
cat > "$stageMock/cp" <<'MOCK'
#!/bin/bash
set -euo pipefail
/bin/cp "$@"
if [[ "$*" == *"/.openmindflow-tabs-0.5-dmg-stage-"* && "$*" == *"/OpenMindFlow-Tabs-0.5.app"* ]]; then
  target="${@: -1}"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 99' "$target/Contents/Info.plist"
  /usr/bin/codesign --force --sign - --timestamp=none "$target"
fi
MOCK
chmod 700 "$stageMock/cp"
reject 're-signed staged app metadata tamper' env PATH="$stageMock:$PATH" bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-stage-tamper.dmg"
[[ ! -e "$scratch/OpenMindFlow-Tabs-0.5-stage-tamper.dmg" ]] || { echo 'FAIL: staged tamper published image' >&2; exit 1; }
# Create a real, structurally valid UDZO from a differently re-signed app with extra resource bytes.
payloadMock="$scratch/payload-mock-bin"
mkdir "$payloadMock"
cat > "$payloadMock/hdiutil" <<'MOCK'
#!/bin/bash
set -euo pipefail
if [[ "$1" != create ]]; then exec /usr/bin/hdiutil "$@"; fi
source=''; args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[i]}" == -srcfolder ]]; then source="${args[i+1]}"; index=$((i+1)); break; fi
done
[[ "$source" == "$FIXTURE_SCRATCH"/.openmindflow-tabs-0.5-dmg-stage-* ]] || exit 82
payload="$FIXTURE_SCRATCH/tampered-payload-$$"
/bin/cp -R "$source" "$payload"
printf 'unexpected payload resource\n' > "$payload/OpenMindFlow-Tabs-0.5.app/Contents/Resources/payload-extra.txt"
/usr/bin/codesign --force --sign - --timestamp=none "$payload/OpenMindFlow-Tabs-0.5.app"
/usr/bin/codesign --verify --deep --strict "$payload/OpenMindFlow-Tabs-0.5.app" || exit 83
args[index]="$payload"
exec /usr/bin/hdiutil "${args[@]}"
MOCK
chmod 700 "$payloadMock/hdiutil"
payloadLog="$scratch/payload-rejection.log"
if env PATH="$payloadMock:$PATH" FIXTURE_SCRATCH="$scratch" bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-payload-tamper.dmg" > "$payloadLog" 2>&1; then
  echo 'FAIL: accepted real DMG payload resource tamper' >&2; exit 1
fi
[[ "$(< "$payloadLog")" == *'Mounted app differs from verified stage'* ]] || { echo 'FAIL: rejected payload without mounted-byte comparison' >&2; exit 1; }
[[ -s "$scratch/OpenMindFlow-Tabs-0.5-payload-tamper.dmg" ]]
hdiutil verify "$scratch/OpenMindFlow-Tabs-0.5-payload-tamper.dmg"
payloads=("$scratch"/tampered-payload-*)
[[ ${#payloads[@]} == 1 && -f "${payloads[0]}/OpenMindFlow-Tabs-0.5.app/Contents/Resources/payload-extra.txt" ]]
codesign --verify --deep --strict "${payloads[0]}/OpenMindFlow-Tabs-0.5.app"
echo 'PASS rejected: real DMG payload resource tamper (mounted byte mismatch)'
if mount | awk -v prefix="$scratch/.openmindflow-tabs-0.5-verify-mount-" 'index($0,prefix)>0 { found=1 } END { exit !found }'; then
  echo 'FAIL: packager retained a fixture verification mount' >&2; exit 1
fi
# Replace a freshly created stage (same UID and mode) at the hdiutil boundary.
# Its replacement must survive the packager EXIT trap. Retain both fixtures.
mockbin="$scratch/mock-bin"
mkdir "$mockbin"
cat > "$mockbin/hdiutil" <<'MOCK'
#!/bin/bash
set -euo pipefail
if [[ "$1" != create ]]; then exec /usr/bin/hdiutil "$@"; fi
stage=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -srcfolder ]]; then stage="$2"; break; fi
  shift
done
[[ -n "$stage" && "$stage" == "$FIXTURE_SCRATCH"/.openmindflow-tabs-0.5-dmg-stage-* &&
   ! -L "$stage" && "$(cd "$stage" && pwd -P)" == "$stage" &&
   "$(stat -f %u "$stage")" == "$(id -u)" && "$(stat -f %Lp "$stage")" == 700 &&
   ! -e "$stage-original" ]] || exit 81
mv -- "$stage" "$stage-original"
mkdir -m 700 "$stage"
printf 'replacement must survive\n' > "$stage/sentinel"
printf '%s\n' "$stage" > "$FIXTURE_SCRATCH/replaced-stage-path"
exit 73
MOCK
chmod 700 "$mockbin/hdiutil"
reject 'same-UID stage replacement' env PATH="$mockbin:$PATH" FIXTURE_SCRATCH="$scratch" bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-stage-replacement.dmg"
replacedStage="$(< "$scratch/replaced-stage-path")"
[[ -f "$replacedStage/sentinel" ]] || { echo 'FAIL: packager deleted same-UID replacement stage' >&2; exit 1; }
printf 'PASS retained replacement stage: %s\n' "$replacedStage"
# All rejection targets use a valid output basename unless the basename itself is under test.
mkdir "$scratch/OpenMindFlow-Tabs-0.5-nested"
reject 'noncanonical indirect child with valid basename' bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-nested/../OpenMindFlow-Tabs-0.5-escape.dmg"
[[ ! -e "$scratch/OpenMindFlow-Tabs-0.5-escape.dmg" ]]
reject 'parent escape with valid basename' bash "$packager" "$app" "$scratch/../OpenMindFlow-Tabs-0.5-escape.dmg"
[[ ! -e "$scratch/../OpenMindFlow-Tabs-0.5-escape.dmg" ]]
ln -s "$linkedScratch" "$scratch/OpenMindFlow-Tabs-0.5-ancestor"
reject 'image symlink ancestor with valid basename' bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-ancestor/OpenMindFlow-Tabs-0.5-escape.dmg"
[[ ! -e "$linkedScratch/OpenMindFlow-Tabs-0.5-escape.dmg" ]]
ln -s "$dmg" "$scratch/OpenMindFlow-Tabs-0.5-linked.dmg"
reject 'image symlink' bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-linked.dmg"
reject 'invalid image extension with valid prefix' bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-invalid.zip"
cp -R "$app" "$scratch/Other.app"
reject 'arbitrary app name' bash "$packager" "$scratch/Other.app" "$scratch/OpenMindFlow-Tabs-0.5-arbitrary.dmg"
cp "$plist" "$scratch/original-info.plist"
cp "$icon" "$scratch/original-icon.icns"
for change in 'CFBundleIdentifier wrong.id' 'CFBundleShortVersionString 0.4.0' 'CFBundleVersion 7' 'UTExportedTypeDeclarations:0:UTTypeIdentifier wrong.uti' 'CFBundleDocumentTypes:0:CFBundleTypeRole Viewer'; do
  key="${change%% *}"; value="${change#* }"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist"
  codesign --force --sign - --timestamp=none "$app"
  codesign --verify --deep --strict "$app" || { echo "FAIL: negative $key fixture has invalid signature" >&2; exit 1; }
  reject "validly re-signed $key" bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-invalid-${key//:/-}.dmg"
  cp "$scratch/original-info.plist" "$plist"
  codesign --force --sign - --timestamp=none "$app"
  codesign --verify --deep --strict "$app"
done
printf altered >> "$icon"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --deep --strict "$app" || { echo 'FAIL: negative icon fixture has invalid signature' >&2; exit 1; }
reject 'validly re-signed icon' bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-invalid-icon.dmg"
cp "$scratch/original-icon.icns" "$icon"
codesign --force --sign - --timestamp=none "$app"
printf altered >> "$app/Contents/MacOS/OpenMindFlow"
reject 'broken signature' bash "$packager" "$app" "$scratch/OpenMindFlow-Tabs-0.5-invalid-signature.dmg"
[[ "$(shasum -a 256 "${protected[@]}")" == "$before" ]]
printf 'GREEN: 0.5 package safety passed; DMG SHA-256 %s; protected files unchanged (%s)\n' "$hash" "${#protected[@]}"
