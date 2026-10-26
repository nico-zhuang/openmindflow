# MindMap Hand-Test Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct the four 2026-10-26 user-observed failures: note indicator, physical window resizing, full-size real theme cards, and left-hand root branches.

**Architecture:** Continue Swift 6.2/AppKit with `MapModel` snapshot Undo, `MapCanvas` rendering, `StyleInspector` cards, `InspectorTheme` data. Keep original root/branch location and custom style precedence; add only optional side state for first-level branches and validated theme IDs. Integrate `App.swift` sequentially after disjoint model/inspector work.

**Tech Stack:** Swift 6.2, AppKit, AVKit/AVFoundation, no third-party dependencies, `.mindmap.json` only for own edits.

## Global Constraints

- Baseline `c83b30c` (`feature/native-editor-v2`); user's running `build/MindMap-Feedback-20261026.app` and first signed ZIP are protected, as are originals, Downloads and original MindNode windows.
- Exactly Style / Notes / Themes; no Tags. Existing three theme IDs, legacy JSON, signed preview and original `.mindnode` imports remain valid/read-only.
- Use `swiftc -D HEADLESS_TEST Sources/*.swift Tests/NAME.swift -framework AppKit -framework AVKit -framework AVFoundation -o /tmp/UNIQUE && /tmp/UNIQUE` for focused tests; 33 safe groups exclude `AppAccessibilityTests.swift` and `WindowResizeTests.swift` (can focus windows).
- Finder frontmost and HID idle ≥180 seconds gate visible synthetic GUI; native edge drag cannot be claimed from `window.setFrame` alone. No user-window automation, second official signing, push or merge.

---

### Task 1: Note Indicator

**Files:** Modify `Sources/App.swift` (`MapCanvas.draw`, `accessibilityElement` labels), test `Tests/NoteIndicatorTests.swift` (new), add necessary localizations in `Sources/Localization.swift` only if new visible text. App.swift changes only when no other task edits it.

**Interfaces:** Consume `MapNode.note: String?`, `MapCanvas.visibleNodes()` and `MapCanvas.screen(_:)`; produce painted icon for `note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false` without storing icon state.

- [ ] **Step 1 — RED**: Add a synthetic model with one noted child and one empty-note child; render to bitmap with the same offscreen `NSBitmapImageRep` pattern as `Tests/RelationshipCanvasTests.swift`, then assert noted glyph region differs but empty-note region does not. Change the note through `MapModel.setNote`, Undo/Redo, compare paint and accessibility labels.
- [ ] **Step 2 — Run RED**: `swiftc -D HEADLESS_TEST Sources/*.swift Tests/NoteIndicatorTests.swift -framework AppKit -framework AVKit -framework AVFoundation -o /tmp/mindmap-note-red && /tmp/mindmap-note-red`; expected nonzero at missing indicator assertion, not compiler failure.
- [ ] **Step 3 — GREEN**: In `MapCanvas.draw`, after drawing node title, guard `let text = item.node.note?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty` and draw a 12pt paper-outline with two short lines beside label, using `NSColor.controlAccentColor` on dark/light backgrounds; reserve gap past line end for child and inside root content edge for roots. In AX node label, append localized “Has note” without revealing note text.
- [ ] **Step 4 — Verify**: Run the exact focused command above with a new `/tmp/mindmap-note-green` path, then `Tests/MapExportTests.swift` focused; icon must not leak note text. `git diff --check`, commit only scoped files.

### Task 2: Native Window Edge Resize Diagnosis

**Files:** Test `Tests/WindowResizeTests.swift` (existing GUI-only) and a guarded synthetic harness `Tests/run-window-edge-visible.sh` if needed; modify `Sources/App.swift` only for a reproduced hit-test/constraint defect.

**Interfaces:** Consume AppDelegate's `NSWindow` with `.resizable`, min size 640×400, `NSSplitViewController`; produce actual `window.frame` change after a native edge drag without moving content or changing world positions.

