# Visible Tree Drag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make existing non-root tree moves visibly draggable in the independent MindMap window, with an honest drop preview and one undoable commit.

**Architecture:** Preserve `MapModel` as the sole owner of tree mutations; expose its existing move guard as a side-effect-free `canMoveNode` and reuse it for commits and previews. `MapCanvas` owns transient pointer state and drawing only; root/empty-area drags pan the viewport, never mutate saved tree coordinates.

**Tech Stack:** Swift, Foundation, AppKit, `swiftc` and existing assertion executables; no new package/dependency or original application.

## Global Constraints

- Modify only independent `mindnode-reconstruction/`; keep the existing untracked `dist/` content and any user-owned process untouched.
- `.mindnode` remains read-only v9 directory import; GUI Save only writes `.mindmap.json`; never inspect user/private maps or original app/license data.
- No global CGEvents or unverified XPC PID. Headless NSEvent method calls prove local behavior, **not** live GUI behavior.
- No saved free-position coordinates, root reorder or change to existing JSON schema. Root drags pan the whole viewport; only non-root nodes can reparent/reorder.
- Drag start after at least 9 screen points; no edit on invalid/cancel; after a valid release exactly one model change/undo step.
- Require a red then green runnable check for each nontrivial code change, full existing headless suite, build, and separate bounded owned-GUI acceptance.

---

### Task 1: Share the model's move-validity guard

**Files:** Modify `Sources/MapModel.swift:81-98`; extend `Tests/MapModelTests.swift` near its existing move tests.

**Interfaces:** Produce `func canMoveNode(_ id: UUID, to parentID: UUID, at index: Int) -> Bool`. `moveNode(_:to:at:)` must call this same predicate before `save()`; both reject root/self/descendant/out-of-range/identity move. Query must not change roots, selection or undo/redo.

- [x] **RED:** Add this concrete case to the existing move assertions:

```swift
let a = UUID(), b = UUID(), c = UUID()
let previewModel = MapModel(roots: [MapNode(id: a, title: "Root", children: [
    MapNode(id: b, title: "Source", children: [], folded: false),
    MapNode(id: c, title: "Target", children: [], folded: false)
], folded: false)], selected: b)
let unchanged = previewModel.roots
assert(previewModel.canMoveNode(b, to: c, at: 0))
assert(!previewModel.canMoveNode(a, to: c, at: 0))
assert(!previewModel.canMoveNode(b, to: b, at: 0))
assert(!previewModel.canMoveNode(b, to: a, at: 1)) // Same location.
assert(previewModel.roots == unchanged)
previewModel.undo() // A validity query must not add undo history.
assert(previewModel.roots == unchanged)
```

Run: `swiftc Sources/MapModel.swift Tests/MapModelTests.swift -o /tmp/mindmap-model-tests && /tmp/mindmap-model-tests`. Expected RED: missing `canMoveNode` compile failure.

- [x] **GREEN:** Move the guards that currently start `moveNode` into this pure method, then call it from `moveNode`:

```swift
func canMoveNode(_ id: UUID, to parentID: UUID, at index: Int) -> Bool {
    guard let source = Self.path(to: id, in: roots), source.count > 1,
          let target = Self.path(to: parentID, in: roots),
          !target.starts(with: source),
          (0...Self.node(at: target[...], in: roots).children.count).contains(index) else { return false }
    let sameParent = source.dropLast().elementsEqual(target)
    let destination = index - (sameParent && source.last! < index ? 1 : 0)
    return !sameParent || destination != source.last!
}

func moveNode(_ id: UUID, to parentID: UUID, at index: Int) -> Bool {
    guard canMoveNode(id, to: parentID, at: index) else { return false }
    let sourcePath = Self.path(to: id, in: roots)!
    let targetPath = Self.path(to: parentID, in: roots)!
    let sameParent = sourcePath.dropLast().elementsEqual(targetPath)
    let destinationIndex = index - (sameParent && sourcePath.last! < index ? 1 : 0)
    let moving = Self.node(at: sourcePath[...], in: roots)
    save()
    Self.edit(&roots, at: sourcePath[...]) { nodes, position in nodes.remove(at: position) }
    let updatedParentPath = Self.path(to: parentID, in: roots)!
    Self.edit(&roots, at: updatedParentPath[...]) { nodes, position in
        nodes[position].folded = false
        nodes[position].children.insert(moving, at: destinationIndex)
    }
    return true
}
```

- [x] **VERIFY & COMMIT:** Re-run the focused command (expected `model tests passed`), then `git diff --check`; commit only the two named files.

### Task 2: Pointer-following ghost and truthful drop preview

**Files:** Modify `Sources/App.swift:27-35,89-130,255-289`; extend `Tests/CanvasCommandTests.swift` (existing local drag cases). `Layout.swift`'s `dropPlacement` remains the one geometric zone rule.

**Interfaces:** `MapCanvas` owns press anchor, grab offset, active pointer, and one shared `validDrop(at:source:nodes:) -> (target: LaidOutNode, parent: UUID, index: Int)?` that calls `dropPlacement` **and** `model.canMoveNode`. The same result drives both drawing and release. Render the source as a translucent rounded rectangle under the pointer, preserving the point at which it was grabbed; valid child drops outline their target, valid before/after drops show a horizontal insertion line. Do not highlight an invalid target.

