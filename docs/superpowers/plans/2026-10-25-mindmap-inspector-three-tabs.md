# MindMap Three-Tab Inspector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-page right inspector with three actually working native pages—Style, Notes and Themes—matching the approved screenshots without a Tags page.

**Architecture:** Reuse `StyleInspector`, `MapModel`'s existing snapshot Undo, `MapCanvas` drawing and `OwnMapDocument` version 1. Node notes and root appearance live on `MapNode`; theme choice and canvas color belong to the document and travel with the model snapshot. Import stays read-only; a separate experimental `.mindnode` export refuses unsupported new metadata.

**Tech Stack:** Swift 6.2, AppKit, Foundation, existing sources only; no dependencies. Spec: `docs/superpowers/specs/2026-10-25-mindmap-inspector-three-tabs-design.md`.

## Global Constraints

- Only **three** inspector tabs: paintbrush, document/notes, palette/themes. **No Tags tab or icon.**
- Root nodes have their own shape; child nodes stay as text on a line, without a persistent box.
- Notes are plain text, at most **64 KiB UTF-8**. Existing `.mindmap.json` root arrays remain readable; object-envelope version stays **1**; map limit remains **32 MiB**.
- Theme priority: per-node explicit color > user-selected document theme > imported original color/theme > current default. Merely opening an imported map must not change its appearance.
- Background defaults to following system appearance; a document background must render identically onscreen and in PDF/PNG/JPG.
- Source `.mindnode`, first signed preview and private user data are read-only. Do not overwrite a running development app, seize the user's desktop for global-event testing, merge `main` or claim original-app package compatibility.
- Synthetic tests: `swiftc -D HEADLESS_TEST Sources/*.swift Tests/<Name>Tests.swift -framework AppKit -framework AVKit -framework AVFoundation -o /tmp/<Name>Tests && /tmp/<Name>Tests`; do not run `AppAccessibilityTests` or `WindowResizeTests` unattended.

---

### Task 1: Model, JSON and `.mindnode` safety

**Files:** Modify `Sources/MapModel.swift`, `Sources/OwnJSON.swift`, `Sources/MindNodeWriter.swift`; extend `Tests/MapModelTests.swift`, `Tests/OwnDocumentTests.swift`, `Tests/MindNodeWriterTests.swift`.

**Interfaces:** `MapNode.note: String?`, `MapNode.rootShape: String?`, `MapNode.rootFillColor: String?`; `MapModel.theme: String?`, `MapModel.canvasColor: String?`, `setNote(_:)`, `setRootShape(_:)`, `setRootFillColor(_:)`, `setTheme(_:)`, `setCanvasColor(_:)`; `OwnMapDocument(roots:relationships:theme:canvasColor:)`; `MindNodeWriter.write(..., theme:canvasColor:)` retains nil defaults for old callers.

- [ ] **Step 1: Write RED tests**. In `MapModelTests`, create two nodes and assert: an empty or unchanged note creates no Undo; `setNote("Example")` changes only one selected node and one Undo restores it; 65,537 UTF-8 bytes are rejected; applying a theme then undo/redo restores the exact theme. In `OwnDocumentTests`, assert `(theme:"tropical",canvasColor:"#102030FF")` forces the version-1 envelope even without relationships, reopens intact, and an old array still reads. Assert legacy `writeOwnJSON` refuses to replace an existing styled envelope. In `MindNodeWriterTests`, new note/root appearance/theme rejects before creating a package.
- [ ] **Step 2: Confirm RED** with the focused compile-and-run command above for each test. Expect missing fields/methods or assertion failures, not a green suite.
- [ ] **Step 3: Add optional fields and validated setters**. Bound notes by `value.utf8.count <= 65_536`, root shape to `"rectangle"|"rounded"`, theme to `"tropical"|"rainbow"|"candyland"`, and colors by the existing `#RRGGBBAA` validation. Reuse `editSelected` for note/shape/fill, rejecting shape/fill edits on non-root selections. For document values, call existing `save()` only when the new value differs. Include `theme` and `canvasColor` in every `Snapshot`, `undo`/`redo`, and `fitsSavedJSON` size calculation. Example note setter:

```swift
@discardableResult func setNote(_ text: String) -> Bool {
    guard text.utf8.count <= 65_536, selectedPaths().count == 1 else { return false }
    return editSelected { $0.note = text.isEmpty ? nil : text }
}
```

