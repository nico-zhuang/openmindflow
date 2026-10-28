#!/bin/bash
set -euo pipefail

# Non-destructive negative-only checks: no production image is created or mounted.
root="$(cd "$(dirname "$0")/.." && pwd -P)"
packager="$root/scripts/package-openmindflow-0.6-stable-dmg.sh"
old="$root/scripts/package-openmindflow-tabs-0.5-dmg.sh"
oldSha=c61eb5db822351c259f66a05f41887f0d2dda6390a0f51a7ce6d7ec9ed0aa0e0
fail() { echo "FAIL: $*" >&2; exit 1; }
[[ -f "$packager" ]] || fail "0.6 stable DMG packager missing (expected RED before implementation)"
[[ "$(shasum -a 256 "$old" | awk '{print $1}')" == "$oldSha" ]] || fail '0.5 packager changed'
bash -n "$packager" || fail 'packager shell syntax'

# Audit literal release contract, including restrictions that negative fixtures cannot exercise.
for literal in \
  'com.nicozhuang.openmindflow' '0.6.0' 'check CFBundleVersion 7' \
  'OpenMindFlowReleaseVersion' 'OpenMindFlowReleaseTag' 'v0.6.0' \
  'OpenMindFlowReleaseChannel' 'stable' 'local.openmindflow.document' \
  'CFBundleTypeRole Editor' 'LSHandlerRank Owner' \
  '3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3' \
  'codesign --verify --deep --strict' '== adhoc' \
  'hdiutil verify "$dmg"' 'hdiutil attach -readonly -nobrowse' \
  '[[ "$(manifest "$mountpoint")" == "$stagedManifest" ]]' \
  'attached_image_device' 'detach_ours' \
  '^OpenMindFlow-Stable-0[.]6-[A-Za-z0-9][A-Za-z0-9._-]*[.]dmg$'; do
  /usr/bin/grep -Fq -- "$literal" "$packager" || fail "contract literal missing: $literal"
done

# Exercise the real embedded image-table parser with isolated read-only plist fixtures.
# No hdiutil attach/detach, diskutil calls, or image creation occurs: diskutil output
# is replaced only inside this fixture interpreter, not in the packager.
/usr/bin/python3 - "$packager" <<'PY'
import pathlib, plistlib, re, subprocess, sys

source = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r"  /usr/bin/python3 -c '\n(.*?)\n' \"\$dmg\" \"\$mountpoint\" < \"\$infoPlist\"", source, re.S)
if match is None:
    raise SystemExit('FAIL: embedded image parser not found')
parser = match.group(1)
image = '/private/tmp/openmindflow-local-Test/OpenMindFlow-Stable-0.6-test.dmg'
mountpoint = '/private/tmp/openmindflow-local-Test/.openmindflow-stable-0.6-verify-mount-Test'
whole = '/dev/disk6'
store = '/dev/disk6s1'
volume = '/dev/disk7s1'

def entity(device, mount=None):
    result = {'dev-entry': device}
    if mount is not None:
        result['mount-point'] = mount
    return result

def probe(name, entities, disks, expected_status, expected_device=''):
    table = plistlib.dumps({'images': [{'image-path': image, 'system-entities': entities}]})
    # Shadow diskutil only in this Python interpreter. Unexpected devices fail
    # closed, exactly as a real missing diskutil response would.
    prelude = '''import plistlib, subprocess
_real_check_output = subprocess.check_output
def _fixture_diskutil(args, **kwargs):
    if args[:3] != ['/usr/sbin/diskutil', 'info', '-plist'] or args[3] not in DISKS:
        raise subprocess.CalledProcessError(1, args)
    return plistlib.dumps(DISKS[args[3]])
subprocess.check_output = _fixture_diskutil
'''
    program = 'DISKS = ' + repr(disks) + '\n' + prelude + parser
    result = subprocess.run([sys.executable, '-c', program, image, mountpoint],
                            input=table, capture_output=True)
    if result.returncode != expected_status or result.stdout.decode().strip() != expected_device:
        raise SystemExit(f'FAIL: {name}: expected exit {expected_status}, device {expected_device!r}; '
                         f'got exit {result.returncode}, stdout {result.stdout!r}, stderr {result.stderr!r}')
    print(f'PASS: {name} parser fixture (exit {result.returncode})')

