# MindMap Second Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development for independent files, then integrate in the Lead turn with focused RED→GREEN checks; the user explicitly authorized continuous second-version work.

**Goal:** Deliver the second and final user-facing release: structural marquee copy/paste, editable cross-node Bézier relationships, real video nodes, and separate `.mindnode` export.

**Architecture:** Keep existing native AppKit `MapCanvas`, `MapModel` Undo, and legacy `[MapNode]` own JSON. Introduce a versioned own-document envelope only when relationships/media metadata requires it, while retaining legacy reads. Never write or delete an original `.mindnode`; export to a new path atomically and verify by reopening the new copy. Clipboard snapshots store only maximal selected subtrees with fresh IDs on paste; relationships whose two endpoints are copied are remapped.

**Tech Stack:** Swift 6.2, AppKit, AVFoundation/AVKit, Foundation, ImageIO, macOS system frameworks only. Tests use `swiftc -D HEADLESS_TEST Sources/*.swift Tests/<Name>.swift -framework AppKit -o /tmp/<binary> && /tmp/<binary>` and independently launched visible/key/frontmost synthetic AppKit windows.

## Global Constraints

- The accepted first release is commit `956b6a5a664e00335cad91d0c660fbb52c3b4c8e`, private prerelease `v0.2.0-first-preview`. Develop on `feature/native-editor-v2`; do not overwrite any old signed app/ZIP, source `.mindnode`, or user files in tests.
- Changes to a model/document must be a single Undo step; failed validation must leave bytes, model, selection and history unchanged. Every new untrusted clipboard/file field is bounded and validated before mutation.
- Preserve legacy `.mindmap.json` root arrays and imported positions/fonts/styles. On write, reject or explicitly report any unsupported `.mindnode` media/relation field rather than silently omit it; never label synthetic importer round-trip as original-MindNode acceptance.
- Never mistake programmatic `NSWindow.setFrame` for a physical border-drag test. Image, video, connections and exported media need detached full-map rendering; Markdown must disclose media/relationship omissions.

---

**Progress (2026-10-25, `feature/native-editor-v2`, commits `4aec727` and `7c35f74`):** Structural clipboard paste, editable relationships, playable video, versioned own JSON, and a **limited experimental plain-tree** `.mindnode` writer are implemented. User-feedback fixes now include outline-sliding Bézier endpoints with no cross-node handle jump, straight first-child branches without tree collisions, blank-canvas commands, two real settings pages, and adaptive high-DPI PNG/JPG with unchanged vector PDF. The revised source passed 33 safe offscreen test groups and an isolated native executable build; the user's **currently running development app remains the older binary** and was not overwritten. This is **not** a second release: the writer rejects relationships/media/themes/rich titles instead of preserving them; original MindNode acceptance, a visible/key/frontmost synthetic journey, physical window-edge dragging, second signing and publication remain unverified or unfinished. The checkboxes below are acceptance criteria, not a claim that every subcase in an implemented feature was tested.

### Task 1: Relationship data, persistence and one-step Undo

**Files:** Create `Sources/MapRelationship.swift`, `Tests/MapRelationshipTests.swift`; modify `Sources/MapModel.swift`, `Sources/OwnJSON.swift`; add `Tests/OwnDocumentTests.swift`.

**Interfaces:** `MapRelationship(id:from:to:control1:control2:style:startArrow:endArrow:)`; `validRelationship(_:nodeIDs:)`; `relationshipGeometry(_:from:to:)`; `MapModel.relationships: [MapRelationship]`; `readOwnDocument(_:)` and `writeOwnDocument(_:to:)` preserving old `readOwnJSON(_:)`/`writeOwnJSON(_:)` wrappers.

- [ ] Write RED assertions: legacy arrays decode unchanged; new `roots+relationships` envelope reopens byte-valid; dangling endpoints, duplicate IDs, non-finite/out-of-range control offsets are rejected; add/edit/delete/style/arrow each commit one Undo with no-op preserving redo.
- [ ] Run `swiftc -D HEADLESS_TEST Sources/*.swift Tests/OwnDocumentTests.swift -framework AppKit -o /tmp/mindmap-own-v2 && /tmp/mindmap-own-v2`; confirm missing envelope/relation methods cause RED.
- [x] Add the minimum document encoder/decoder and extend `MapModel.Snapshot` to include relationships; `fitsSavedJSON` must measure the exact new envelope when relationships exist, else preserve legacy array bytes. Verify `Tests/MapRelationshipTests.swift` and `Tests/OwnDocumentTests.swift` GREEN.

### Task 2: Structural clipboard group copy/paste and native commands

**Files:** Modify `Sources/MapModel.swift`, `Sources/App.swift`, `Sources/Localization.swift`; create `Tests/MapClipboardTests.swift` and `Tests/ClipboardCanvasTests.swift`.

**Interfaces:** `MapModel.copySelection(visibleCenters:) -> MapSelectionClip?` returns only topmost selected subtrees plus in-group relationship edges. `MapModel.pasteSelection(_:at:) -> Bool` gives every cloned node/relationship a new UUID, shifts saved coordinates to the requested blank-canvas world anchor, appends cloned roots, and selects the cloned group. `MapCanvas.copy(_:)` writes a bounded private `NSPasteboard` type; `paste(_:)` prioritizes this type over image/text and uses the last blank click/context-menu location.

