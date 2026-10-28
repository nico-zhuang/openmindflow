#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd -P)"
builder="$repo/scripts/build-openmindflow-0.6-stable-local.sh"
appname=OpenMindFlow-Stable-0.6.app
fixtures=()
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
private_fixture() {
  local dir
  dir="$(mktemp -d /private/tmp/openmindflow-local-XXXXXXXX)"
  fixtures+=("$dir|$(stat -f '%d:%i' "$dir")")
  printf -v "$1" '%s' "$dir"
}
cleanup() {
  local fixture dir identity canonical
  for fixture in ${fixtures[@]+"${fixtures[@]}"}; do
    dir="${fixture%%|*}"
    identity="${fixture#*|}"
    [[ -d "$dir" && ! -L "$dir" && "$dir" =~ ^/private/tmp/openmindflow-local-[A-Za-z0-9!-]+$ ]] || continue
    canonical="$(cd "$dir" && pwd -P)"
    [[ "$canonical" == "$dir" && "$(stat -f %u "$dir")" == "$(id -u)" &&
       "$(stat -f '%d:%i' "$dir")" == "$identity" ]] || continue
    rm -rf -- "$dir"
  done
}
trap cleanup EXIT
reject() {
  local label="$1" target="$2" status output
  if output="$(bash "$builder" "$target" 2>&1)"; then
    fail "$label unexpectedly accepted: $target"
  else
    status=$?
  fi
  [[ "$status" == 2 ]] || fail "$label: expected refusal status 2; got $status: $output"
  printf 'PASS reject %s (exit %s)\n' "$label" "$status"
}

[[ -f "$builder" ]] || fail "missing stable builder: $builder"
bash -n "$builder" || fail 'stable builder bash syntax'
printf 'PASS builder bash -n\n'

# Every call below MUST reject before mkdir/compilation; never build production here.
private_fixture occupied
mkdir "$occupied/$appname"
printf 'existing sentinel\n' > "$occupied/$appname/sentinel"
reject existing-app "$occupied/$appname"
[[ "$(<"$occupied/$appname/sentinel")" == 'existing sentinel' ]] || fail 'existing output changed'

private_fixture linked
ln -s /private/tmp "$linked/$appname"
reject existing-app-symlink "$linked/$appname"
[[ -L "$linked/$appname" && "$(readlink "$linked/$appname")" == /private/tmp ]] || fail 'existing symlink changed'

private_fixture unprivate
chmod 755 "$unprivate"
reject non-0700-parent "$unprivate/$appname"
[[ ! -e "$unprivate/$appname" && ! -L "$unprivate/$appname" ]] || fail 'non-private parent gained output'

reject protected-path "/private/tmp/$appname"
[[ ! -e "/private/tmp/$appname" && ! -L "/private/tmp/$appname" ]] || fail 'protected target was occupied; inspect manually'

private_fixture invalid
reject wrong-basename "$invalid/OpenMindFlow-Stable-0.6-copy.app"
[[ ! -e "$invalid/OpenMindFlow-Stable-0.6-copy.app" ]] || fail 'wrong basename gained output'
invalid_token="$(mktemp -d '/private/tmp/openmindflow-local-bad!-XXXXXXXX')"
fixtures+=("$invalid_token|$(stat -f '%d:%i' "$invalid_token")")
reject invalid-parent-token "$invalid_token/$appname"
[[ ! -e "$invalid_token/$appname" && ! -L "$invalid_token/$appname" ]] || fail 'invalid token gained output'

# Inspect the literal here-doc; a production compilation is deliberately forbidden
# until final UI verification. Parse as a real plist rather than string matching XML.
python3 - "$builder" <<'PY'
import pathlib, plistlib, re, sys
source = pathlib.Path(sys.argv[1]).read_text()
assert '[[ "$parent" =~ ^/private/tmp/openmindflow-local-[A-Za-z0-9]+$ ]]' in source, 'strict parent regex absent'
for guard in ('-L "$parent"', '"$canonical" != "$parent"', 'stat -f %u "$parent"', 'stat -f %Lp "$parent"', '"$name" != OpenMindFlow-Stable-0.6.app', '-e "$app" || -L "$app"', 'mkdir "$app"'):
    assert guard in source, f'output safety guard missing: {guard}'
assert 'rm -' not in source, 'builder must never delete old or partial outputs'
assert 'swiftc Sources/*.swift -framework AppKit -framework AVKit -framework AVFoundation' in source
assert 'shasum -a 256 "$app/Contents/Resources/OpenMindFlow.icns"' in source
match = re.search(r'''^cat > "\$app/Contents/Info\.plist" <<'PLIST'\n(.*?)^PLIST$''', source, re.M | re.S)
assert match, 'literal Info.plist here-doc missing'
info = plistlib.loads(match.group(1).encode())
for key, value in {
    'CFBundleIdentifier': 'com.nicozhuang.openmindflow',
    'CFBundleVersion': '7',
    'CFBundleShortVersionString': '0.6.0',
    'OpenMindFlowReleaseVersion': '0.6.0',
    'OpenMindFlowReleaseTag': 'v0.6.0',
    'OpenMindFlowReleaseChannel': 'stable',
    'LSMinimumSystemVersion': '26.0',
}.items():
    assert info.get(key) == value, f'{key}: {info.get(key)!r} != {value!r}'
uti = info['UTExportedTypeDeclarations'][0]
assert uti['UTTypeIdentifier'] == 'local.openmindflow.document'
assert uti['UTTypeTagSpecification']['public.filename-extension'] == 'mflw'
assert info['CFBundleDocumentTypes'][0]['LSItemContentTypes'] == ['local.openmindflow.document']
assert info['CFBundleDocumentTypes'][0]['CFBundleTypeRole'] == 'Editor'
assert info['CFBundleDocumentTypes'][0]['LSHandlerRank'] == 'Owner'
assert '3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3' in source
assert 'codesign --sign - --timestamp=none "$app"' in source
assert 'codesign --verify --deep --strict --verbose=2 "$app"' in source
print('PASS parsed literal stable Info.plist, icon hash and ad-hoc signature checks')
PY

# Cleanup must not follow a pathname after its original directory has moved away.
private_fixture rotated
rotated_identity="$(stat -f '%d:%i' "$rotated")"
rotated_original="${rotated}-original"
[[ "$(cd "$rotated" && pwd -P)" == "$rotated" && ! -e "$rotated_original" && ! -L "$rotated_original" ]] || fail 'unsafe rotation fixture'
mv -- "$rotated" "$rotated_original"
mkdir "$rotated"
printf 'replacement sentinel\n' > "$rotated/replacement-sentinel"
[[ "$(stat -f '%d:%i' "$rotated")" != "$rotated_identity" ]] || fail 'replacement reused original inode'
cleanup
[[ ! -e "$invalid_token" && ! -L "$invalid_token" ]] || fail 'cleanup leaked its own invalid-token fixture'
[[ -f "$rotated/replacement-sentinel" ]] || fail 'cleanup removed a same-owner replacement directory'
printf 'PASS cleanup preserves replacement and removes only identified fixtures\n'
printf 'PASS StableBuildSafetyTests (no production app built)\n'