- [x] **RED:** Extend `CanvasCommandTests.swift` after its existing `dragCanvas` case. Use the existing `mouse(_:_:)` local-event helper, create a non-root source and destination, then assert: a movement under 9 pt changes neither the tree nor the visual image; a >9 pt move into *blank* canvas draws a ghost but does not mutate the tree; releasing on blank preserves undo/redo; a move onto a valid target leaves roots unchanged until `mouseUp`, then changes once and `undo()` restores the exact prior roots. To verify drawing, render the headless `MapCanvas` into `NSBitmapImageRep` via `NSGraphicsContext(bitmapImageRep:)` + `displayIgnoringOpacity(_:in:)` **after mouse-down** (so selection styling is the same) and during whitespace drag; compare PNG bytes. Old code fails at whitespace-ghost assertion. Add a root-grab local drag that pans its rendered position but does not dirty the tree. The existing valid center and edge drops remain regressions.

Run: `swiftc -D HEADLESS_TEST Sources/*.swift Tests/CanvasCommandTests.swift -framework AppKit -o /tmp/mindmap-canvas-tests && /tmp/mindmap-canvas-tests`. Expected RED: the current draw has no whitespace ghost and root drag does not pan.

- [x] **GREEN — transient gesture contract:** Keep `dragSource` and `dragPoint`; add `private var dragOrigin: CGPoint?` and `private var dragGrab: CGPoint = .zero`. On `mouseDown`, commit pending text and select the hit node as before, record `dragOrigin`, set `dragSource` only for a single click on a **non-root** node, and compute `dragGrab = point - screen(node.frame).origin`. On `mouseDragged`, if a source exists and `dragPoint` is still nil, ignore movement with `hypot(point.x-origin.x, point.y-origin.y) < 9`; otherwise update `dragPoint` and redraw. If no source, pan by `point - dragOrigin` and update `dragOrigin` so root and blank drags both track 1:1. On `mouseUp` compute `validDrop` from the actual release point, call `moveNode` once only if non-nil, and clear all transient state in `defer`; Escape while canvas is first responder clears a running drag without mutation.

- [x] **GREEN — shared preview geometry:** In `validDrop`, find the last laid-out non-source node whose `screen(frame)` contains the point. Convert point to world coordinates with `(point-offset)/zoom`, call `dropPlacement(at:over:siblings:)` on siblings sharing the target parent, and return its `(parent,index)` only when `model.canMoveNode(source,to:parent,at:index)` is true. In `draw`, call this helper at most once per frame. Stroke only its valid target: a rounded frame for child insertion or a short high-contrast horizontal bar at target top/bottom for sibling insertion. After the normal nodes, draw the dragged node's title inside a translucent rounded ghost at `dragPoint - dragGrab`, using existing text colors/font scaled by `zoom`. During drag, the model remains unchanged; no timers, animation engines or custom drag/drop frameworks.

- [x] **VERIFY & COMMIT:** Re-run the focused canvas check, model and layout tests, `bash build.sh`, and `git diff --check`; review frame/zoom math and AX selection before committing only `Sources/App.swift` and `Tests/CanvasCommandTests.swift`.

### Task 3: Bounded real-window acceptance and honest release

**Files:** Update `README.md`, the [taskbook](../specs/2026-10-21-independent-mindmap-gui-taskbook.md) G1 checkbox/evidence, and a new owned fixture report under `docs/superpowers/specs/` only after actually observing the GUI. Existing built output under `build/` is not committed; do not remove the unrelated `dist/` contents.

- [ ] Confirm the desktop is unlocked and AX permission is trusted; build/copy exactly one independent `MindMap.app` to a private `mkdtemp` 0700 directory with a fixed `.owner` marker; verify bundle URL and PID before each AX action. Never target original MindNode or private maps. Start from the app's own synthetic `Central idea`; add two children using the **owned app's native Node menu**, name them `Drag source` and `Drag target` in the focused native text field, rather than opening an unautomatable file panel.
- [ ] In that same owned window, have a human drag the first child across the second and release; capture only the uniquely matched app-owned window ID **during drag** and after release, inspect the resulting AX tree/selection, then undo and inspect restoration. If direct pointer automation is considered, use only verified PID-targeted events and abort on focus change; no global-posted events. An unmatched window or unobservable real mouse path means **GUI gate unverified**, not passed.
- [ ] Verify no package/fixture outside the owned directory changed; exit only the verified disposable PID. Before removing the private directory verify its resolved parent, exact name/marker, user ID, `0700` mode and expected synthetic contents; do not delete it when a user map or dirty window might be present.
- [x] Run every README assertion command and `bash build.sh` fresh. If the GUI gate passed, provide a new app bundle/zip, exact synthetic before/during/after images, a one-step drag/undo demonstration, and a gap list. If it could not be observed, ship the code and headless evidence labeled **GUI drag pending**, with one concrete user action to unblock it; never claim MindNode-level or original-format round-trip parity.

## Execution checkpoint｜2026-10-21

- Model guard commit `2a0112d`; canvas gesture commit `33a54e4`; old canvas failed the new blank-ghost assertion, new build passed all README assertion commands and `bash build.sh`.
- Owned live window PID `73855` displayed root `Drag target` and children `Drag source`/`Drag destination`. AX menu creation worked with condition-based waits, but an early unsynchronized AX text assignment renamed the synthetic root. This **does not** match the ideal fixture naming in Task 3; retain the honest [live gate record](../specs/2026-10-21-live-drag-gate.md) rather than marking the first GUI checklist item complete.
- The sole PID-targeted mouse click did not change AX selection; no actual drag was sent and no global event workaround was attempted. At 15:26 the same owned PID remained, but all three known synthetic AX labels disappeared; its current window state is unknown and must not be presumed synthetic. **Human drag/undo, real mouse routing, and verified cleanup remain pending.**
- New independently runnable artifact: `dist/MindMap-G1-Drag.zip`; `dist/mindmap-g1-ready-window.png` shows the synthetic three-node window only, not a mid-drag frame.
