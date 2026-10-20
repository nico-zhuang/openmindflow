# MindMap (native editor prototype)

Build on macOS with Swift command-line tools: `bash build.sh`. Run with `open build/MindMap.app`.
No Xcode project, third-party dependencies, signing, or original application are required.

- Tab: new child; Return: new sibling (roots cannot have a new sibling via this model).
- Type to edit the selected node through the native text input editor (including Chinese IME); double-click to replace its text, Escape to cancel editing.
- Arrow keys: navigate visible nodes; Delete: remove a non-root node; Shift+period or Space: fold/unfold while the canvas has focus. While editing text, Shift+period types punctuation instead.
- Command-Z / Shift-Command-Z: model undo/redo. Drag the canvas or scroll to pan; pinch or Option-scroll to zoom.
- Drawn nodes appear as labeled, selected-state accessibility buttons; press one to select and edit using the native text field. Colors adapt to light/dark appearance.
- File → Open/Save use **only** `.mindmap.json` (a JSON array of roots). The original `.mindnode` format is not supported or overwritten. Save uses atomic writes; unsaved edits prompt before opening another file, closing the only window, or quitting. Confirmed window close quits the app; Cancel keeps the map open. An empty JSON array opens as an empty state.

Run assertion tests:

```sh
swiftc Sources/MapModel.swift Tests/MapModelTests.swift -o /tmp/mindmap-model-tests && /tmp/mindmap-model-tests
swiftc Sources/MapModel.swift Sources/Layout.swift Tests/LayoutTests.swift -o /tmp/mindmap-layout-tests && /tmp/mindmap-layout-tests
# With exactly one instance of our app launched: swift Tests/AppAccessibilityTests.swift
```

The layout is independent, fixed-size geometry; it does not reproduce original artwork or claim interaction parity with MindNode.
