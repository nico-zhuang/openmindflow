# Centered Initial Map View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a newly created or successfully opened map immediately readable in the independent window instead of marooning a small tree in the top-left corner.

**Architecture:** Keep the existing deterministic layout and canvas transform. Fit the union of *visible* node frames once, after the canvas has its actual native split-window bounds; cap zoom at 1 for small maps, never refit during drawing, panning, editing or ordinary resizing. Invoke this action on initial launch and successful document replacement only; user viewport movement remains in control thereafter.

**Tech Stack:** Swift, AppKit geometry, existing `mapLayout` and `MapCanvas`/`AppDelegate`; no dependency or JSON change.

## Global Constraints

- G1 real mouse drag, G2 native picker/save workflow and G3 native workbench GUI gates remain open; offscreen geometry assertions do not pass them. This is independent G4 code preparation, not stage acceptance.
- `.mindnode` import stays read-only, Save stays own JSON. Never inspect/launch original app, private maps or unknown PID `73855`; no global events, no extra GUI process while another same-bundle window's ownership/content is unknown.
- Preserve no-op behavior for failed/cancelled opens and active editing. Do not reset viewport on every `draw`, `needsDisplay`, ordinary resize, text edit or user pan/zoom. No new persisted coordinates or style fields.

---

### Task 1: Geometry-only fit action

**Files:** Modify `Sources/App.swift` near `MapCanvas.screen(_:)`/`revealSelection()`; extend `Tests/CanvasCommandTests.swift`.

**Interface:** Add only `@discardableResult func fitMapInView() -> CGRect` to `MapCanvas`. It reads `visibleNodes()` world frames once, takes their union, computes `min(1, max(0.35, min((bounds.width - 2*64)/world.width, (bounds.height - 2*64)/world.height)))` for positive drawable bounds, centers the transformed union via `offset = bounds.mid - world.mid * zoom`, aligns active editor font/frame, sets `needsDisplay`, and returns the projected union of visible frames. Empty map or bounds ≤128pt leave state unchanged and return `.null`. No test-only viewport API or duplicate geometry helper.

- [ ] RED: in `CanvasCommandTests.swift`, construct the committed 10-node synthetic fixture (or an equivalent 10-node root with two levels, multiline and 280pt-wide titles) in a `MapCanvas` with `frame = CGRect(x: 0,y: 0,width: 1200,height: 850)`. Call `fitMapInView()` then assert projected bounds minimums ≥60pt, maximums ≤viewport−60pt and both midpoints differ from viewport midpoint by <2pt. A 30-node tall map may hit the existing 0.35 minimum zoom; assert its root remains visible, not that every row fits simultaneously. Run `swiftc -D HEADLESS_TEST Sources/*.swift Tests/CanvasCommandTests.swift -framework AppKit -o /tmp/mindmap-fit-red && /tmp/mindmap-fit-red`; expected compile failure for missing method.
- [ ] GREEN: implement the exact geometry above using `visibleNodes()` once; compute `zoom`, `offset`, editor font/frame and redraw once. No scroll event changes or custom layout. The original drag tests must still pass because they do not call `fitMapInView()`.
- [ ] VERIFY: focused canvas checks and full README suite/build pass; `git diff --check`, scoped commit `Sources/App.swift` + `Tests/CanvasCommandTests.swift`.

### Task 2: Fit only at new-document boundaries

**Files:** Modify `Sources/App.swift` AppDelegate launch and successful `openFile`/`openMindNode` branches; one focused AppKit/document-journey assertion if a safe non-visible instance can exercise the existing boundary without panels.

- [ ] PRECONDITION: Task 1 first establishes the geometry regression (red then green). Read the three existing AppDelegate call sites; do not create a test-only opener or launch a window just to test three calls of the already verified action. Confirm `openFile` decodes before and after any Save; do not move that validation.
- [ ] GREEN: after attaching split/toolbar, call `window.contentView?.layoutSubtreeIfNeeded()` and `canvas.fitMapInView()` before first `makeKeyAndOrderFront`. After **successful** `canvas.model` replacement in own JSON and read-only MindNode import, call `canvas.fitMapInView()` before `window.makeFirstResponder(canvas)`; failed/Cancelled returns must not touch viewport/model. These are three one-line uses of the tested method, not another geometry implementation. Never call from `windowDidResize` or `syncDirty()`.
- [ ] VERIFY: full README suite/build and fixed ten-node offscreen render at one size. GUI screenshot comparison remains pending until one clean verified owned process exists and real drag/open-panel gates can be observed; no cosmetic parity claim from a windowless image.
