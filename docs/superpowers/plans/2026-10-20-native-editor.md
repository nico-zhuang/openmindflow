# Native Mind Map Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compile a runnable, independent macOS editor with keyboard-first node editing, undo, deterministic layout and viewport navigation.

**Architecture:** A testable Foundation-only tree model owns IDs, titles, children, fold state and undo snapshots. One AppKit canvas handles native text input, keyboard, drawing and gestures. Do not load proprietary assets or touch user documents.

**Tech Stack:** Swift 6.2.1, Foundation, AppKit, swiftc; no Xcode or third-party dependencies.

## Global Constraints

- Project path is `mindnode-reconstruction/`, not the user's source app.
- `Tab` = child and `Return` = sibling are static bundled-menu findings until runtime verified.
- No personal `.mindnode` documents are accessed; unknown file format remains unsupported rather than guessed.
- Provide one assert-based executable test of every branching tree mutation; keyboard smoke tests require manual UI evidence.

---

### Task 1: Tree model and runnable tests

**Files:** Create `Sources/MapModel.swift`, `Tests/MapModelTests.swift`.

**Interfaces:** `struct MapNode: Codable { var id: UUID; var title: String; var children: [MapNode]; var folded: Bool }`; `final class MapModel { var roots: [MapNode]; var selected: UUID; func addChild(); func addSibling(); func rename(_ title: String); func remove(); func toggleFold(); func undo(); func redo() }`.

- [ ] Write tests first in `@main struct ModelTests { static func main() { ... } }` (multi-file `swiftc` disallows top-level expressions): create a root, add child and sibling, rename, fold, delete, undo and redo; assert exact order and selection; verify deleting root is rejected.
- [ ] Run `swiftc Sources/MapModel.swift Tests/MapModelTests.swift -o /tmp/mindnode-model-tests && /tmp/mindnode-model-tests`; expected compilation failure because methods are missing.
- [ ] Implement only the model needed by those assertions; represent undo/redo with snapshots, not a command framework.
- [ ] Re-run the same command; expected exit 0 and printed `model tests passed`.

### Task 2: AppKit editor with local build

**Files:** Create `Sources/App.swift`, `Sources/Layout.swift`, `Tests/LayoutTests.swift`, `build.sh`, `README.md`, `.gitignore` (`build/`).

**Interfaces:** `MapCanvas: NSView` takes `MapModel` and renders visible nodes; `keyDown` maps Tab, Return, Delete, Shift+period (static original fold key) and arrows to model calls; Space may remain as an optional shortcut but must not replace Shift+period. Native text input uses `NSTextField`; model mutations trigger redraw. Own-format saving uses a `.mindmap.json` file with `JSONEncoder` and `NSSavePanel`, and opening uses `JSONDecoder` and `NSOpenPanel`; never overwrite `.mindnode`. `build.sh` compiles to `build/MindMap.app/Contents/MacOS/MindMap` with `swiftc Sources/*.swift -framework AppKit -o ...` and generates a small Info.plist via here-document.

- [ ] Write an assert-based layout check before implementation: one parent with two children has distinct vertically ordered bounds and stable coordinates on two recomputations. In the same test runner, roundtrip `JSONEncoder`/`JSONDecoder` for roots (titles, UUIDs, fold state). Run compilation to see it fail for missing `layout`.
- [ ] Implement minimal deterministic tree layout and a zoom/pan transform inside `MapCanvas`, plus `scrollWheel` and `magnify` for platform gestures. Avoid speculative animation.
- [ ] Run `bash build.sh` and execute model/layout test command; expected exit 0 and executable `.app` exists.
- [ ] Launch only our new app with `open build/MindMap.app`; visually check Tab, Return, typing, undo, fold, zoom and pan without opening MindNode's saved windows. Report any unverified interaction honestly.

### Task 3: Format compatibility discovery, separate plan

**Files:** `docs/superpowers/plans/2026-10-20-mindnode-import.md` only after obtaining a disposable original-exported sample.

- [ ] Obtain a blank disposable `.mindnode` from the original app without reading or opening private documents; if app launch would restore private windows, stop and document this boundary.
- [ ] Identify actual container with `file`, `unzip -l` and read-only inspection of the disposable copy, then specify a precise bounded decoder and tests in the separate import plan.
- [ ] Never advertise `.mindnode` read compatibility until a real sample import and corruption checks pass.
