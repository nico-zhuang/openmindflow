#!/bin/bash
set -euo pipefail
# Ad-hoc signatures validate integrity, never builder identity or publisher provenance.
if [[ $# != 2 || "$1" != /* || "$2" != /* ]]; then
  echo 'Usage: package-openmindflow-tabs-0.5-dmg.sh /private/tmp/openmindflow-local-*/OpenMindFlow-Tabs-0.5.app /private/tmp/openmindflow-local-*/OpenMindFlow-Tabs-0.5-UNIQUE.dmg' >&2; exit 2
fi
app="$1"; dmg="$2"; parent="${app%/*}"
dmgParent="${dmg%/*}"; dmgName="${dmg##*/}"
if [[ ! -d "$parent" || -L "$parent" ]]; then echo 'Private scratch missing' >&2; exit 2; fi
canonical="$(cd "$parent" && pwd -P)"
if [[ "$canonical" != "$parent" || ! "$parent" =~ ^/private/tmp/openmindflow-local-[A-Za-z0-9]+$ ||
      "$(stat -f %u "$parent")" != "$(id -u)" || "$(stat -f %Lp "$parent")" != 700 ||
      "$app" != "$parent/OpenMindFlow-Tabs-0.5.app" || ! -d "$app" || -L "$app" ||
      "$dmgParent" != "$parent" || ! "$dmgName" =~ ^OpenMindFlow-Tabs-0[.]5-[A-Za-z0-9][A-Za-z0-9._-]*[.]dmg$ ||
      -e "$dmg" || -L "$dmg" ]]; then
  echo 'Refusing escaped, arbitrary, protected, existing or symlink path' >&2; exit 2
fi
if [[ -n "$(find "$app" -type l -print -quit)" ]]; then echo 'Refusing app symlinks' >&2; exit 2; fi
check() { local actual; actual="$(/usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null)" || actual='';
  [[ "$actual" == "$2" ]] || { echo "Unexpected $1" >&2; exit 2; }; }
validate_app() {
  local candidate="$1" plist icon executable
  [[ -d "$candidate" && ! -L "$candidate" && -z "$(find "$candidate" -type l -print -quit)" ]] || { echo 'Refusing app symlinks' >&2; exit 2; }
  plist="$candidate/Contents/Info.plist"
  icon="$candidate/Contents/Resources/OpenMindFlow.icns"
  executable="$candidate/Contents/MacOS/OpenMindFlow"
  [[ -f "$plist" && -f "$icon" && -f "$executable" ]] || { echo 'Incomplete app' >&2; exit 2; }
check CFBundleIdentifier local.openmindflow.tabs.20261027
check CFBundleShortVersionString 0.5.0
check CFBundleVersion 6
check CFBundleName OpenMindFlow
check CFBundleDisplayName OpenMindFlow
check CFBundlePackageType APPL
check CFBundleExecutable OpenMindFlow
check CFBundleIconFile OpenMindFlow.icns
check LSMinimumSystemVersion 26.0
check UTExportedTypeDeclarations:0:UTTypeIdentifier local.openmindflow.document
check UTExportedTypeDeclarations:0:UTTypeConformsTo:0 public.data
check UTExportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension mflw
check UTExportedTypeDeclarations:0:UTTypeTagSpecification:public.mime-type application/vnd.openmindflow.mflw
check CFBundleDocumentTypes:0:LSItemContentTypes:0 local.openmindflow.document
check CFBundleDocumentTypes:0:CFBundleTypeRole Editor
[[ "$(shasum -a 256 "$icon" | awk '{print $1}')" == 3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3 ]] || { echo 'Wrong icon' >&2; exit 2; }
codesign --verify --deep --strict --verbose=2 "$candidate"
[[ "$(codesign -dv "$candidate" 2>&1 | awk -F= '/^Signature=/{print $2}')" == adhoc ]] || { echo 'Non-ad-hoc signature' >&2; exit 2; }
}
validate_app "$app"
parentIdentity="$(stat -f '%d:%i' "$parent")"
stage="$(mktemp -d "$parent/.openmindflow-tabs-0.5-dmg-stage-XXXXXXXX")"
[[ ! -L "$stage" && "$(cd "$stage" && pwd -P)" == "$stage" &&
   "$(stat -f %u "$stage")" == "$(id -u)" && "$(stat -f %Lp "$stage")" == 700 ]] || exit 2
stageIdentity="$(stat -f '%d:%i' "$stage")"
mountpoint=''; mountIdentity=''; mountDirectoryIdentity=''; mountDevice=''
attemptedAttach=0; ownDetached=0
mount_is_ours() {
  [[ -d "$parent" && ! -L "$parent" && "$(cd "$parent" && pwd -P)" == "$parent" &&
     "$(stat -f '%d:%i' "$parent")" == "$parentIdentity" &&
     -d "$stage" && ! -L "$stage" && "$(cd "$stage" && pwd -P)" == "$stage" &&
     "$(stat -f '%d:%i' "$stage")" == "$stageIdentity" &&
     -n "$mountpoint" && -n "$mountDevice" && -d "$mountpoint" && ! -L "$mountpoint" &&
     "$(cd "$mountpoint" && pwd -P)" == "$mountpoint" &&
     "$(stat -f '%d:%i' "$mountpoint")" == "$mountIdentity" ]] || return 1
  diskutil info -plist "$mountpoint" > "$stage/disk-info.plist" || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :DeviceNode' "$stage/disk-info.plist" 2>/dev/null)" == "$mountDevice" &&
     "$(/usr/libexec/PlistBuddy -c 'Print :MountPoint' "$stage/disk-info.plist" 2>/dev/null)" == "$mountpoint" ]]
}
# Attach can succeed even when its stdout is missing, malformed, or has no
# mount-point entity. In that case the parsed device is unavailable; resolve
# only this exact image path from the system attachment table, requiring one
# matching image and a diskutil-confirmed whole disk image before ejecting.
attached_image_device() {
  hdiutil info -plist | /usr/bin/python3 -c '
import plistlib, re, subprocess, sys
try:
    images = plistlib.loads(sys.stdin.buffer.read()).get("images", [])
    matches = [image for image in images if image.get("image-path") == sys.argv[1]]
    if len(matches) != 1:
        sys.exit(1 if not matches else 2)
    entities = matches[0].get("system-entities", [])
    if not entities:
        sys.exit(2)
    device = entities[0].get("dev-entry", "")
    if not re.fullmatch(r"/dev/disk[0-9]+", device):
        sys.exit(2)
    disk = plistlib.loads(subprocess.check_output(
        ["/usr/sbin/diskutil", "info", "-plist", device], stderr=subprocess.DEVNULL))
    if disk.get("DeviceNode") != device or disk.get("WholeDisk") is not True or disk.get("BusProtocol") != "Disk Image":
        sys.exit(2)
    print(device)
except (KeyError, ValueError, OSError, subprocess.CalledProcessError):
    sys.exit(2)
' "$dmg"
}
detach_ours() {
  local imageDevice status
  imageDevice="$(attached_image_device)" && status=0 || status=$?
  if [[ "$status" == 1 ]]; then
    # An absent image is benign only if no prior parsed attachment remains.
    [[ -z "$mountDevice" ]] && return 0
    echo 'Previously mounted image disappeared; refusing unsafe cleanup' >&2; return 1
  fi
  [[ "$status" == 0 ]] || { echo 'Image identity ambiguous; refusing unsafe detach' >&2; return 1; }
  hdiutil detach "$imageDevice" || return 1
  mountDevice=''
  return 0
}
cleanup() {
  # Detach only the very disk mounted at our verified exact path. Never delete a mounted directory.
  # EXIT may run before attach or after our successful detach. Neither state
  # owns an image, even if another process subsequently attaches this pathname.
  if [[ "$attemptedAttach" == 1 && "$ownDetached" == 0 ]]; then
    detach_ours || return 0
  fi
  if [[ -n "$mountpoint" && -d "$parent" && ! -L "$parent" &&
         "$(cd "$parent" && pwd -P)" == "$parent" &&
         "$(stat -f '%d:%i' "$parent")" == "$parentIdentity" &&
         -d "$mountpoint" && ! -L "$mountpoint" &&
        "$(cd "$mountpoint" && pwd -P)" == "$mountpoint" &&
        "$(stat -f '%d:%i' "$mountpoint")" == "$mountDirectoryIdentity" &&
         "$(stat -f %u "$mountpoint")" == "$(id -u)" && "$(stat -f %Lp "$mountpoint")" == 700 ]] &&
       ! mount | awk -v path="$mountpoint" 'index($0," on "path" (")>0 { found=1 } END { exit !found }'; then
    rmdir -- "$mountpoint" 2>/dev/null || :
  fi
  # A same-UID process can replace a pathname. Never recursively remove a replacement.
  if [[ -d "$parent" && ! -L "$parent" && "$(cd "$parent" && pwd -P)" == "$parent" &&
        "$(stat -f '%d:%i' "$parent")" == "$parentIdentity" &&
        "$(stat -f %u "$parent")" == "$(id -u)" && "$(stat -f %Lp "$parent")" == 700 &&
        -d "$stage" && ! -L "$stage" && "$stage" == "$parent"/.openmindflow-tabs-0.5-dmg-stage-* &&
        "$(cd "$stage" && pwd -P)" == "$stage" && "$(stat -f '%d:%i' "$stage")" == "$stageIdentity" &&
        "$(stat -f %u "$stage")" == "$(id -u)" && "$(stat -f %Lp "$stage")" == 700 ]] &&
      ! mount | awk -v root="$stage" 'index($0," on "root"/")>0 { found=1 } END { exit !found }'; then
    rm -rf -- "$stage"
  fi
}
trap cleanup EXIT
cp -R "$app" "$stage/OpenMindFlow-Tabs-0.5.app"
validate_app "$stage/OpenMindFlow-Tabs-0.5.app"
# Freeze the copied file names and bytes before image creation; never compare only to a mutable stage afterward.
manifest() { (cd "$1" && find OpenMindFlow-Tabs-0.5.app -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256); }
stagedManifest="$(manifest "$stage")"
[[ -n "$stagedManifest" ]] || { echo 'Empty staged manifest' >&2; exit 2; }
ln -s /Applications "$stage/Applications"
# Do not request overwrite; fail closed on already occupied destination.
hdiutil create -format UDZO -srcfolder "$stage" -volname OpenMindFlow-Tabs-0.5 "$dmg"
hdiutil verify "$dmg"
hdiutil imageinfo "$dmg"
mountpoint="$(mktemp -d "$parent/.openmindflow-tabs-0.5-verify-mount-XXXXXXXX")"
[[ ! -L "$mountpoint" && "$(cd "$mountpoint" && pwd -P)" == "$mountpoint" &&
   "$(stat -f %u "$mountpoint")" == "$(id -u)" && "$(stat -f %Lp "$mountpoint")" == 700 ]] || exit 2
