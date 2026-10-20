# MindMap (native editor prototype)

Build on macOS with Swift command-line tools: `bash build.sh`. Run with `open build/MindMap.app`.
No Xcode project, third-party dependencies, signing, or original application are required.

- The native Node menu exposes implemented creation and detach commands. Tab: new child (or the first root when an opened map is empty); Return: new sibling; Option-Return: new sibling before; Option-Tab: insert a parent; Shift-Return: new main/root node. Ordinary sibling/parent insertion does nothing on roots (menu items are not yet disabled contextually).
- Type to edit the selected node through a native text field; double-click to replace its text, Escape to cancel editing. Chinese IME composition has not been verified in the final GUI build.
- Arrow keys: navigate visible nodes; Command-Up/Down: move the selected node among siblings; Command-Shift-D: detach the selected non-root node into a main/root node; Delete: remove a non-root node; Option+period or Space: fold/unfold while the canvas has focus. While editing text, punctuation remains text input.
- Command-Z / Shift-Command-Z: model undo/redo. Drag empty canvas space or scroll to pan; drag a node onto another node's middle to make it a child, or its top/bottom edge to reorder among siblings. Pinch or Option-scroll to zoom. Node drop zones are an independent approximation, not verified against MindNode's runtime; free-position dragging is not implemented.
- Drawn nodes appear as labeled, selected-state accessibility buttons; press one to select and edit using the native text field. Colors adapt to light/dark appearance.
- File → Open uses `.mindmap.json` (a JSON array of roots). File → Open MindNode (Read-only)… keeps folders navigable, disables unrelated files and validates a selected `.mindnode` directory package in the native picker before accepting it; the package must contain a MindNode v9 binary plist. Only text, tree structure and fold state are copied; styling, notes and attachments are **not** round-tripped. The source package is never edited. Save prompts for a **new** `.mindmap.json` after an import, even if another JSON file was previously open; subsequent saves use that JSON destination. Save uses atomic writes; unsaved edits prompt before replacing a map, closing the only window, or quitting. Invalid packages show an alert without replacing the current editor. Empty JSON files or MindNode packages display an explicit no-nodes state. Confirmed window close quits the app; Cancel keeps the map open.

Run assertion tests:

```sh
swiftc Sources/MapModel.swift Tests/MapModelTests.swift -o /tmp/mindmap-model-tests && /tmp/mindmap-model-tests
swiftc Sources/MapModel.swift Sources/Layout.swift Tests/LayoutTests.swift -o /tmp/mindmap-layout-tests && /tmp/mindmap-layout-tests
swiftc Sources/MapModel.swift Sources/MindNodeImporter.swift Tests/MindNodeImporterTests.swift -o /tmp/mindmap-importer-tests && /tmp/mindmap-importer-tests
swiftc -D HEADLESS_TEST Sources/*.swift Tests/CanvasCommandTests.swift -framework AppKit -o /tmp/mindmap-canvas-tests && /tmp/mindmap-canvas-tests
# With exactly one instance of our app launched and Accessibility permission:
# swift Tests/OpenMindNodeGUI.swift # synthetic package, prior JSON, invalid import, picker, warning, Save and SHA-256
# swift Tests/AppAccessibilityTests.swift
```

The layout is independent, fixed-size geometry; it does not reproduce original artwork or claim interaction parity with MindNode. This phase did not launch the GUI; the [gap baseline](docs/superpowers/specs/2026-10-20-mindmap-gap-baseline.md) and [read-only compatibility matrix](docs/superpowers/specs/2026-10-20-mindmap-readonly-compatibility.md) separate CLI evidence from unverified interface behavior.
