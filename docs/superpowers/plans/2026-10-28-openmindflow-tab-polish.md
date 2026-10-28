# OpenMindFlow Tab Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement each task with RED→GREEN tests and independent review.

**Goal:** Make tab renaming, hover-only close, vertical New Tab alignment and selected-tab wayfinding correct in the separate 0.5 candidate.

**Architecture:** `DocumentSession` owns a validated optional display title, distinct from the file URL and map root, and serializes it as backward-compatible optional `.mflw` metadata. `DocumentTabStrip` owns transient inline title editing, pointer-hover chrome and selected-state AppKit drawing. Existing tab transfer keeps the same session, so all properties follow it.

**Tech Stack:** Swift 6.2, macOS 26, AppKit NSView/NSButton/NSTextField, binary-property-list `.mflw`, offscreen HEADLESS_TEST and one isolated ordered native window smoke.

## Global Constraints

- Existing signed preview PID 68901, old 0.4 app/DMG/ZIP and original `.mindnode` files stay untouched; never overwrite them, relaunch old apps, or push unfinished 0.5.
- Preserve `OMFLW001`, 128 MiB bound, SHA-256 and inode conflict guards; unknown MindNode data and media remain unchanged.
- Current bundle identifier `local.openmindflow.tabs.20261027`, `0.5.0` build `6`, `.mflw` Editor UTI `local.openmindflow.document` remain unchanged.
- User forbids routine clarifying questions; commit a defensible default: renaming changes the document's visible tab/title metadata, never silently renames a Finder file or map-root node; inline Return/blur commits, Escape cancels; ordinary Save writes title to `.mflw` without silent disk writes.
- Hover-only visual close must retain accessible, keyboard-operable close semantics even when hidden; no invisible area may silently close a tab.
- Do not conflate synthetic offscreen/ordered-window checks with real user hover, field-editor or VoiceOver acceptance.

---

### Task 1: Persistent, safe document tab title

**Files:** Modify `Sources/OpenMindFlowFile.swift`, `Sources/DocumentSession.swift`, `Sources/App.swift`; create `Tests/TabTitlePersistenceTests.swift`; preserve existing APIs and tests.

**Interface:** `NativeMapFile.Payload` gains optional `tabTitle: String? = nil` (backward-compatible decoder). `LoadedDocument` gains optional title metadata. `DocumentSession` exposes `tabTitleOverride: String?`, `func renameTab(to raw: String) -> Bool`, `func displayTabTitle(defaults: UserDefaults) -> String`; its dirty baseline includes the name override and its Save/Load includes optional title. `AppDelegate`'s title callback uses the same display title rather than duplicating URL fallback.

- [ ] **Write RED:** a new unsaved session accepts `renameTab(to: "Project A")`, rejects empty/control or overlong titles, marks dirty; old `.mflw` with no optional title still opens; a new private `.mflw` Save→reopen retains title and unchanged map/archive; changing a file-backed tab title does not rename or overwrite the underlying filename; undo/transfer keep distinct sessions and names. Assert source-title callback updates only the current document's window title.
- [ ] **Run RED:** `swiftc -suppress-warnings -D HEADLESS_TEST Sources/*.swift Tests/TabTitlePersistenceTests.swift -framework AppKit -framework AVKit -framework AVFoundation -o <fresh-owned0700-scratch>/TabTitlePersistenceTests && <same-executable>` must fail for the missing title API or a focused behavioral assertion, not a typo.
- [ ] **Implement GREEN:** validate trimmed NFC UTF-8 name ≤255 bytes, no newline/control; allow 1–128 grapheme clusters, no filesystem path side effects. Keep `savedTabTitleOverride` beside other saved baselines; incorporate title inequality into `syncDirty()`. On successful `.mflw` write/read verify the encoded title equals the in-memory value before clearing dirty. `installDocument` takes optional saved title and refreshes the title callback; imported old JSON or `.mindnode` starts without an override. Do not rename `fileURL` when tab metadata changes.
- [ ] **Run focused GREEN and adjacent:** `TabTitlePersistenceTests`, `NativeDocumentJourneyTests`, `OpenMindFlowFileTests`, `MultiDocumentSaveAsTests`, `DocumentSessionIsolationTests` compile/run offscreen in new private scratch; production `swiftc Sources/*.swift` links. Record exact RED/GREEN exits.
- [ ] **Commit only Task 1 scope** after self-review and `git diff --check`.

### Task 2: Editable and legible horizontal/vertical tab chrome

**Files:** Modify `Sources/DocumentTabStrip.swift` and optionally `Sources/WindowSession.swift` for narrow callback wiring; create `Tests/TabChromeInteractionTests.swift`; extend `Tests/TabAccessibilityTests.swift` if needed.

**Interface:** second title-button `mouseDown(clickCount >= 2)` invokes strip-owned inline NSTextField; single click and ≥8pt drag stay unchanged. Inline Return or focus loss calls `DocumentSession.renameTab`, Escape restores prior title; rejected empty text keeps editing without corrupting the session. Selected row draws a dynamic accent-tinted fill and narrow stroke in light and dark appearance; unselected rows remain subdued. Each row's close button has a ≥24pt pointer target, 14–16pt low-contrast glyph, hidden/non-hittable at rest and 100–140ms opacity on hover. The tab retains a persistent accessible Close action so VoiceOver/keyboard can close without hover. Vertical `＋` gets a centered 28–30pt square hit area with consistent row spacing; do not change insertionIndex semantics.

- [ ] **Write RED:** tests assert double-click enters field and single click/drag do not rename; Return/blur commit, Escape cancels, empty title does not mutate; distinct tab titles and active selection survive orientation, transfer, and localization; close is visually hidden and non-hittable until hover yet accessible close action remains; current selected row has measurable distinct active fill in both orientations/appearances; vertical add-button frame is centered within the strip and does not overlap the final row.
- [ ] **Run RED:** independently compile/run `TabChromeInteractionTests` in fresh owned0700 scratch and record the intentional failure before touching production chrome.
- [ ] **Implement GREEN:** use AppKit tracking area with `.inVisibleRect` plus `.activeInKeyWindow`; opacity animation only on hover state transition, respect Reduce Motion. Preserve native button actions/AX and the audited native dragging state machine. Avoid an invisible button intercepting pointer clicks; use a tab accessibility custom Close action while its hover control is hidden.
- [ ] **Run GREEN and adjacent:** `TabChromeInteractionTests`, `TabAccessibilityTests`, `DocumentTabStripTests`, `TabDragSignalTests`, `DocumentTabTransferTests`, `MultiWindowLifecycleTests` each independently compile/run offscreen in owned0700 scratch; production link; ordered native-window geometry/selection smoke in new disposable process without global AX/HID.
- [ ] **Commit only Task 2 scope** after self-review. Independent SPEC/QUALITY reviewer checks both commits and tests; fix Important/Critical findings before rebuilding a newly named signed 0.5 candidate (do not patch existing PID68901).

### Release coordination

Task82B concurrently writes only new version-specific scripts/tests and README. After both tasks pass review, Lead rebuilds **fresh** 0.5 app using final source, runs full safe HEADLESS_TEST suite (excluding live `AppAccessibilityTests.swift`) plus three LeftBranchInteraction modes, new package safety tests, signed DMG/ZIP read-only mount/extract hashes, protected 0.4 SHA/PID checks. User-verified earlier physical three actions apply only to the previous preview; they do not automatically validate this newly changed chrome. README and final reply distinguish previous interaction testimony from untested new hover/inline edit and real Finder/MindNode-app acceptance.
