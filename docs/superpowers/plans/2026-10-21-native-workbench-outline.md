# Native MindMap Outline Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a collapsible native outline beside the existing canvas, with the *same* selected tree, editing commits, fold/undo state and dirty status.

**Architecture:** `MapCanvas.model` remains the only mutable map. A new AppKit `NSOutlineView` renders disposable UUID-backed row snapshots from that model; row selection invokes one canvas selection method (which commits the old text field first). A standard `NSSplitViewController` hosts outline and canvas; the existing AppDelegate menu, toolbar, JSON and read-only import paths stay in place.

**Tech Stack:** Swift/AppKit `NSOutlineView`, `NSScrollView`, `NSSplitViewController`, `NSTextField`; existing assertion executables, no packages.

## Global Constraints

- This G3 slice depends on the toolbar commit `777dd62` but is independent code preparation while the G1 real-pointer and G2 native-picker gates wait. **Do not mark G1/G2/G3 complete** on headless evidence.
- `.mindnode` remains read-only; Save writes only own JSON. Never open original app/private files, interact with unknown PID `73855`, inject global events or presume synthetic GUI state.
- Never create a second mutable map or style model. `MapNode` serialization and undo snapshot format must stay unchanged. Reuse `MapCanvas.toggleFold()` and AppKit controls.
- Editing an old canvas node followed by outline selection must commit the old title **before** changing `model.selected`; selection alone must not mark dirty or add undo history. Programmatic outline reload/expansion must not toggle model fold.
- One failing then passing focused assertion per branch, all README headless commands, `bash build.sh`, code review. Offscreen AppKit tests do **not** prove physical mouse/menu accessibility.

---

### Task 1: Shared canvas selection and non-mutating selection callback

**Files:** Modify `Sources/App.swift:14-27,65-72`; extend `Tests/CanvasCommandTests.swift` or add `Tests/OutlineWorkbenchTests.swift` with `@main`.

**Interface:** Add `MapCanvas.onSelectionChange: (() -> Void)?` and `MapCanvas.selectNode(_ id: UUID)`; call the callback only when `announcedSelection` actually changes inside the existing `needsDisplay.didSet` accessibility branch. `selectNode` calls `commitEditing()` *before* touching `model.selected`, rejects IDs absent from `visibleNodes()`, reveals selection, redraws and does **not** call `onChange`. `selectAndEdit` may reuse `selectNode` and then `beginEditing()`.

- [x] RED: create a synthetic root+child, `selectAndEdit(root.id)`, type `Old title` into its existing native text field, then call `canvas.selectNode(child.id)`. Assert `roots[0].title == "Old title"`, `model.selected == child.id`, `onChange` ran once for the rename and `onSelectionChange` once for the new selection; calling `selectNode(child.id)` again must not add a second notification. Run `swiftc -D HEADLESS_TEST Sources/*.swift Tests/OutlineWorkbenchTests.swift -framework AppKit -o /tmp/mindmap-outline-tests && /tmp/mindmap-outline-tests`; expect compile failure for missing `selectNode`.
- [x] GREEN: implement the exact interface above, using the existing `needsDisplay.didSet` AX-change branch rather than touching every keyboard/mouse call site. Run the focused command and existing canvas command test; expect both PASS. Commit only this source/test pair after `git diff --check`.

### Task 2: One native outline that reflects canvas state

**Files:** Create `Sources/MapOutlineView.swift`; extend `Tests/OutlineWorkbenchTests.swift`.