- [ ] **Step 1 — RED diagnosis**: Existing `Tests/WindowResizeTests.swift:39–69` verifies programmatic `setFrame` only. Add a guarded physical edge-drag journey that records frame before and after a bottom-right native drag inside own synthetic window; check frontmost Finder and ≥180-second HID idle *before* creating or activating the fixture, and skip with exit 77 otherwise. Inspect hit-testing and constraints if the frame does not change.
- [ ] **Step 2 — Execute guarded journey once**: `bash Tests/run-window-edge-visible.sh`; expected PASS if `resized.width > before.width && resized.height > before.height`, or SKIP 77 without focus changes. A failure is evidence to fix the specific AppKit/toolbar/view constraint; a skip is not a pass and must be reported as unverified physical gesture.
- [ ] **Step 3 — GREEN if reproduced**: Fix only the confirmed cause in window setup/split constraints; preserve `.resizable`, 640×400 min, normal title bar, and pane-toggle viewport compensation. Re-run the journey under the same gate plus existing window test when safe; `git diff --check` then commit only relevant files. If synthetic drag passes but user's gesture remains unreproduced, do not add a speculative resize handle: record the difference and keep user hand-test gate open.

### Task 3: Large Theme Cards and Eight Real Themes

**Files:** Modify `Sources/InspectorTheme.swift`, `Sources/StyleInspector.swift`, `Sources/Localization.swift` (labels for new themes), `Sources/MapModel.swift` (`setTheme` currently hardcodes three IDs), `Sources/OwnJSON.swift`, and `Sources/App.swift` only in the later integration pass; test `Tests/StyleInspectorTests.swift`, `Tests/OwnDocumentTests.swift`, plus new focused visual theme test if existing one cannot compare fills and actual pixels.

**Interfaces:** `InspectorTheme: String, CaseIterable` gains eight lowercase raw IDs `vintage`, `greyscale`, `teal`, `slate`, `blackberry`, `blackboard`, `coffee`, `swing` and scoped palette properties for root fill, branch colors, document background and contrasting title color. Existing three raw IDs/colors unchanged. `OwnJSON` theme validation reads `InspectorTheme(rawValue: value) != nil` rather than a three-string hardcoded list.

- [ ] **Step 1 — RED**: Extend focused tests to assert `InspectorTheme.allCases.count == 11`, all 11 cards have distinct accessible labels, preview image width tracks 260–320pt inspector content (not fixed 196pt), preview area occupies most of the card, names use secondary smaller font, all cards scroll. Round-trip each ID through `OwnMapDocument`, assert Undo; sample real canvas bitmap after theme change so backdrop/root/branch changes match palette and custom node style remains stronger.
- [ ] **Step 2 — Run RED**: `swiftc -D HEADLESS_TEST Sources/*.swift Tests/StyleInspectorTests.swift -framework AppKit -framework AVKit -framework AVFoundation -o /tmp/mindmap-themes-red && /tmp/mindmap-themes-red`; expected failure at card count/size. Run `Tests/OwnDocumentTests.swift` similarly for ID validation.
- [ ] **Step 3 — GREEN**: Change `InspectorTheme` palette metadata, make `StyleInspector.themeButtons` width follow themeScroll content, draw proportional previews containing background, center root, lines and subnodes (do not paste screenshots), put subdued ~12pt title beneath image with selected outline. Make `MapCanvas` consume theme background/title palette while retaining explicitly set node colors and imported presentation precedence. Replace both `MapModel.setTheme` and `OwnJSON.checkOwnDocument` hardcoded three-ID guards with the same `InspectorTheme(rawValue:)` validation; old JSON with no theme still uses native appearance.
- [ ] **Step 4 — Verify**: Rerun focused inspector, JSON, export, localization tests; compare detached PNG pixels and card aspect under narrow/wide pane. `git diff --check` and commit; no `Tags` icon/page.

### Task 4: Persistent Left-Hand Root Branches

**Files:** Modify `Sources/MapModel.swift` (optional first-level side + setter with single snapshot), `Sources/Layout.swift` (mirror left subtree and avoid overlap), `Sources/OwnJSON.swift` (strict optional enum validation), `Sources/MindNodeWriter.swift` (reject loss of unsupported left-branch orientation if writer cannot faithfully encode it), `Sources/App.swift` (left/right tree line geometry, underline, drag drop/command), focused tests `Tests/LayoutTests.swift`, `Tests/OwnDocumentTests.swift`, `Tests/MindNodeWriterTests.swift`, `Tests/CanvasGestureTests.swift` and new `Tests/LeftBranchTests.swift` if necessary.