- [ ] **Step 4: Extend v1 JSON without dropping metadata**. Decode absent optional `theme`/`canvasColor` as nil; encode only non-nil fields. `writeOwnDocument` uses the old root array only when relationships and both document values are empty. `readOwnJSON`/`writeOwnJSON` reject a document containing metadata the wrapper cannot preserve. Validate note length, shape, fill, theme and background during `checkOwnDocument` *before* model mutation or file replacement. Keep `Data.write(options:.atomic)` and existing path checks.
- [ ] **Step 5: Guard experimental writer** at its existing `guard` before `mkdtemp`: reject a nonempty note, any new root shape/fill, or non-nil theme/background; keep the original destination untouched. Update its private `render(_:)` guard too if a separate code path could bypass the entry guard.
- [ ] **Step 6: Run tests and commit**. Expect all three focused groups PASS; run `git diff --check`, then commit only this task's files with `feat: persist inspector notes and document appearance`.

### Task 2: Shared rendering and export consistency

**Files:** Create `Sources/InspectorTheme.swift` (only three palettes and a tiny preview draw helper if reused); modify `Sources/App.swift` `MapCanvas.draw`/`AppDelegate` save/open/dirty paths, `Sources/MapExport.swift`; extend `Tests/BranchStyleTests.swift` and `Tests/MapExportTests.swift`.

**Interfaces:** `InspectorTheme(rawValue:)`, `InspectorTheme.rootFill` and `.branchColors`; `MapCanvas.model.theme/canvasColor` drives screen and detached `exportMap`; `AppDelegate.savedTheme/savedCanvasColor` participates in dirty state.

- [ ] **Step 1: Write RED render/export checks**. A synthetic root+two children with `theme="rainbow"` gets distinct colored strokes and a themed root fill; an explicit node branch color still wins; an imported color remains until theme is explicitly selected. Set `canvasColor="#102030FF"`; export PNG/JPG/PDF using temporary owned destinations and assert bitmap background pixels and PDF page backdrop are the chosen color, while absent color follows existing system behavior. Ensure tests never use user content or overwrite existing files.
- [ ] **Step 2: Confirm RED** by compiling/running `BranchStyleTests` and `MapExportTests`; record missing color effect or mismatched output.
- [ ] **Step 3: Render three real theme palettes** using one shared enum rather than duplicating colors in view and export:

```swift
enum InspectorTheme: String, CaseIterable, Codable {
    case tropical, rainbow, candyland
    var rootFill: String {
        switch self { case .tropical: "#FFFFFFFF"; case .rainbow: "#FFFFFFFF"; case .candyland: "#EF1760FF" }
    }
    var branchColors: [String] {
        switch self {
        case .tropical: ["#52C6C4FF", "#FF9955FF", "#F6CC49FF", "#A94ECCFF"]
        case .rainbow: ["#7CCF8DFF", "#A9A6F0FF", "#FF9A60FF", "#46C3C9FF"]
        case .candyland: ["#A1D56FFF", "#F248A8FF", "#3EB9B6FF", "#C95A6AFF"]
        }
    }
}
```

  In `MapCanvas.draw`, calculate inherited color in priority order `node.branchStrokeColor ?? selectedThemeColor ?? importedStyle ?? existingDefault`, and root fill `node.rootFillColor ?? selectedThemeFill ?? importedFill ?? controlBackgroundColor`; root shape controls only root path corner radius. Leave the existing unframed child path intact. Use one `canvasColor` background fill in the drawing path used both by screen and detached export canvas.
- [ ] **Step 4: Wire file lifecycle**. `openOwn` restores both document values; new/imported documents reset them to nil; `save` writes them; `syncDirty` compares them to saved values. Copy them from the live canvas to `MapExport`'s detached canvas; preserve current high-DPI raster limits and vector PDF dimensions.
- [ ] **Step 5: Run render/export and Task-1 model/JSON tests**, `git diff --check`, then commit `feat: render document themes and export background`.

### Task 3: Three native tabs, context menu and localization

**Files:** Modify `Sources/StyleInspector.swift`, `Sources/App.swift` (context menu + presenter callback), `Sources/Localization.swift`; extend `Tests/StyleInspectorTests.swift`, `Tests/CanvasCommandTests.swift`.

