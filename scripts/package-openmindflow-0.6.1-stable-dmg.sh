#!/bin/bash
set -euo pipefail
# Ad-hoc signatures validate integrity, never builder identity or publisher provenance.
if [[ $# != 2 || "$1" != /* || "$2" != /* ]]; then
  echo 'Usage: package-openmindflow-0.6.1-stable-dmg.sh /private/tmp/openmindflow-local-*/OpenMindFlow-Stable-0.6.1.app /private/tmp/openmindflow-local-*/OpenMindFlow-Stable-0.6.1-UNIQUE.dmg' >&2; exit 2
fi
app="$1"; dmg="$2"; parent="${app%/*}"
dmgParent="${dmg%/*}"; dmgName="${dmg##*/}"
if [[ ! -d "$parent" || -L "$parent" ]]; then echo 'Private scratch missing' >&2; exit 2; fi
canonical="$(cd "$parent" && pwd -P)"
if [[ "$canonical" != "$parent" || ! "$parent" =~ ^/private/tmp/openmindflow-local-[A-Za-z0-9]+$ ||
      "$(stat -f %u "$parent")" != "$(id -u)" || "$(stat -f %Lp "$parent")" != 700 ||
      "$app" != "$parent/OpenMindFlow-Stable-0.6.1.app" || ! -d "$app" || -L "$app" ||
      "$dmgParent" != "$parent" || ! "$dmgName" =~ ^OpenMindFlow-Stable-0[.]6[.]1-[A-Za-z0-9][A-Za-z0-9._-]*[.]dmg$ ||
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
check CFBundleIdentifier com.nicozhuang.openmindflow
check CFBundleShortVersionString 0.6.1
check CFBundleVersion 8
check OpenMindFlowReleaseVersion 0.6.1
check OpenMindFlowReleaseTag v0.6.1
check OpenMindFlowReleaseChannel stable
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
check CFBundleDocumentTypes:0:LSHandlerRank Owner
[[ "$(shasum -a 256 "$icon" | awk '{print $1}')" == 3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3 ]] || { echo 'Wrong icon' >&2; exit 2; }
codesign --verify --deep --strict --verbose=2 "$candidate"
[[ "$(codesign -dv "$candidate" 2>&1 | awk -F= '/^Signature=/{print $2}')" == adhoc ]] || { echo 'Non-ad-hoc signature' >&2; exit 2; }
}
validate_app "$app"
manifest() { (cd "$1" && find OpenMindFlow-Stable-0.6.1.app -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256); }
sourceManifest="$(manifest "$parent")"
[[ -n "$sourceManifest" ]] || { echo 'Empty source manifest' >&2; exit 2; }
parentIdentity="$(stat -f '%d:%i' "$parent")"
stage="$(mktemp -d "$parent/.openmindflow-stable-0.6.1-dmg-stage-XXXXXXXX")"
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
# The attachment table identifies an image path and device, not who attached it.
# A missing/malformed own attach plist can leave a mount requiring manual review;
# never infer ownership from the image pathname alone.
attached_image_device() {
  local infoPlist="$stage/attached-images.plist"
  # A failed hdiutil query is ambiguous, even if it emitted valid plist bytes.
  # Do not conflate its exit 1 with the parser's definite absent-image exit 1.
  hdiutil info -plist > "$infoPlist" || return 2
  /usr/bin/python3 -c '
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
    # Attach reports a mounted volume; APFS can synthesize diskMsN from
    # physical store diskNsN, so a direct diskN prefix is not always valid.
    volumes = [entity.get("dev-entry", "") for entity in entities
               if entity.get("mount-point") == sys.argv[2]]
    if len(volumes) != 1:
        sys.exit(2)
    volume = volumes[0]
    if not re.fullmatch(re.escape(device) + r"(?:s[0-9]+)?", volume):
        if not re.fullmatch(r"/dev/disk[0-9]+s[0-9]+", volume):
            sys.exit(2)
        mounted = plistlib.loads(subprocess.check_output(
            ["/usr/sbin/diskutil", "info", "-plist", volume], stderr=subprocess.DEVNULL))
        stores = mounted.get("APFSPhysicalStores", [])
        container = mounted.get("APFSContainerReference", "")
        if (mounted.get("DeviceNode") != volume or mounted.get("MountPoint") != sys.argv[2]
                or mounted.get("BusProtocol") != "Disk Image" or len(stores) != 1
                or not re.fullmatch(r"disk[0-9]+", container)
                or "/dev/" + container not in [e.get("dev-entry") for e in entities]):
            sys.exit(2)
        store = stores[0].get("APFSPhysicalStore", "")
        if (not re.fullmatch(re.escape(device.removeprefix("/dev/")) + r"s[0-9]+", store)
                or "/dev/" + store not in [e.get("dev-entry") for e in entities]):
            sys.exit(2)
        physical = plistlib.loads(subprocess.check_output(
            ["/usr/sbin/diskutil", "info", "-plist", "/dev/" + store], stderr=subprocess.DEVNULL))
        if (physical.get("DeviceNode") != "/dev/" + store
                or physical.get("ParentWholeDisk") != device.removeprefix("/dev/")
                or physical.get("BusProtocol") != "Disk Image"
                or physical.get("APFSContainerReference") != container):
            sys.exit(2)
    print(volume)
except (AttributeError, IndexError, KeyError, TypeError, ValueError, OSError, subprocess.CalledProcessError):
    sys.exit(2)
' "$dmg" "$mountpoint" < "$infoPlist"
}
detach_ours() {
  local imageDevice status
  [[ -n "$mountDevice" ]] && mount_is_ours || {
    echo 'Own mounted device or mountpoint identity unverified; refusing unsafe detach' >&2; return 1;
  }
  imageDevice="$(attached_image_device)" && status=0 || status=$?
  [[ "$status" == 0 && "$imageDevice" == "$mountDevice" ]] || {
    echo 'Image device absent, changed or ambiguous; refusing unsafe detach' >&2; return 1;
  }
  hdiutil detach "$mountDevice" || return 1
  mountDevice=''
  return 0
}
cleanup() {
  local mountOutput
  # Detach only the very disk mounted at our verified exact path. Never delete a mounted directory.
  # EXIT may run before attach or after our successful detach. Neither state
  # owns an image, even if another process subsequently attaches this pathname.
  if [[ "$attemptedAttach" == 1 && "$ownDetached" == 0 ]]; then
    detach_ours || return 0
  fi
  # Unknown mount state is not proof that either private directory is unmounted.
  mountOutput="$(mount)" || { echo 'Cannot inspect mounts; retaining private stage and mountpoint' >&2; return 0; }
  if [[ -n "$mountpoint" && -d "$parent" && ! -L "$parent" &&
         "$(cd "$parent" && pwd -P)" == "$parent" &&
         "$(stat -f '%d:%i' "$parent")" == "$parentIdentity" &&
         -d "$mountpoint" && ! -L "$mountpoint" &&
        "$(cd "$mountpoint" && pwd -P)" == "$mountpoint" &&
        "$(stat -f '%d:%i' "$mountpoint")" == "$mountDirectoryIdentity" &&
         "$(stat -f %u "$mountpoint")" == "$(id -u)" && "$(stat -f %Lp "$mountpoint")" == 700 ]] &&
       ! printf '%s\n' "$mountOutput" | awk -v path="$mountpoint" 'index($0," on "path" (")>0 { found=1 } END { exit !found }'; then
    rmdir -- "$mountpoint" 2>/dev/null || :
  fi
  # A same-UID process can replace a pathname. Never recursively remove a replacement.
  if [[ -d "$parent" && ! -L "$parent" && "$(cd "$parent" && pwd -P)" == "$parent" &&
        "$(stat -f '%d:%i' "$parent")" == "$parentIdentity" &&
        "$(stat -f %u "$parent")" == "$(id -u)" && "$(stat -f %Lp "$parent")" == 700 &&
        -d "$stage" && ! -L "$stage" && "$stage" == "$parent"/.openmindflow-stable-0.6.1-dmg-stage-* &&
        "$(cd "$stage" && pwd -P)" == "$stage" && "$(stat -f '%d:%i' "$stage")" == "$stageIdentity" &&
        "$(stat -f %u "$stage")" == "$(id -u)" && "$(stat -f %Lp "$stage")" == 700 ]] &&
      ! printf '%s\n' "$mountOutput" | awk -v root="$stage" 'index($0," on "root"/")>0 { found=1 } END { exit !found }'; then
    rm -rf -- "$stage"
  fi
}
trap cleanup EXIT
cp -R "$app" "$stage/OpenMindFlow-Stable-0.6.1.app"
validate_app "$stage/OpenMindFlow-Stable-0.6.1.app"
# Freeze copied file names and bytes before image creation, matching the validated source.
stagedManifest="$(manifest "$stage")"
[[ -n "$stagedManifest" ]] || { echo 'Empty staged manifest' >&2; exit 2; }
[[ "$sourceManifest" == "$stagedManifest" ]] || { echo 'Staged app differs from validated source' >&2; exit 2; }
ln -s /Applications "$stage/Applications"
# Do not request overwrite; fail closed on already occupied destination.
hdiutil create -format UDZO -srcfolder "$stage" -volname OpenMindFlow-Stable-0.6.1 "$dmg"
hdiutil verify "$dmg"
hdiutil imageinfo "$dmg"
mountpoint="$(mktemp -d "$parent/.openmindflow-stable-0.6.1-verify-mount-XXXXXXXX")"
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
validate_app "$mountpoint/OpenMindFlow-Stable-0.6.1.app"
[[ "$(manifest "$mountpoint")" == "$stagedManifest" ]] || { echo 'Mounted app differs from verified stage' >&2; exit 2; }
[[ -L "$mountpoint/Applications" && "$(readlink "$mountpoint/Applications")" == /Applications ]] || { echo 'Wrong Applications shortcut' >&2; exit 2; }
detach_ours || exit 2
ownDetached=1
printf 'Private 0.6.1 stable candidate DMG: %s\n' "$dmg"
