# MindMap First Release Implementation Plan

> **For agentic workers:** Execute checked steps with TDD and independent review; user authorized continuous implementation without approval pauses. This is the first of at most two user-facing releases, not a new third preview.

**Goal:** Ship a separately signed Mac preview with predictable node/branch drag, marquee/hand pan, safe arrangement, search, image nodes and PDF/PNG/JPG/Markdown export.

**Architecture:** Preserve `MapNode` and the existing `.mindmap.json` reader/writer, the v9 importer and the user's imported positions. `MapCanvas` owns one pointer gesture at a time; `MapModel` commits selected/subtree movement and explicit arrange as atomic Undo; exports render a separate map snapshot and never overwrite source. Image bytes are bounded and validated on read, write, paste and file import, saved in own JSON until video/package requirements in release two. The app's native window, menus and language settings remain AppKit.

**Tech Stack:** Swift 6.2/AppKit, Foundation and ImageIO (installed OS frameworks); existing no-framework `swiftc -D HEADLESS_TEST Sources/*.swift Tests/<Name>.swift -framework AppKit` checks, `bash build.sh`; no external dependency.

## Global Constraints

- Never write/rename/delete the original `.mindnode`, the authorized read-only copy, prior signed apps/zips or user preferences in synthetic tests; edits save only a distinct own file.
- Do not conflate offscreen AppKit tests with a visible/key/frontmost synthetic GUI; run an independent LaunchServices native GUI journey for gestures, panels, exports and window resizing.
- Preserve imported untouched coordinates, theme/colors, older JSON compatibility, user-edited titles and atomic Undo; explicit Arrange is the only action that discards saved positions, and can be undone.
- H selects persistent hand tool; V or Escape exits it to select; held middle button pans temporarily; while editing text these letters and Escape belong to the text editor.
- Separate final signed app/ZIP with unique bundle ID and verified code signature/archive bytes; no source format save in this release.

---

### Task 1: Gesture state and root/subtree drag

**Files:** `Sources/App.swift:840-1041`, `Sources/MapModel.swift:20-454`, `Tests/CanvasCommandTests.swift`, `Tests/MultiSelectCanvasTests.swift`, new `Tests/CanvasGestureTests.swift`.
**Interfaces:** Add `MapModel.selectNodes(_ ids: Set<UUID>) -> Bool`, `moveSelectedBy(_ delta: CGPoint, visibleCenters: [UUID: CGPoint]) -> Bool` or reuse existing `moveSelectedNodes` when it faithfully moves root descendants. `MapCanvas` owns select/hand state and delegates edits to one model transaction.

- [ ] Write synthetic NSEvent tests: drag a selected root and verify its descendant world centers change by exactly the same delta and Undo restores them; drag blank rectangle and select intersected nodes without moving `offset`; H then left-drag pans without moving model; V/Escape restores selection; middle-drag pans in either mode and restores previous mode; clicking a node selects before drag; text field receives H/V/Escape without tool switching.
- [ ] Run `swiftc -D HEADLESS_TEST Sources/*.swift Tests/CanvasGestureTests.swift -framework AppKit -o /tmp/mindmap-gesture-test && /tmp/mindmap-gesture-test`, confirm each added behavior fails for the intended reason.
- [ ] Implement one AppKit gesture discriminator in the existing mouse/key handlers: resize/plus hit first, then hand/middle pan, node drag, blank marquee. Threshold 4–9pt prevents clicks becoming drags; draw the marquee as an inset selection overlay and commit visible-frame intersections on release. Move positioned roots/descendants once in `MapModel`, preserve optional saved coordinates of unchanged nodes, and commit one Undo.
- [ ] Run the focused check and existing `CanvasCommandTests`, `MultiSelectCanvasTests`, `OutlineWorkbenchTests`; commit the scoped tested diff.

### Task 2: Startup sidebars and native window resizing

**Files:** `Sources/App.swift:1098-1130,1285-1334`, `Tests/OutlineWorkbenchTests.swift`, new `Tests/WindowResizeTests.swift`.
**Interfaces:** Shared `togglePane(at:)` must retain window/map-screen coordinates; both items start collapsed before the first content layout and the initial map fit follows the real final canvas size.