whole_info = {'DeviceNode': whole, 'WholeDisk': True, 'BusProtocol': 'Disk Image'}
physical_info = {'DeviceNode': store, 'ParentWholeDisk': 'disk6',
                 'APFSContainerReference': 'disk7', 'BusProtocol': 'Disk Image'}
volume_info = {'DeviceNode': volume, 'MountPoint': mountpoint, 'BusProtocol': 'Disk Image',
               'APFSContainerReference': 'disk7',
               'APFSPhysicalStores': [{'APFSPhysicalStore': 'disk6s1'}]}
probe('owned synthesized APFS volume',
      [entity(whole), entity(store), entity('/dev/disk7'), entity(volume, mountpoint)],
      {whole: whole_info, store: physical_info, volume: volume_info}, 0, volume)
probe('unrelated APFS physical store rejected',
      [entity(whole), entity(store), entity('/dev/disk7'), entity(volume, mountpoint)],
      {whole: whole_info, store: physical_info,
       volume: dict(volume_info, APFSPhysicalStores=[{'APFSPhysicalStore': 'disk9s1'}])}, 2)
probe('malformed APFS store rejected ambiguously',
      [entity(whole), entity(store), entity('/dev/disk7'), entity(volume, mountpoint)],
      {whole: whole_info, store: physical_info,
       volume: dict(volume_info, APFSPhysicalStores=['disk6s1'])}, 2)
probe('unrelated APFS container rejected',
      [entity(whole), entity(store), entity('/dev/disk7'), entity(volume, mountpoint)],
      {whole: whole_info, store: dict(physical_info, APFSContainerReference='disk9'),
       volume: volume_info}, 2)
probe('direct disk partition preserved',
      [entity(whole), entity(store, mountpoint)], {whole: whole_info}, 0, store)
PY

# Fixtures intentionally remain under this self-created private directory; never remove others' files.
fixture="$(mktemp -d /private/tmp/openmindflow-local-XXXXXXXX)"
[[ "$fixture" =~ ^/private/tmp/openmindflow-local-[A-Za-z0-9]+$ &&
   "$(cd "$fixture" && pwd -P)" == "$fixture" &&
   "$(stat -f %u "$fixture")" == "$(id -u)" && "$(stat -f %Lp "$fixture")" == 700 ]] || fail 'unsafe fixture'
app="$fixture/OpenMindFlow-Stable-0.6.app"
dmg="$fixture/OpenMindFlow-Stable-0.6-test.dmg"
# PATH shim records any hdiutil invocation; every case below must reject beforehand.
shim="$fixture/shim"; mkdir "$shim"
printf '#!/bin/bash\nprintf "called\\n" >> "%s"\nexit 96\n' "$fixture/hdiutil-calls" > "$shim/hdiutil"
chmod 700 "$shim/hdiutil"
expect_reject() {
  local name="$1" a="$2" d="$3" status=0
  PATH="$shim:$PATH" bash "$packager" "$a" "$d" > "$fixture/$name.stdout" 2> "$fixture/$name.stderr" || status=$?
  [[ "$status" != 0 ]] || fail "$name accepted"
  [[ ! -e "$fixture/hdiutil-calls" ]] || fail "$name reached hdiutil"
  printf 'PASS: %s rejected before hdiutil (exit %s)\n' "$name" "$status"
}
expect_reject nonexistent-app "$app" "$dmg"
mkdir "$fixture/OpenMindFlow-Other.app"
expect_reject wrong-app-name "$fixture/OpenMindFlow-Other.app" "$dmg"
mkdir "$app"
expect_reject malformed-dmg-name "$app" "$fixture/OpenMindFlow-Stable-0.6-.dmg"
ln -s "$fixture/nonexistent-image" "$dmg"
expect_reject symlink-dmg "$app" "$dmg"
expect_reject protected-path "$app" "/Applications/OpenMindFlow-Stable-0.6-test.dmg"
occupied="$fixture/OpenMindFlow-Stable-0.6-occupied.dmg"
: > "$occupied"
expect_reject occupied-dmg "$app" "$occupied"
other="$(mktemp -d /private/tmp/openmindflow-local-XXXXXXXX)"
[[ "$(cd "$other" && pwd -P)" == "$other" && "$(stat -f %Lp "$other")" == 700 ]] || fail 'unsafe second fixture'
expect_reject wrong-private-parent "$app" "$other/OpenMindFlow-Stable-0.6-test.dmg"
ln -s "$fixture/OpenMindFlow-Other.app" "$other/OpenMindFlow-Stable-0.6.app"
expect_reject symlink-app "$other/OpenMindFlow-Stable-0.6.app" "$other/OpenMindFlow-Stable-0.6-test.dmg"
ln -s "$fixture/OpenMindFlow-Other.app" "$app/nested-link"
expect_reject nested-app-symlink "$app" "$fixture/OpenMindFlow-Stable-0.6-nested.dmg"
chmod 755 "$fixture"
expect_reject non-private-parent "$app" "$dmg"
chmod 700 "$fixture"

