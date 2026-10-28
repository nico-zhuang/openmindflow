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
mountpoint=''; mountIdentity=''; mountDevice=''
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
detach_ours() {
  [[ -z "$mountDevice" ]] && return 0
  mount_is_ours || { echo 'Mount identity changed; refusing unsafe detach' >&2; return 1; }
  hdiutil detach "$mountDevice" || return 1
  mountDevice=''
  return 0
}
cleanup() {
  # Detach only the very disk mounted at our verified exact path. Never delete a mounted directory.
  detach_ours || return 0
  if [[ -n "$mountpoint" && -d "$mountpoint" && ! -L "$mountpoint" &&
        "$(cd "$mountpoint" && pwd -P)" == "$mountpoint" &&
        "$(stat -f '%d:%i' "$mountpoint")" == "$mountIdentity" ]]; then
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
printf 'Private 0.5 candidate DMG: %s\n' "$dmg"
