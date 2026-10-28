# Task 1 — OpenMindFlow 0.6 adaptive tab strip

**Status: DONE_WITH_CONCERNS** — scoped implementation and tests pass against the committed `ReleaseChecker.swift` snapshot; the concurrently edited shared checker API presently prevents a normal `Sources/*.swift` compile. Leave board task-86 **in progress** until Lead review; no commit or staging.

## Scope and behavior

- Changed `Sources/DocumentTabStrip.swift`: `draw(_:)` now fills the strip opaquely with appearance-resolved neutral (`windowBackgroundColor` blended 11% toward `labelColor`) and paints a one-point canvas-side separator (38% blend); horizontal bottom edge, vertical right edge. Both operations precede the existing drag insertion-preview guard and preserve the preview overlay and separate selected-row highlight. Canvas color, drag/transfer logic and models are untouched.
- Created `Tests/TabStripSurfaceTests.swift`: `NSApplication.shared.setActivationPolicy(.prohibited)`; no activation, ordering, global AX/HID, screen capture, or user window. Synthetic offscreen AppKit bitmap checks Aqua/Dark Aqua × horizontal/vertical: alpha > 0.99 without prefilling opaque color, RGB distance > 0.06 from appearance-resolved window background, opaque edge differing > 0.08, and adjacent non-edge pixel within 0.015 of interior. A separate unshown-window session verifies the selected title/button state and selected-row accent bitmap in both layouts and appearances.

## RED evidence

First compile after test creation, before editing production source:

```sh
swiftc -D HEADLESS_TEST Sources/*.swift Tests/TabStripSurfaceTests.swift -framework AppKit -framework AVKit -framework AVFoundation -o /tmp/openmindflow-task86-strip-red && /tmp/openmindflow-task86-strip-red
```

**Exit 133**, stderr `main/TabStripSurfaceTests.swift:43: Assertion failed: horizontal NSAppearanceNameAqua: undropped tab strip must paint opaque`. The test compiled successfully; existing `Sources/MapVideo.swift` AVFoundation deprecation warnings were emitted. After switching test appearance handling to nondeprecated `performAsCurrentDrawingAppearance`, concurrent edits to `Sources/ReleaseChecker.swift` introduced a temporary `App.swift:3331` compile mismatch (`missing argument for parameter 'channel'`). A test closure type error was corrected; final independent RED command below compiled against the committed checker snapshot to isolate Task 1 from concurrent API edits:

```sh
scratch=$(mktemp -d /tmp/omf-task86-red-XXXXXX) && git show HEAD:Sources/ReleaseChecker.swift > "$scratch/ReleaseChecker.swift" && files=(); for file in Sources/*.swift; do if [ "$file" != Sources/ReleaseChecker.swift ]; then files+=("$file"); fi; done; swiftc -D HEADLESS_TEST "${files[@]}" "$scratch/ReleaseChecker.swift" Tests/TabStripSurfaceTests.swift -framework AppKit -framework AVKit -framework AVFoundation -o "$scratch/strip-red" && "$scratch/strip-red"
```

**Exit 133**; same missing-background assertion, with no test compilation errors. The scratch file lives outside the repository; no other implementer's files were altered.

## GREEN evidence

Initial focused GREEN exposed a test-only flipped-coordinate error: bitmap row zero maps to direct drawing's high Y; the horizontal separator at strip `bounds.maxY - 1` was incorrectly sampled at bitmap row `height - 1`. Corrected samples to bitmap rows 0 (edge) and 1 (interior); production code unchanged. Final focused command (the optional render directory was used for visual inspection):

```sh
scratch=$(mktemp -d /tmp/omf-task86-render-XXXXXX) && git show HEAD:Sources/ReleaseChecker.swift > "$scratch/ReleaseChecker.swift" && files=(); for file in Sources/*.swift; do if [ "$file" != Sources/ReleaseChecker.swift ]; then files+=("$file"); fi; done; swiftc -D HEADLESS_TEST "${files[@]}" "$scratch/ReleaseChecker.swift" Tests/TabStripSurfaceTests.swift -framework AppKit -framework AVKit -framework AVFoundation -o "$scratch/strip-green" 2> "$scratch/compile.log" && OMF_TABSTRIP_RENDER_DIR="$scratch" "$scratch/strip-green" && echo "render directory: $scratch" && echo "compiler warning count: $(grep -c 'warning:' "$scratch/compile.log" || true)"
```

**Exit 0**, stdout `opaque Aqua/Dark Aqua strip surfaces, canvas edges and selected title highlights passed`; four PNGs at `/tmp/omf-task86-render-PYvVlu/{horizontal,vertical}-NSAppearanceName{Aqua,DarkAqua}.png` rendered and inspected; all show uniform neutral surfaces with a visible one-pixel canvas edge. **14** existing AVFoundation deprecation warning lines, none from scoped files.

Adjacent-suite command:

```sh
scratch=$(mktemp -d /tmp/omf-task86-adjacent-XXXXXX) && git show HEAD:Sources/ReleaseChecker.swift > "$scratch/ReleaseChecker.swift" && files=(); for file in Sources/*.swift; do if [ "$file" != Sources/ReleaseChecker.swift ]; then files+=("$file"); fi; done; for suite in TabChromeInteractionTests DocumentTabStripTests TabDragSignalTests DocumentTabTransferTests; do echo "=== $suite ==="; swiftc -D HEADLESS_TEST "${files[@]}" "$scratch/ReleaseChecker.swift" "Tests/$suite.swift" -framework AppKit -framework AVKit -framework AVFoundation -o "$scratch/$suite" 2> "$scratch/$suite.compile.log" || { echo "COMPILE FAILED $suite"; tail -30 "$scratch/$suite.compile.log"; exit 1; }; "$scratch/$suite" || { echo "TEST FAILED $suite"; exit 1; }; echo "PASS $suite (compiler warnings: $(grep -c 'warning:' "$scratch/$suite.compile.log" || true))"; done
```

**Exit 0**. `TabChromeInteractionTests`: `offscreen inline edit, persistent close AX, selected state and vertical geometry passed; physical pointer/VoiceOver unverified` (20 existing warnings); `DocumentTabStripTests`: `horizontal/vertical layout, viewport anchor, tab identity, editor rejection, plus and menu bindings passed` (14); `TabDragSignalTests`: `offscreen token-only drag, dequeued-release gate, cancel, destination and tearoff passed; physical production drag not tested` (14); `DocumentTabTransferTests`: `transactional reorder, transfer rollback, identity, private bytes and last-tab close passed` (14).

## Caveats and handoff

- Whole-tree compile with **current** concurrent `ReleaseChecker.swift` exits **1** at `Sources/App.swift:3331` because new `check(currentVersion:channel:completion:)` signature is not yet adopted in `App.swift`; Lead was notified immediately. Rerun all five suites against actual shared `Sources/*.swift` once the API integration lands. The committed checker snapshot is used for verification only and is not a proposed product change.
- Synthetic bitmap surfaces and separate selected-row accent tests do not substitute for human GUI review, native window composite with titles, or physical drag/VoiceOver inspection. No app activation or existing user `.mindnode` was touched.
- Only `Sources/DocumentTabStrip.swift`, `Tests/TabStripSurfaceTests.swift`, and this report are Task 1 edits. Board claim requested from Lead because this delegated session exposes no board-task tool/CLI. No stage/commit performed; Lead should review, integrate, and mark task-86 complete afterward.

## Reviewer Important gap — hierarchy-render TDD addendum

The initial tests at lines above exercised `strip.draw`/`row.draw` separately. Those were not evidence for the actual composited flipped view hierarchy or legible native button glyphs. Replaced `Tests/TabStripSurfaceTests.swift` with an unshown real `NSWindow` fixture (`makeUnshownWindowSession`, two tabs), using `strip.cacheDisplay(in:to:)` to traverse the **attached strip → rows → title buttons**. `NSApp` activation remains `.prohibited`; fixture stays unshown, never ordered/key/activated; no desktop screenshot, AX or HID. Both Aqua/Dark Aqua × horizontal/vertical are tested at native window backing scale and independently at explicit 1x. Assertions compare composited selected/unselected row-interior colors, detect drawn glyph pixels in **both** title rectangles against their row backgrounds, and sample the **outermost canvas-side pixel** against its immediate neighbor and opposite side. A row is unflipped although its parent strip is flipped, so the test uses row frames in strip coordinates rather than a misleading point conversion. Optional diagnostic PNGs are generated only when `OMF_TABSTRIP_RENDER_DIR` is specified.

**RED (mutation verification, private 0700 scratch only):** removed the strip separator fill from a private copy of `DocumentTabStrip.swift`; same hierarchy test exited **133**, `horizontal NSAppearanceNameAqua: canvas-side separator must occupy outermost pixel`. Separately removed the private copy's selected-row accent fill/stroke; test exited **133**, `horizontal NSAppearanceNameAqua: selected highlight must differ from unselected strip`. These mutations never touched repository production files. The first unmutated hierarchy draft also failed with `selected title glyphs ... (0 pixels)` due to the test's wrong row-to-strip point conversion; corrected the test coordinate mapping before GREEN. No production bug was proven; `Sources/DocumentTabStrip.swift` was **not changed** in this addendum.

**GREEN:** compiled a private snapshot of all sources, substituting committed `App.swift` and `ReleaseChecker.swift` while concurrent Settings edits were incomplete. The hierarchy suite exited **0** at native and explicit 1x, all four appearance/orientation images rendered, 14 existing `MapVideo.swift` AVFoundation deprecation-warning lines. Inspected `hierarchy-vertical-NSAppearanceNameDarkAqua.png`: both native titles, selected-row accent, and right canvas edge are visible. Subsequently compiled **current** `Sources/*.swift` copied into another private 0700 directory, without committed substitutions, and ran the same suite: **exit 0**, `unshown NSWindow hierarchy: Aqua/Dark, both orientations, selected/unselected glyphs and canvas edges passed` (14 existing warning lines). Thus the earlier shared-App/checker compile caveat in this report is historical, **no longer pending for this focused suite**. Adjacent suites reported earlier used committed checker and were not rerun against current source in this addendum. Human GUI and physical drag/VoiceOver remain unverified. No staging or commit.