- [ ] Write RED cases for a selected root+selected child+unselected descendant (one complete subtree only), selected siblings without their parent (two independent cloned roots), in-group edge ID remap, outside edge omission, media bytes retained, malformed/oversized clipboard refusal, repeated pastes with distinct IDs, one Undo/Redo and original data unchanged.
- [ ] Run `swiftc -D HEADLESS_TEST Sources/*.swift Tests/MapClipboardTests.swift -framework AppKit -o /tmp/mindmap-clipboard-v2 && /tmp/mindmap-clipboard-v2`, then implement the smallest model transaction until GREEN.
- [ ] Route native Edit → Copy/Paste and blank-canvas right-click through the existing responder chain; ensure focused title editor still copies/pastes text. Run `Tests/ClipboardCanvasTests.swift` GREEN with actual NSEvent marquee and named NSPasteboard.

### Task 3: Editable curve UI and full-map exports

**Files:** Modify `Sources/App.swift`, `Sources/MapExport.swift`, `Sources/Localization.swift`; create `Tests/RelationshipCanvasTests.swift`.

**Interfaces:** canvas context menu creates a relationship between two selected nodes; selected curve exposes two draggable control handles; native menu changes solid/dashed/dotted and toggles arrow at either endpoint. Export `MapCanvas` snapshot carries relationships so PDF/PNG/JPG draw same curves and arrowheads.

- [ ] Write RED synthetic NSEvent checks: curve creation selects only valid distinct endpoints; moving each control point changes the visible Bézier path and one Undo restores it; changing line style and either arrow survives Save→Open and full-map PNG includes curved pixels.
- [ ] Run `swiftc -D HEADLESS_TEST Sources/*.swift Tests/RelationshipCanvasTests.swift -framework AppKit -o /tmp/mindmap-curves-v2 && /tmp/mindmap-curves-v2`; implement using `NSBezierPath` and existing model/Undo until GREEN. Do not alter tree parent-child connector semantics.

### Task 4: Real video node and media export boundary

**Files:** Create `Sources/MapVideo.swift`, `Tests/MapVideoTests.swift`; modify `Sources/MapModel.swift`, `Sources/Layout.swift`, `Sources/App.swift`, `Sources/OwnJSON.swift`, `Sources/MapExport.swift`; create `Tests/VideoCanvasTests.swift`.

**Interfaces:** `MapVideo(data:) throws` validates an actual playable local MOV/MP4/M4V with AVFoundation; `MapVideoPlayerView(video:)` wraps AVKit native play/pause/scrub/progress. One node contains either image or video and an optional editable title below; the selected media corner resizes proportionally; input is bounded and remains playable after `.mindmap.json` Save→Open without depending on the original file path.

- [ ] Write RED cases using an `AVAssetWriter`-generated tiny synthetic movie: add, scale, title, save/reopen, playback progression and seek; reject damaged/oversized and avoid leaking temporary files. A source file must remain byte-identical after import.
- [ ] Run `swiftc -D HEADLESS_TEST Sources/*.swift Tests/VideoCanvasTests.swift -framework AppKit -o /tmp/mindmap-video-v2 && /tmp/mindmap-video-v2`; integrate native File/clipboard input and AVKit playback without relying on source paths. Report any explicit media-size ceiling to the user; do not claim unrestricted video.

### Task 5: Separate `.mindnode` writing with honest round-trip

**Files:** Create `Sources/MindNodeWriter.swift`, `Tests/MindNodeWriterTests.swift`; modify `Sources/App.swift`, `Sources/Localization.swift`; extend `Tests/MapExportTests.swift` only if shared UI menu tests require it.

**Interfaces:** `MindNodeWriter.writeNewCopy(..., to: URL) throws` (exact argument list fixed against v9 importer/parser fields), never overwrites a destination or writes inside an existing `.mindnode`. File → Export MindNode… uses `NSSavePanel` and leaves the editing document in `.mindmap.json`; writer must preserve relationship, image, and video fields in a format the original MindNode can reopen; until this is independently verified, such fields throw explicit errors rather than writing a deceptively incomplete map, and the second release remains incomplete.

- [ ] Write RED fixture checks for synthetic v9 full node tree, IDs, titles, folds, location, font/width/styles and a no-overwrite package; compare source and old preview byte hashes before/after; reimport the newly exported file via `MindNodeImporter.loadDetailed` and check fields exactly.
- [ ] Run `swiftc -D HEADLESS_TEST Sources/*.swift Tests/MindNodeWriterTests.swift -framework AppKit -o /tmp/mindmap-mindnode-writer && /tmp/mindmap-mindnode-writer`; implement safe new-copy writer and native action, disclose any fields not verifiably encoded in v9.

### Task 6: Regression, native GUI and final version delivery

**Files:** Create `Tests/SecondReleaseVisibleJourney.swift` and a unique owned-bundle runner; update `README.md` with actual limitations.

- [x] Re-run the first release's 24 focused groups plus new model/clipboard/relationship/video/writer tests, `bash build.sh`, `git diff --check` (33 safe offscreen groups passed; this does not cover the two focus-stealing GUI suites).
- [ ] Launch a **new owned signed synthetic App** via LaunchServices and require visible/key/frontmost status for marquee→Copy→blank Paste/Undo, Bezier control drag/line style/arrows, playable video/progress, and new `.mindnode` Save dialog without touching user originals. If desktop focus shifts, stop global-input tests and mark them unverified.
- [ ] Sign a **unique second** app/ZIP; check `codesign --verify --deep --strict`, `unzip -tq`, executable identity and both prior ZIP hashes; open the new app. Commit only scoped source/tests/docs and publish a private second prerelease after validation. Do not declare original-MindNode compatibility without independent original-app round-trip evidence.
