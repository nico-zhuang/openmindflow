# Native MindMap Workbench Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first useful native window control layer so common node edits, folding and undo/redo are visibly discoverable without hiding the canvas or replacing keyboard shortcuts.

**Architecture:** Attach one standard `NSToolbar` to the existing `NSWindow` and route every item to the *same* AppDelegate command methods already used by the native menus. Only the existing canvas/model may mutate the tree. Keep the full outline sidebar as the next independent G3 slice; toolbar alone does not complete G3.

**Tech Stack:** Swift, AppKit `NSToolbar`, existing `MapCanvas`/`MapModel`, assertion-style `swiftc` tests; no dependency or new persistence field.

## Global Constraints

- Existing taskbook G1 physical mouse and G2 own-JSON panel GUI gates remain **unverified**. This independent G3 implementation may run while manual GUI actions wait, but G3 may not be marked accepted until prior gates and sidebar are complete.
- `.mindnode` remains read-only import; Save only writes own `.mindmap.json`. No original app, user maps, unknown PID `73855`, global CGEvents, or private window inspection.
- Native platform toolbar, labels and accessibility descriptions; no custom visual controls, theme tokens, persisted style model, animation framework, or toolbar logic duplicated from menu actions.
- Failure/undo safeguards and active text-field commit retain existing behavior. Do not create a button which edits the wrong selected node or steals an unfinished title without committing.
- Each branch requires one real failing assertion, subsequent pass, all README headless commands and `bash build.sh`; local AppKit checks are not real mouse acceptance.

---

### Task 1: Expose a shared fold action and standard toolbar

**Files:** Modify `Sources/App.swift` (`MapCanvas` editing commands, `AppDelegate.applicationDidFinishLaunching`, command selectors and toolbar delegate conformance); extend `Tests/CanvasCommandTests.swift` or create `Tests/WorkbenchToolbarTests.swift` if the latter makes the run simpler.

**Interfaces:** `MapCanvas.toggleFold()` reuses `model.toggleFold()` and `changed()` after `commitEditing()`; both existing keyboard fold keys call it. `AppDelegate` conforms to `NSToolbarDelegate`, `makeToolbar() -> NSToolbar` returns the native toolbar, and `toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)` produces only New Child, New Sibling, Fold/Unfold, Undo and Redo. Item targets point to existing selectors `newChild(_:)`, `newSibling(_:)`, `undoEdit(_:)`, `redoEdit(_:)`; fold target calls `canvas.toggleFold()` once. Identifiers/labels are stable: `new-child` / `New Child`, `new-sibling` / `New Sibling`, `fold-node` / `Fold/Unfold`, `undo` / `Undo`, `redo` / `Redo`.

- [x] **RED:** Before changing production code, add this assertion to the existing `CanvasCommandTests` after its menu assertions (or in `WorkbenchToolbarTests` with `@main`):

```swift
let toolbarDelegate = AppDelegate()
let toolbar = toolbarDelegate.makeToolbar()
let expected = ["new-child", "new-sibling", "fold-node", "undo", "redo"]
let items = toolbarDelegate.toolbarDefaultItemIdentifiers(toolbar)
    .filter { $0 != .flexibleSpace }
assert(items.map(\.rawValue) == expected)
let actions = ["newChild:", "newSibling:", "foldNode:", "undoEdit:", "redoEdit:"]
for (id, action) in zip(items, actions) {
    let item = toolbarDelegate.toolbar(toolbar, itemForItemIdentifier: id, willBeInsertedIntoToolbar: true)!
    assert(item.target as AnyObject? === toolbarDelegate)
    assert(item.action.map(NSStringFromSelector) == action)
    assert(!item.label.isEmpty && !item.toolTip.isEmpty)
}
```

Run `swiftc -D HEADLESS_TEST Sources/*.swift Tests/CanvasCommandTests.swift -framework AppKit -o /tmp/mindmap-toolbar-tests && /tmp/mindmap-toolbar-tests`; expect missing `makeToolbar` compile failure (if separate test file, use that filename). Add a focused canvas assertion that `toggleFold()` on a parent changes folded state once and Undo restores it, while a leaf fold is a no-op; old code fails to compile without `MapCanvas.toggleFold()`.

- [x] **GREEN:** Add `func toggleFold() { commitEditing(); if model.toggleFold() { changed() } }` to `MapCanvas`, route Space/Option-period through it, and add `@objc private func foldNode(_ sender: Any?) { canvas.toggleFold() }` to AppDelegate. Add `NSToolbarDelegate` conformance and `makeToolbar()` with `NSToolbar(identifier: "MindMap")`, `toolbar.delegate = self`, `toolbar.displayMode = .iconAndLabel`, return toolbar. Supply exact default/allowed identifiers from the test (add `.flexibleSpace` only between node actions and undo/redo), create each native `NSToolbarItem` with its test label, a system-symbol image when available (`plus`, `arrow.turn.down.right`, `chevron.right`, `arrow.uturn.backward`, `arrow.uturn.forward`), readable `toolTip`, exact existing selector target/action, no duplicate mutation logic. In `applicationDidFinishLaunching`, attach `window.toolbar = makeToolbar()` after constructing the window and before showing it.

- [x] **VERIFY:** Run the focused check, full commands listed in `README.md`, `bash build.sh`, `git diff --check`; confirm toolbar button actions do not touch file loading/saving paths and all standard menu shortcuts stay unchanged. Commit only the named source/test files.

### Task 2: Bound acceptance honestly

**Files:** Update `README.md` with the exact toolbar controls and evidence status. Add one taskbook progress note without checking G1/G2/G3 complete.

- [ ] With a **new** owned synthetic app only if no unknown other same-bundle process is active, check toolbar items exist and one item changes the expected tree through bound AX; if safe isolation is unavailable, report this as GUI toolbar **unverified**, not as success. Do not interact with old PID `73855` or read its window.
- [ ] If there is no safe GUI window, deliver the compiled app and headless menu/toolbar wiring evidence with the same explicit manual gate. The G3 sidebar and visual comparison remain future tasks; do not describe this as a complete MindNode-level interface.
