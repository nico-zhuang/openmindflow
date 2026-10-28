#!/bin/bash
set -euo pipefail
# Ad-hoc signatures validate integrity, never builder identity or publisher provenance.
if [[ $# != 2 || "$1" != /* || "$2" != /* ]]; then
  echo 'Usage: package-openmindflow-tabs-0.5-dmg.sh /private/tmp/openmindflow-local-*/OpenMindFlow-Tabs-0.5.app /private/tmp/openmindflow-local-*/OpenMindFlow-Tabs-0.5-UNIQUE.dmg' >&2; exit 2
fi
app="$1"; dmg="$2"; parent="${app%/*}"
if [[ ! -d "$parent" || -L "$parent" ]]; then echo 'Private scratch missing' >&2; exit 2; fi
canonical="$(cd "$parent" && pwd -P)"
if [[ "$canonical" != "$parent" || "$parent" != /private/tmp/openmindflow-local-* ||
      "$(stat -f %u "$parent")" != "$(id -u)" || "$(stat -f %Lp "$parent")" != 700 ||
      "$app" != "$parent/OpenMindFlow-Tabs-0.5.app" || ! -d "$app" || -L "$app" ||
      "$dmg" != "$parent/OpenMindFlow-Tabs-0.5-"*.dmg ||
      "${dmg##*/}" == OpenMindFlow-Tabs-0.5-.dmg || -e "$dmg" || -L "$dmg" ]]; then
  echo 'Refusing escaped, arbitrary, protected, existing or symlink path' >&2; exit 2
fi
if [[ -n "$(find "$app" -type l -print -quit)" ]]; then echo 'Refusing app symlinks' >&2; exit 2; fi
plist="$app/Contents/Info.plist"
icon="$app/Contents/Resources/OpenMindFlow.icns"
executable="$app/Contents/MacOS/OpenMindFlow"
[[ -f "$plist" && -f "$icon" && -f "$executable" ]] || { echo 'Incomplete app' >&2; exit 2; }
check() { local actual; actual="$(/usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null)" || actual='';
  [[ "$actual" == "$2" ]] || { echo "Unexpected $1" >&2; exit 2; }; }
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
codesign --verify --deep --strict --verbose=2 "$app"
[[ "$(codesign -dv "$app" 2>&1 | awk -F= '/^Signature=/{print $2}')" == adhoc ]] || { echo 'Non-ad-hoc signature' >&2; exit 2; }
stage="$(mktemp -d "$parent/.openmindflow-tabs-0.5-dmg-stage-XXXXXXXX")"
[[ ! -L "$stage" && "$(cd "$stage" && pwd -P)" == "$stage" &&
   "$(stat -f %u "$stage")" == "$(id -u)" && "$(stat -f %Lp "$stage")" == 700 ]] || exit 2
cleanup() {
  if [[ -d "$stage" && ! -L "$stage" && "$stage" == "$parent"/.openmindflow-tabs-0.5-dmg-stage-* &&
        "$(cd "$stage" && pwd -P)" == "$stage" && "$(stat -f %u "$stage")" == "$(id -u)" &&
        "$(stat -f %Lp "$stage")" == 700 ]]; then rm -rf -- "$stage"; fi
}
trap cleanup EXIT
cp -R "$app" "$stage/OpenMindFlow-Tabs-0.5.app"
ln -s /Applications "$stage/Applications"
# Do not request overwrite; fail closed on already occupied destination.
hdiutil create -format UDZO -srcfolder "$stage" -volname OpenMindFlow-Tabs-0.5 "$dmg"
hdiutil verify "$dmg"
hdiutil imageinfo "$dmg"
printf 'Private 0.5 candidate DMG: %s\n' "$dmg"
