# MindMap (native editor prototype)

Build on macOS with Swift command-line tools: `bash build.sh`. Run with `open build/MindMap.app`.
No Xcode project, third-party dependencies, signing, or original application are required.

- Tab: new child; Return: new sibling (roots cannot have a new sibling via this model).
- Type to edit the selected node through the native text input editor (including Chinese IME); double-click to replace its text, Escape to cancel editing.
- Arrow keys: navigate visible nodes; Delete: remove a non-root node; Shift+period or Space: fold/unfold while the canvas has focus. While editing text, Shift+period types punctuation instead.
- Command-Z / Shift-Command-Z: model undo/redo. Drag the canvas or scroll to pan; pinch or Option-scroll to zoom.
- Drawn nodes appear as labeled, selected-state accessibility buttons; press one to select and edit using the native text field. Colors adapt to light/dark appearance.
- File → Open uses `.mindmap.json` (a JSON array of roots). File → Open MindNode (Read-only)… keeps folders navigable, disables unrelated files and validates a selected `.mindnode` directory package in the native picker before accepting it; the package must contain a MindNode v9 binary plist. Only text, tree structure and fold state are copied; styling, notes and attachments are **not** round-tripped. The source package is never edited. Save prompts for a **new** `.mindmap.json` after an import, even if another JSON file was previously open; subsequent saves use that JSON destination. Save uses atomic writes; unsaved edits prompt before replacing a map, closing the only window, or quitting. Invalid packages show an alert without replacing the current editor. Empty JSON files or MindNode packages display an explicit no-nodes state. Confirmed window close quits the app; Cancel keeps the map open.

Run assertion tests:

```sh
swiftc Sources/MapModel.swift Tests/MapModelTests.swift -o /tmp/mindmap-model-tests && /tmp/mindmap-model-tests
swiftc Sources/MapModel.swift Sources/Layout.swift Tests/LayoutTests.swift -o /tmp/mindmap-layout-tests && /tmp/mindmap-layout-tests
swiftc Sources/MapModel.swift Sources/MindNodeImporter.swift Tests/MindNodeImporterTests.swift -o /tmp/mindmap-importer-tests && /tmp/mindmap-importer-tests
# With exactly one instance of our app launched and Accessibility permission:
# swift Tests/OpenMindNodeGUI.swift # synthetic package, prior JSON, invalid import, picker, warning, Save and SHA-256
# swift Tests/AppAccessibilityTests.swift
```

The layout is independent, fixed-size geometry; it does not reproduce original artwork or claim interaction parity with MindNode.