mountDirectoryIdentity="$(stat -f '%d:%i' "$mountpoint")"
# An exact image pathname identifies the source, not who attached it. Refuse
# an image already attached before our invocation attempts its own attach.
preAttachStatus=0
attached_image_device > /dev/null && preAttachStatus=0 || preAttachStatus=$?
[[ "$preAttachStatus" == 1 ]] || { echo 'Image already attached or attachment identity ambiguous before own attach' >&2; exit 2; }
attemptedAttach=1
hdiutil attach -readonly -nobrowse -mountpoint "$mountpoint" -plist "$dmg" > "$stage/attach.plist"
for ((i=0; i<32; i++)); do
  candidateMount="$(/usr/libexec/PlistBuddy -c "Print :system-entities:$i:mount-point" "$stage/attach.plist" 2>/dev/null)" || continue
  if [[ "$candidateMount" == "$mountpoint" ]]; then
    mountDevice="$(/usr/libexec/PlistBuddy -c "Print :system-entities:$i:dev-entry" "$stage/attach.plist" 2>/dev/null)"
    break
  fi
done
[[ "$mountDevice" == /dev/disk* ]] || { echo 'Missing mounted disk identity' >&2; exit 2; }
mountIdentity="$(stat -f '%d:%i' "$mountpoint")"
mount_is_ours || { echo 'Mounted disk identity mismatch' >&2; exit 2; }
validate_app "$mountpoint/OpenMindFlow-Tabs-0.5.app"
[[ "$(manifest "$mountpoint")" == "$stagedManifest" ]] || { echo 'Mounted app differs from verified stage' >&2; exit 2; }
[[ -L "$mountpoint/Applications" && "$(readlink "$mountpoint/Applications")" == /Applications ]] || { echo 'Wrong Applications shortcut' >&2; exit 2; }
detach_ours || exit 2
ownDetached=1
printf 'Private 0.5 candidate DMG: %s\n' "$dmg"