**Interfaces:** Add `MapNode.branchSide: String? = nil` only for root children (`"left"` or `"right"`; missing means right). Provide `MapModel.setRootBranchSide(_ side: String, for id: UUID) -> Bool`; rejects non-first-level IDs/invalid values, snapshots once, keeps children in same subtree. `mapLayout` places descendants according to root-child direction; explicitly saved/imported positions remain authoritative until the user requests a side change.

- [ ] **Step 1 — RED**: Assert one root with mixed sides yields `leftChild.frame.maxX < root.frame.minX`, `rightChild.frame.minX > root.frame.maxX`, left grandchild lies farther left; draw two-sided parent curves meeting near root left/right and child underline, not crossing root. Assert `setRootBranchSide` one Undo, JSON read/write old missing side defaults right and rejects invalid strings. Drag a right root child to root's left on canvas and expect persisted left, restore right by drag/context menu.
- [ ] **Step 2 — Run RED**: `swiftc -D HEADLESS_TEST Sources/*.swift Tests/LeftBranchTests.swift -framework AppKit -framework AVKit -framework AVFoundation -o /tmp/mindmap-left-red && /tmp/mindmap-left-red`; expected failure at new side behavior. Use existing `Tests/LayoutTests.swift` and `Tests/CanvasGestureTests.swift` only as focused regression, not glob all tests.
- [ ] **Step 3 — GREEN**: Layout left subtree in mirrored depth columns while keeping right default, root and explicitly imported world coordinates stable. In `MapCanvas.draw` determine side by child/root ancestry and route connector/underline in that direction; let root-child drag decide side at release from pointer vs root center and expose left/right action in existing node context menu. Call one model setter for one Undo, then recompute nodes. Existing manual free-node coordinates and copied subtree locations require a deliberate side switch before mirroring. Experimental `MindNodeWriter` must either encode the left position accurately with a round-trip or reject `branchSide == "left"` before writing with an explicit unsupported-style error, never silently export a right-only tree.
- [ ] **Step 4 — Verify**: Focused layout/model/canvas/JSON/export tests at a new `/tmp` path, `git diff --check`, commit. Document tradeoff if protected importer positions prevent drag auto-placement; no source `.mindnode` mutation.

### Task 5: Integration, Review, Safe GUI and Distinct Candidate

**Files:** Modify `README.md` only for verified status, new separate app `build/MindMap-Handtest-20261026-Next.app` (ensure absent first); tests run from current `Sources/*.swift`.

**Interfaces:** Depends on Tasks 1–4. No user-owned app process is closed or overwritten; first ZIP SHA-256 remains `1dd50186df560cf84d418b9ca8e975d8ed75ebbc952f989e8a5140583e3891eb`.

- [ ] **Step 1 — Independent review**: A different reviewer checks each scoped diff against design; fix Important findings via focused RED→GREEN, re-review. Review App.swift final cross-effects (native import, model replacement, panel target, selected relationship, left drag).
- [ ] **Step 2 — Safe matrix**: Explicitly run the prior 33 safe offscreen groups at normal priority (omit AX and WindowResize); record count and exit, rerun any changed test after source stabilizes. A failure is not a pass.
- [ ] **Step 3 — Isolated visible synthetic tests**: Run Finder+180-second-idle gated journeys once. Report PASS/SKIP/FAIL separately; no interaction with live app or original MindNode.
- [ ] **Step 4 — Candidate**: Verify resolved absolute new `.app` path absent; compile sources with `swiftc Sources/*.swift -framework AppKit -framework AVKit -framework AVFoundation -o <NEW_APP>/Contents/MacOS/MindMap`, create unique bundle ID, `plutil -lint`, inspect linker-ad-hoc signature vs release signing. Do not launch the user's next app unless explicitly requested or desktop gate allows safe automation.
- [ ] **Step 5 — Final integrity**: Verify old app bundle/hash/first ZIP hash, git clean and branch unpushed; update README with exact verified status and any physical-edge/visual/original-app limits. Deliver a separate link, not a second signed release claim.
