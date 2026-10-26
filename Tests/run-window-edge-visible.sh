#!/bin/bash
# Visible synthetic journey; NEVER run while another app owns the desktop.
# The executable performs the Finder/HID/trust gate before any NSApplication or AppDelegate use,
# then repeats it immediately before AppDelegate's window ordering/activation.
set -euo pipefail
cd "$(dirname "$0")/.."
base="$(mktemp -d /tmp/mindmap-window-edge-visible-XXXXXXXX)"
base="$(realpath "$base")"
[[ "$base" == /private/tmp/mindmap-window-edge-visible-* ]] || { echo 'SKIP 77: unsafe temporary directory'; exit 77; }
chmod 700 "$base"
exe="$base/WindowEdgeDragJourney"
swiftc -D HEADLESS_TEST Sources/*.swift Tests/WindowEdgeDragJourney.swift \
  -framework AppKit -framework AVKit -framework AVFoundation -framework IOKit -o "$exe"
# The preflight executable does not create NSApp or a window, or request trust.
"$exe" --preflight || exit "$?"
# Hard stop if AppKit's native tracking loop does not terminate; never leave a synthetic drag running.
perl -e 'alarm 15; exec @ARGV' "$exe"