**Interface:** `final class MapOutlineView: NSScrollView, NSOutlineViewDataSource, NSOutlineViewDelegate` with `init(canvas: MapCanvas)`, internal `let outlineView: NSOutlineView`, `func reloadMap()`, `func syncSelection()`. Build NSObject row wrappers from `canvas.model.roots` containing immutable node UUID/title/folded and children, not a second mutable map. `NSOutlineView` supplies native disclosure/keyboard/AX; the text cell shows `title.isEmpty ? "New idea" : title`, is a noneditable `NSTextField(labelWithString:)`, and exposes the full title as tooltip. `syncSelection` selects the visible row matching `canvas.model.selected`, without causing a model write. `reloadMap` rebuilds rows, expands only nodes with `folded == false`, then syncs selection; suppress programmatic selection/expansion callbacks while doing so.

- [ ] RED: create root→child→grandchild and a sibling with distinct UUIDs, instantiate `MapOutlineView(canvas:)` without starting an app window. Assert initial outline row count 4, selected row matches root, and selecting the child row commits an actively edited root title before changing selection; pure row selection must not increase `onChange`. Trigger `canvas.toggleFold()` with a parent selected and then `reloadMap()`; assert its descendants disappear from rows and `undo()` plus `reloadMap()` restores them. Run the focused command above; expect compile failure for missing `MapOutlineView`.
- [ ] GREEN: implement `NSOutlineViewDataSource` using the read-only wrappers for child counts/items/expandability; implement `outlineViewSelectionDidChange` by capturing row UUID first, then invoking `canvas.selectNode(id)`, then restoring keyboard focus to the outline if a window exists (canvas text commit currently makes itself first responder). In `outlineView(_:shouldExpandItem:)` / `shouldCollapseItem`, allow expansion during `reloadMap`; for a user action select the row, invoke `canvas.toggleFold()` only when its immutable folded state differs from the requested new state, and return `false` so `reloadMap` renders the authoritative model. Reuse native system font/colors; set outline accessibility label `Map outline`.
- [ ] VERIFY: focused test + `CanvasCommandTests` pass; 30-node synthetic sample row count is correct, leaf disclosure does not create undo. `git diff --check`; commit only new source + focused test.

### Task 3: Embed outline and preserve document behavior

**Files:** Modify `Sources/App.swift:362-385,424-464,511-551`, existing `Tests/CanvasCommandTests.swift`, `Tests/OutlineWorkbenchTests.swift`; documentation `README.md` after code review.

**Interface:** In `AppDelegate`, retain one `MapOutlineView` and one `NSSplitViewController`. Use `NSSplitViewItem(sidebarWithViewController:)` with a 180–320pt collapsible sidebar and `NSSplitViewItem(viewController:)` for the current canvas. Attach the split as `window.contentViewController`; keep `window.makeFirstResponder(canvas)` at initial launch. Link `canvas.onChange` to *both* existing `syncDirty()` and `outline.reloadMap()`, `canvas.onSelectionChange` to `outline.syncSelection()`. After each successful JSON/MindNode document replacement explicitly reload outline; do not reload on failure/cancel. Add a native View menu `Show/Hide Outline` targeting `splitController.toggleSidebar(_:)` (Option-Command-S), rather than a custom drawer. Preserve every existing File/Node/Edit shortcut and save prompt.

- [ ] RED: headless workbench test constructs a split controller with root+child through the production builder (do not launch a visible app), asserts first item is collapsible sidebar, second item's view is the **same** canvas instance, and toggling the sidebar changes no roots. Existing `CanvasCommandTests` menu assertion must include `View` and its single outline toggle command. Expect missing builder or menu on initial compile/run.
- [ ] GREEN: wire the AppDelegate integration only; menu and split contain no tree mutation. Ensure 640pt minimum window width still leaves room for canvas and native text editor. On JSON and `.mindnode` open success, call `outline.reloadMap()` after `canvas.model` assignment. Avoid new file IO code or introducing style fields.
- [ ] VERIFY: focused test, all README headless commands, `bash build.sh`, `git diff --check`. If another same-bundle window or PID has unknown state, do not launch another GUI or mark narrow-width/VoiceOver/real drag acceptance passed. Commit this scoped integration, then update taskbook G3 as **code built; GUI gate pending**.
