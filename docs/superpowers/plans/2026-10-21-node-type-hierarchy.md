# Native Node Type Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the map's central/main ideas distinguishable from branches while keeping inline typing aligned to the text it replaces, including multiline Chinese/English titles.

**Architecture:** One platform `NSFont` function returns 16pt semibold for each main/root node and 14pt medium for descendants, with the existing zoom factor applied only at draw/edit time. Reuse that one font in text measurement, canvas labels and the native editor. Do not introduce a theme/style schema, alternative model, custom font, animations, or JSON fields.

**Tech Stack:** Swift/AppKit `NSFont.systemFont`, existing `Layout.swift`, `MapCanvas`, assertion tests.

## Global Constraints

- This is G4 code preparation. G1 pointer, G2 native panels, G3 workbench GUI and G4 real-window/IME/light-dark gates remain unverified; offscreen type geometry cannot pass them.
- Keep `.mindnode` read-only, atomic own-JSON saves and selected/drag/undo behavior unchanged; never inspect original/private maps, unknown PID `73855` or use global events.
- Fit capped text frames using the *same* font metrics as drawing. One 30-node mixed CJK/multiline fixture and active-field assertion are required; avoid fragile screenshots as the only regression.

---

### Task 1: Shared root/branch font and layout measurement

**Files:** Modify `Sources/Layout.swift`, `Sources/App.swift`, `Tests/LayoutTests.swift`, `Tests/CanvasCommandTests.swift`.

- [x] RED: in `LayoutTests`, assert `mapFont(isRoot: true).pointSize == 16`, branch `== 14`, root font differs from branch font, then for the existing 30-node mixed CJK/multiline fixture measure each `LaidOutNode.frame` text with `mapFont(isRoot: node.parent == nil)` and assert height ≤ frame height−22. In `CanvasCommandTests`, create a root and child text editor, assert its font matches the corresponding font used for rendering at zoom 1; after `fitMapInView`, zoomed editor point size remains synchronized. The missing `mapFont` helper/new root font should fail before production changes.
- [x] GREEN: add only `func mapFont(isRoot: Bool, zoom: CGFloat = 1) -> NSFont` to `Layout.swift` (root 16pt `.semibold`, descendants 14pt `.medium`). In `mapLayout` measure each node using `mapFont(isRoot: depth == 0)`; compute `attributes` inside `measure` so text width and wrapping use actual displayed font. In `MapCanvas.draw` (node labels **and drag ghost**), `beginEditing`, viewport fit and zoom/editor-font update sites, use that same function keyed by `LaidOutNode.parent == nil`; do not alter card geometry constants, semantic colors, gestures, selection or JSON.
- [x] VERIFY: focused layout/canvas assertions, all README nine headless commands, `bash build.sh`, `git diff --check`; commit only the four named source/test files. Record that same-size ten/30-node light/dark screenshots and Chinese IME input still need real owned GUI observations before G4 acceptance.
