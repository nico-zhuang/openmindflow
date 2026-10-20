# Unified MindMap Open Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `File → Open…` safely selects both own `.mindmap.json` and supported v9 directory `.mindnode`, without relaxing existing read-only/source-isolation rules.

**Architecture:** Reuse `MindNodeImporter.load(_:)` and AppDelegate's existing selection/saving path. Replace the separate `Open MindNode (Read-only)…` menu with one `Open…` entry whose picker explains v9 read-only import; route both formats through that entry and commit import only after parsing succeeds. Preserve prior map, selected UUID, fileURL and dirty state on error or user cancellation.

**Tech Stack:** Swift 6.2.1, Foundation, AppKit, current `bash build.sh`, assertion tests; no new dependencies.

## Global Constraints

- Original `/Applications/MindNode.app` and authorized `.mindnode` packages are read-only; no writes or private title logging.
- Only v9 directory packages with bounded binary-plist `contents.xml` are accepted by the current importer; unsupported variants show an explicit error.
- MindNode import remains lossy (title/tree/fold only); Save only writes a new `.mindmap.json` file. No `.mindnode` writer in this gate.
- Do not replace the currently installed MindMap or loop GUI windows; one bounded synthetic fixture test when safe.

---

### Task 1: Open panel accepts both formats without accepting unrelated files

**Files:** Modify `Sources/App.swift:356-404`; extend `Tests/CanvasCommandTests.swift` with a native panel-delegate check.

**Interfaces:** `AppDelegate.panel(_:shouldEnable:)` and `panel(_:validate:)` are already the picker trust boundary. JSON destination must have last component ending `.mindmap.json`; original import must have `.mindnode` extension and be a directory.

- [ ] Write a failing assertion with one newly created temporary JSON, one synthetic `.mindnode` directory and one unrelated regular file: the delegate enables both valid inputs, disables unrelated regular files, and rejects selection of an ordinary directory. Use ownership-marked temp cleanup as `Tests/MindNodeImporterTests.swift` already does; never operate on a user's folder.
- [ ] Run `swiftc -D HEADLESS_TEST Sources/*.swift Tests/CanvasCommandTests.swift -framework AppKit -o /tmp/mindmap-canvas-tests && /tmp/mindmap-canvas-tests`; expected assertion failure for JSON being disabled by the current delegate.
- [ ] In `Sources/App.swift`, change only panel enable/validate logic: enable every directory for navigation and regular files with `.mindmap.json` suffix; validate only selectable `.mindmap.json` regular file or `.mindnode` directory. Remove `panel.allowedContentTypes = [.json]` from the unified `Open…` panel; set `canChooseFiles = true`, `canChooseDirectories = true`, `delegate = self`. Remove the dedicated import menu item/handler and add `panel.message = "Open .mindmap.json or import a MindNode v9 directory package read-only."` so there is one validated path.
- [ ] Re-run the headless test and `bash build.sh`; expected all assertions pass and build exit 0.

### Task 2: Preserve replacement prompts and independent save targets

**Files:** Modify `Sources/App.swift:356-393`; extend `Tests/OpenMindNodeGUI.swift` only after headless route proof and before bounded GUI run.

**Interfaces:** `MindNodeImporter.load(_:) throws -> [MapNode]`; `canvas.model`, `fileURL`, `dirty`, `updateTitle()`, `confirmDiscardOrSave()`. Parse import before replacing current model; JSON opens retain their own URL, MindNode opens clear it and retain the loss warning.

- [ ] Add a failing bounded synthetic GUI check that the **same File → Open… menu** can open an existing JSON and then a synthetic v9 package; invalid package leaves previous map selected; importing asks for a fresh `.mindmap.json` on Save; SHA-256 of package files unchanged. Reuse fixture and AX helpers already in `Tests/OpenMindNodeGUI.swift`; do not add a second launch loop.
- [ ] Inline the existing `openMindNode(_:)` import branch into the unified `openFile(_:)` handler and remove the unused handler/menu item rather than adding a helper. Move state assignment only after importer succeeds and `confirmDiscardOrSave()` returns true; keep `fileURL = nil`, `dirty = false`, the explicit partial-import warning, and window focus. Ordinary JSON Open still guards unsaved changes before replacing the map.
- [ ] Run four headless test commands in `README.md`, `bash build.sh`, `plutil -lint build/MindMap.app/Contents/Info.plist`, `git diff --check`; all exit 0. Perform exactly one synthetic GUI run **only with one independent App instance, Accessibility permission and explicit temporary test fixtures**; otherwise record GUI gate not met rather than claim success.
- [ ] Commit only source, tests and docs. Preserve `dist/` archives, current installed app, original app and authorized packages; do not ship `.mindnode` writeback in this task.

## Reviewer stop line

If the single Open panel cannot both navigate directories and select JSON on this host's UTType behavior, retain separate entries and make the default Open present explicit format guidance; do not loosen importer file validation to make the picker look successful. A build/headless pass cannot substitute for visible picker/IME validation.

**执行记录**：混合面板的 AX 合成测试看到 JSON 文件但始终未能使 Open 启用；无法证明是产品拒绝还是 AX 脚本未选中列表项。按停线退回双入口：⌘O 的 `Open MindNode (Read-only)…` 与 `Open Own JSON…`；四组无窗口断言及构建通过，当前新版尚未完成有界 GUI 复测。只有 GUI 复测通过才关闭阶段 0。