**Interfaces:** `StyleInspector.selectNotes(for:)`, `StyleInspector.refresh()` and page selector; `MapCanvas.onEditNote: ((UUID) -> Void)?`; existing `AppDelegate.togglePane(at: 2)` preserves window frame and map screen position.

- [ ] **Step 1: Write RED UI tests**. Recursively inspect native inspector controls: exactly three icon tabs with paintbrush/document/palette accessibility labels, no Tags icon or placeholder, scrollable style controls at widths 260/320 pt, scrollable plain-text notes, three theme cards with preview content. Trigger node-menu Edit Note and assert the selected node, visible right pane, Notes tab and focused text editor; change/commit a note, undo, save/reopen and assert its text. Click each card, assert document theme ID changed in one Undo and the thumbnail colors match the shared enum. Check English and Simplified Chinese labels.
- [ ] **Step 2: Confirm RED** with `StyleInspectorTests` and `CanvasCommandTests`; do not activate the user's existing app or post global key/mouse events.
- [ ] **Step 3: Reuse existing controls**. Put the current style `NSStackView` in a vertical `NSScrollView`; retain all current font/connection controls and accessibility names. Add root shape/fill/fixed-width controls only after their Task-1 setters exist. Add exactly three native icon segments (no tag):

```swift
let tabs = NSSegmentedControl(labels: ["", "", ""], trackingMode: .selectOne,
                              target: self, action: #selector(selectPage(_:)))
for (index, spec) in [("paintbrush", "Style"), ("note.text", "Notes"),
                      ("paintpalette", "Themes")].enumerated() {
    tabs.setImage(NSImage(systemSymbolName: spec.0,
                          accessibilityDescription: L10n.text(spec.1, defaults: defaults)),
                  forSegment: index)
    tabs.setToolTip(L10n.text(spec.1, defaults: defaults), forSegment: index)
}
tabs.selectedSegment = 0
```

  Build the Notes page with `NSScrollView` + editable `NSTextView`; disable editing unless exactly one node is selected. On editor exit or tab switch, call `model.setNote(textView.string)` once rather than on each keystroke. Theme cards are native clickable views using `InspectorTheme` values; previews draw an unframed child tree, not the original app's artwork.
- [ ] **Step 4: Wire right-click Edit Note** through one `MapCanvas.onEditNote` closure set by `AppDelegate` (no global window). After selecting the node, open pane 2 only if collapsed using the existing frame-preserving toggle; select the Notes segment and focus its text view. Update localization for each visible/accessibility string, including the context item. Keep unsupported screenshot controls entirely absent, not merely disabled dummies.
- [ ] **Step 5: Run both focused UI groups plus model, export and localization groups**, `git diff --check`, then commit `feat: add functional style notes and theme inspector tabs`.

### Task 4: Integrated verification and safe preview handoff

**Files:** Add one focused synthetic visibility test in `Tests/InspectorVisibleJourney.swift` or extend existing isolated GUI harness without touching the user's running app; update `README.md` and `docs/superpowers/plans/2026-10-24-mindmap-second-release.md` with the actual pass/fail evidence.

- [ ] **Step 1: Run all 33 safe offscreen groups** over final sources (exclude only focus-stealing `AppAccessibilityTests.swift` and `WindowResizeTests.swift`); confirm exact count=33 and any new inspector test included. If the new test file raises count to 34, report that count accurately rather than hardcode 33. Re-run the prior export and imported-theme checks after any fixes.
- [ ] **Step 2: Use an owned synthetic `.app`/window** and verify visible, key and frontmost status, icon tabs, note context action, theme selection/Undo, and 260 pt layout *only when desktop focus can be safely obtained without interrupting the user*. If not safe, mark visible GUI unverified and do not claim the release passes; do not substitute headless tests.
- [ ] **Step 3: Rebuild the existing development app only after verifying its exact resolved bundle path/ID and that its previous process exited.** Never overwrite the first signed app/ZIP or original `.mindnode`. Run `git diff --check`, check the signed first-preview SHA-256 is still `1dd50186df560cf84d418b9ca8e975d8ed75ebbc952f989e8a5140583e3891eb`, and commit truthful status docs. Do not merge main, sign a third user-facing version, or publish the second signed preview while original-MindNode acceptance remains unverified.