- [ ] Create an AppKit `NSWindow` with `AppDelegate.applicationDidFinishLaunching` or a synthetic attached split: assert both pane items collapsed at startup, 1280x700 requested content remains resizable and map center stable after each toggle. Separately verify minSize and `.resizable` style, actual visible frame and OS edge drag in the independent GUI journey; never infer drag availability from styleMask alone.
- [ ] Run the focused check RED for initial collapse; inspect measured screen/window geometry before changing resize behavior.
- [ ] Implement only the root-cause change, preserve the shared viewport-offset compensation from commit `e7b5310`; pass the focused test and six-toggle layout regression.

### Task 3: Explicit arrangement and global title search

**Files:** `Sources/MapModel.swift`, `Sources/App.swift` (menu/actions), new `Sources/MapSearch.swift`, `Tests/MapModelTests.swift`, `Tests/CanvasCommandTests.swift`, new `Tests/SearchTests.swift`.
**Interfaces:** `MapModel.arrange() -> Bool` computes `mapLayout(roots)` and assigns each node's center into one Undo snapshot; a context-menu item tagged separately invokes it only after commitEditing. `searchTitles(_ roots: [MapNode], query: String) -> [UUID]` returns visible/navigation-stable matches case/diacritic insensitive; `AppDelegate` owns a native non-modal search field bound to selected/reveal.

- [ ] RED: imported explicit locations do not change on ordinary open/resize; explicit Arrange repositions siblings with 24pt minimum gap and one Undo restores original centers; empty query does not select; search finds nested Chinese and Latin titles, moving to the chosen result without editing it.
- [ ] Implement tested functions with current `mapLayout`, stdlib `localizedStandardContains` or Foundation folding, no search library/extra layout engine; expose Arrange on blank canvas context menu and Find via ⌘F with a labeled native text field.
- [ ] Pass focused and existing import/JSON/menu tests, and add Chinese translations for new app-owned labels.

### Task 4: Safe image nodes and independent exports

**Files:** `Sources/MapModel.swift`, `Sources/OwnJSON.swift`, `Sources/Layout.swift`, `Sources/App.swift` media rendering/menus only, new `Sources/MapExport.swift`, new `Tests/ImageNodeTests.swift` and `Tests/MapExportTests.swift`.
**Interfaces:** An optional `MapNode` image payload carries validated image MIME/encoded bytes plus layout width/height; existing JSON without image still decodes identically. Image file/clipboard import validates OS-decodability, byte/pixel limits and allowed formats before altering model; double-click preserves the title editor above/below according to image-first visual layout. Export functions use a separate rendered snapshot to produce full-tree PNG/JPEG/PDF; `exportMarkdown(_ roots: [MapNode]) -> String` writes heading hierarchy (image links must be truthful or explicitly omitted with a warning).

- [ ] RED: import synthetic PNG from a test-owned URL and pasteboard, selected image scales within hard bounds; Undo and own-JSON save/reopen preserve title and image; invalid/oversized data leaves model and destination intact. Snapshot PNG/JPEG/PDF contain the whole map even when canvas is panned; Markdown headings are ordered and safely escape title whitespace. No test touches a user asset.
- [ ] Implement with Foundation/AppKit/ImageIO and native `NSSavePanel`; keep read-only `.mindnode` import behavior unchanged. Add an explicit error if document size limit is exceeded; never silently drop image bytes or destructively overwrite any source.
- [ ] Pass focused import/export tests, all old ownJSON tests, production build and a real native image import/render/export journey.

### Task 5: Integrate, verify and ship

**Files:** `README.md`, native GUI test in `Tests/`, release app/zip under ignored `dist/` only.

- [ ] Re-run every existing regression plus new gesture, window, search, image and export checks. `git diff --check`, `bash build.sh`, check prior signed ZIP hash remains untouched.
- [ ] Launch a separate synthetic GUI through LaunchServices and require visible/key/frontmost acceptance for initial collapsed panes, real window-edge resize, root/subtree/marquee/hand/middle input, Arrange/Undo, Find and image/export actions. If the desktop denies frontmost status, report it as unverified rather than passing offscreen checks.
- [ ] Sign a uniquely named `.app`, zip it, `codesign --verify --deep --strict`, `unzip -tq`, compare archived executable hash, open new signed app and confirm onscreen usable native window; never overwrite the old preview.
- [ ] Document results and release-two gaps (editable Bezier relationships, video with scrubber and original `.mindnode` write-back), commit only scoped source/tests/docs and present ZIP.