# Evaluate actual packager functions without top-level packaging or physical disk calls.
function_fixture() {
  bash -c '
    set -euo pipefail
    packager="$1"; fixture="$2"; scenario="$3"
    eval "$(awk "$4" "$packager")"
    declare -F detach_ours cleanup >/dev/null || exit 94
    parent="$fixture"; parentIdentity="$(stat -f "%d:%i" "$parent")"
    stage="$(mktemp -d "$parent/.openmindflow-stable-0.6-dmg-stage-XXXXXXXX")"
    stageIdentity="$(stat -f "%d:%i" "$stage")"
    mountpoint="$(mktemp -d "$parent/.openmindflow-stable-0.6-verify-mount-XXXXXXXX")"
    mountDirectoryIdentity="$(stat -f "%d:%i" "$mountpoint")"
    mountIdentity="$mountDirectoryIdentity"
    dmg="$fixture/OpenMindFlow-Stable-0.6-test.dmg"
    attemptedAttach=1; ownDetached=0
    hdiutil() {
      if [[ "$1" == detach ]]; then printf "%s\n" "$2" >> "$fixture/detach-calls"; return 0; fi
      return 96
    }
    attached_image_device() { printf "%s\n" /dev/disk42; }
    case "$scenario" in
      unknown-device)
        mountDevice=""
        mount_is_ours() { [[ -n "$mountDevice" ]]; }
        ;;
      mismatched-device)
        mountDevice=/dev/disk41
        mount_is_ours() { return 0; }
        ;;
      replaced-mount)
        mountDevice=/dev/disk42
        mount_is_ours() { return 1; }
        ;;
      verified-own-device)
        mountDevice=/dev/disk42
        mount_is_ours() { return 0; }
        detach_ours || exit 95
        [[ "$(< "$fixture/detach-calls")" == /dev/disk42 ]] || exit 96
        exit 0
        ;;
      mount-failure)
        attemptedAttach=0; mountDevice=""
        mount() { return 95; }
        rm() { printf "rm called\n" >> "$fixture/remove-calls"; return 0; }
        rmdir() { printf "rmdir called\n" >> "$fixture/remove-calls"; return 0; }
        cleanup
        [[ -d "$stage" && -d "$mountpoint" && ! -e "$fixture/remove-calls" ]] || exit 91
        exit 0
        ;;
    esac
    detach_ours && exit 92
    [[ ! -e "$fixture/detach-calls" ]] || exit 93
  ' bash "$packager" "$fixture" "$1" '/^mount_is_ours\(\) \{/{copy=1} /^trap cleanup EXIT/{copy=0} copy' || { local status=$?; fail "$1 safety regression (fixture exit $status)"; }
  printf 'PASS: %s safety regression\n' "$1"
}
if [[ -n "${TASK91_SCENARIO:-}" ]]; then
  function_fixture "$TASK91_SCENARIO"
else
  function_fixture unknown-device
  function_fixture mismatched-device
  function_fixture replaced-mount
  function_fixture verified-own-device
  function_fixture mount-failure
fi
echo 'PASS: stable DMG negative safety tests; no DMG created'
