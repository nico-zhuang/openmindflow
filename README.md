# MindMap (native editor prototype)

Build on macOS with Swift command-line tools: `bash build.sh`. Run with `open build/MindMap.app`.
No Xcode project, third-party dependencies, signing, or original application are required.

- A native toolbar is wired to the existing New Child, New Sibling, Fold/Unfold, Undo and Redo commands; its real-window button behavior is still unverified. The native Node menu exposes creation and detach commands. Tab: new child (or the first root when an opened map is empty); Return: new sibling; Option-Return: new sibling before; Option-Tab: insert a parent; Shift-Return: new main/root node. Ordinary sibling/parent insertion does nothing on roots (menu items are not yet disabled contextually).
- A native 180–320 pt outline sidebar shares the canvas tree, selected node, fold state and undo; View → Show/Hide Outline (Option-Command-S) collapses it. Selecting a row commits any active canvas edit first; successful document opens refresh the outline. Sidebar/menu behavior in a real window remains unverified.
- Type to edit the selected node through a native text field; double-click to replace its text, Escape to cancel editing. Chinese IME composition has not been verified in the final GUI build.
- Arrow keys: navigate visible nodes; Command-Up/Down: move the selected node among siblings; Command-Shift-D: detach the selected non-root node into a main/root node; Delete: remove a non-root node or an extra main root (the last root is protected); Option+period or Space: fold/unfold while the canvas has focus. While editing text, punctuation remains text input.
- Command-Z / Shift-Command-Z: model undo/redo. Drag empty canvas or the root to pan. Drag a **non-root** node at least 9 screen points to reveal a pointer-following ghost; only valid middle-of-node child drops or top/bottom sibling insertion show a target/line, and invalid drops leave the tree unchanged. Pinch or Option-scroll to zoom. These independent tree drop zones are not verified against MindNode; root reordering and free-position dragging are not implemented. Local NSEvent tests pass, but real-window mouse dragging still requires manual GUI confirmation.
- Drawn nodes appear as labeled, selected-state accessibility buttons; press one to select and edit using the native text field. Colors adapt to light/dark appearance.
- File → Open MindNode (Read-only)… (⌘O) imports supported `.mindnode` directory packages; File → Open Own JSON… opens `.mindmap.json` (a JSON array of roots). The MindNode picker keeps folders navigable, disables unrelated files and validates the selected directory package before accepting it; the package must contain a MindNode v9 binary plist. Only text, tree structure and fold state are copied; styling, notes and attachments are **not** round-tripped. The source package is never edited. Save prompts for a **new** `.mindmap.json` after an import, even if another JSON file was previously open; subsequent saves use that JSON destination. Save uses atomic writes; unsaved edits prompt before replacing a map, closing the only window, or quitting. Invalid packages show an alert without replacing the current editor. Empty JSON files or MindNode packages display an explicit no-nodes state. Confirmed window close quits the app; Cancel keeps the map open.

Run assertion tests:

```sh
swiftc Sources/MapModel.swift Tests/MapModelTests.swift -o /tmp/mindmap-model-tests && /tmp/mindmap-model-tests
swiftc Sources/MapModel.swift Sources/Layout.swift Tests/LayoutTests.swift -framework AppKit -o /tmp/mindmap-layout-tests && /tmp/mindmap-layout-tests
swiftc Sources/MapModel.swift Sources/OwnJSON.swift Tests/OwnJSONTests.swift -o /tmp/mindmap-ownjson-tests && /tmp/mindmap-ownjson-tests
swiftc Sources/MapModel.swift Sources/MindNodeImporter.swift Tests/MindNodeImporterTests.swift -o /tmp/mindmap-importer-tests && /tmp/mindmap-importer-tests
swiftc Sources/MapModel.swift Sources/MindNodeImporter.swift Sources/MindNodeTitlePatch.swift Sources/MindNodePackage.swift Tests/MindNodePackageTests.swift -o /tmp/mindmap-package-tests && /tmp/mindmap-package-tests # synthetic new-copy title/fold edit; not wired to Save
# /tmp/mindmap-package-tests --keep-fixture # explicitly retain one 0700 synthetic source/edited pair under owned dist/ for original-app inspection; manually remove after checking ownership
swiftc Sources/MapModel.swift Sources/MindNodeImporter.swift Sources/MindNodeTitlePatch.swift Tests/MindNodeTitlePatchTests.swift -o /tmp/mindmap-title-patch-tests && /tmp/mindmap-title-patch-tests # internal plist transform only; not wired to Save
swiftc -D HEADLESS_TEST Sources/*.swift Tests/CanvasCommandTests.swift -framework AppKit -o /tmp/mindmap-canvas-tests && /tmp/mindmap-canvas-tests
swiftc -D HEADLESS_TEST Sources/*.swift Tests/OutlineWorkbenchTests.swift -framework AppKit -o /tmp/mindmap-outline-tests && /tmp/mindmap-outline-tests
swiftc -D HEADLESS_TEST Sources/*.swift Tests/EditingJourney.swift -framework AppKit -o /tmp/mindmap-editing-journey && /tmp/mindmap-editing-journey
# Native open/save panels need manual file selection. Tests/OpenMindNodeGUI.swift cannot navigate them with PID-targeted events here;
# do not treat a timeout as GUI acceptance, and never replace it with global keyboard events.
# Tests/AppAccessibilityTests.swift --selection-refresh posts global events and is not part of the safe acceptance run.
```

G1 physical dragging, G2 native JSON picker, and G3 toolbar/sidebar real-window behavior still require manual acceptance; offscreen checks do not close those gates. The layout is independent, text-aware geometry (up to 320 pt wide per node), not the original artwork. Opening and saving own JSON is size/ID/path checked; document titles compare current content against the last saved tree, so undoing back to it clears the unsaved marker. `Tests/RenderFixedSample.swift` renders the same synthetic ten-node map without opening windows; `dist/mindmap-closure-before.png` and `dist/mindmap-closure-after.png` show the earlier and current canvas, not MindNode. `.mindnode` import remains **read-only**, with no original-format save or round-trip claim. The [gap baseline](docs/superpowers/specs/2026-10-20-mindmap-gap-baseline.md) and [read-only compatibility matrix](docs/superpowers/specs/2026-10-20-mindmap-readonly-compatibility.md) distinguish headless checks from GUI acceptance.
