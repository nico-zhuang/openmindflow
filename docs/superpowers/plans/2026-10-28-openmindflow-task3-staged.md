# OpenMindFlow Multi-Document Task 3 Staged Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved design plan's Task 3 in three separately reviewed, sequential TDD changes without shipping an inaccessible intermediate editor.

**Architecture:** `DocumentSession` remains the sole mutable owner of one map and its native-file baseline. `WindowSession.documents` temporarily retains inactive sessions and swaps their existing workbench on activation; the visible tab strip is the dependent Task 79, so no intermediate app is published. `AppDelegate` owns Finder/menu routing and close/quit preflight, but never uses `sessionsByWindow` to resurrect a document removed from a registered window.

**Tech Stack:** macOS 26, Swift 6.2.1, AppKit, Darwin `lstat`, SHA/inode-checked `.mflw` binary-plist codec; isolated, never-ordered AppKit test windows.

## Global Constraints

- Prior version 0.4.0 was pushed separately; do not push unfinished 0.5.0, overwrite historical bundles/images, touch running applications or modify source `.mindnode` packages.
- Planned candidate is 0.5.0, build 6, bundle ID `local.openmindflow.tabs.20261027`; no candidate may ship before visible tabs and verified physical drag/cancel distinction.
- Preserve the original `loadMap(at:)`, `loadMindNode(at:)`, `installUnshownDocumentFixture(canvas:)`, `makeWorkbench(canvas:)`, `saveCurrentMap(to:)`, `exportCurrentMindNode(to:)` signatures and their explicitly installed isolated test behavior. In particular, the existing pre-launch synthetic Finder test (`Tests/NativeDocumentJourneyTests.swift:208-215`) may replace its **HEADLESS_TEST-only** placeholder; production Finder/open panels must not replace an edited document.
- Offscreen tests: `swiftc -suppress-warnings -D HEADLESS_TEST Sources/*.swift Tests/NAME.swift -framework AppKit -framework AVKit -framework AVFoundation -o <fresh-private-output>`; never run live `AppAccessibilityTests.swift`/global AX or HID.
- No routine design question: a production Finder open with zero windows creates one window and uses its initial clean placeholder slot for the first successfully preflighted file; subsequent distinct files become sessions in the same window. An already edited or user-created untitled session is **never** silently replaced. Before Task 79, other sessions are retained but not yet accessible via visible tabs; this is test-only intermediate behavior, not a distributable candidate.

## File Structure

- `Sources/DocumentSession.swift`: retain per-document model, archive, Find, SHA/device+inode baseline and bounded preflight; expose read-only verified native identity for registry comparison and a destination guard hook only if AppDelegate cannot safely mediate Save As.
- `Sources/OpenMindFlowFile.swift`: in Task 3C only, optionally accept an expected destination identity at the existing descriptor-relative pre-publication check; default preserves verified 0.4 writer behavior for all old callers.
- `Sources/WindowSession.swift`: own ordered documents, active workbench, final-session close preparation; removal invalidates document-owned panels and never leaves stale AppDelegate routing.
- `Sources/StyleInspector.swift`: in Task 3C only, reject stale global color-panel callbacks when its document is no longer the active owner.
- `Sources/App.swift`: Finder multi-URL, menu panel route, session construction/registration, window selection, staged close/quit, global language/color-panel routes. Leave the legacy headless fixture branch explicit.
- `Tests/MultiDocumentOpenTests.swift`: focused never-ordered Finder/open/import/dedup/corrupt-URL regression, including pre-launch legacy fixture compatibility.
- `Tests/MultiDocumentCloseTests.swift`: focused dirty Save/Cancel/failure, last-tab removal, all-window quit, stale Find/menu resolution tests.
- `Tests/MultiDocumentBindingTests.swift`: cross-session Save As alias, language/Find/color/media-menu binding tests.
- Keep `Tests/NativeDocumentJourneyTests.swift`, `Tests/MultiWindowLifecycleTests.swift` unchanged unless a deliberate old assertion must be adapted; never weaken 0.4 codec/save regression.

---

### Task 3A: Finder, Open and Import Create Independent Sessions

**Files:** Modify `Sources/App.swift`, `Sources/WindowSession.swift`, `Sources/DocumentSession.swift`; create `Tests/MultiDocumentOpenTests.swift`. No close-flow or color-panel edits in this task.

**Interfaces:** Produce `AppDelegate.openMapInWindow(_ url: URL, preferred: WindowSession?) throws -> DocumentSession` and `openMindNodeInWindow(_ url: URL, preferred: WindowSession?) throws -> DocumentSession`; after preflight `WindowSession.insert(_:)` retains the prior session and `activate(_:)` installs the new session's existing split view. `DocumentSession.nativeIdentity: NativeMapFile.FileIdentity?` is read-only from its verified loaded/saved baseline. Existing `loadMap(at:)`/`loadMindNode(at:)` retain replacement semantics exclusively as old compatibility entrypoints; File menu calls the new functions instead.

- [ ] **Step 1: Write RED tests.** Create two distinct valid `.mflw` files plus a hardlink alias and invalid `.mflw` in a newly created owner-only 0700 fixture. With `NSApplication.shared.setActivationPolicy(.prohibited)` and never-ordered windows, assert `application(_:open: [a,b,alias,invalid])` yields two distinct sessions with their own roots/URLs and exactly one per verified device+inode; the invalid entry neither removes nor dirties successful sessions. Open an archive-backed v9 `.mindnode` into another session and assert its `fileURL == nil`, archive belongs only to it, original bytes unchanged; an already dirty session survives both File Open and Import. Assert no window is visible or key, and reopening after final close creates a window. Keep `NativeDocumentJourneyTests.swift:208-215` passing without changing its test fixture.
  Core assertions after constructing distinct fixture files `a`, `b`, `hardlink`, `bad`:
  ```swift
  app.application(NSApplication.shared, open: [a, b, hardlink, bad])
  let opened = app.windowSessions.flatMap(\.documents).filter { $0.fileURL != nil }
  assert(opened.count == 2 && opened[0] !== opened[1])
  assert(opened.map(\.nativeIdentity).allSatisfy { $0 != nil })
  assert(app.windowSessions.allSatisfy { !$0.window.isVisible && !$0.window.isKeyWindow })
  ```
- [ ] **Step 2: Verify RED.** Compile/run `MultiDocumentOpenTests` alone using the global command: expect missing `openMapInWindow` or the old single-URL Finder refusal, not fixture creation failure.
- [ ] **Step 3: Implement preflight before registration.** Use `LoadedDocument` from `DocumentSession.preflightMap(at:)` and existing `preflightMindNode(at:)`, then construct/install a **new** `DocumentSession` and only then insert/activate it. Compare `loaded.identity` with live registered sessions' verified native identities *before* creating a duplicate; focus that exact session on match. Implement the production no-window initial-clean-slot rule from Global Constraints; handle every Finder URL independently and report one failed item without undoing other opens. AppKit panel actions capture an explicit registered window before `runModal`, never derive destination from a key window after the panel returns. For tests, keep the legacy `installUnshownDocumentFixture` pending Finder replacement behind `#if HEADLESS_TEST`.
  Minimal identity accessor and dedup branch, placed before session construction:
  ```swift
  // DocumentSession.swift
  var nativeIdentity: NativeMapFile.FileIdentity? { savedNativeIdentity }
  // AppDelegate.openMapInWindow, after preflightMap(at:)
  if let identity = loaded.identity,
     let owner = windowSessions.first(where: { candidate in
         candidate.documents.contains { $0.nativeIdentity == identity }
     }),
     let existing = owner.documents.first(where: { $0.nativeIdentity == identity }) {
      owner.activate(existing)
      return existing
  }
  ```
  Exact-URL reopening after external inode replacement must also focus the still-open session and report its external-change warning; do not create a second editor on the same path.
- [ ] **Step 4: Verify GREEN and regressions.** Compile/run `MultiDocumentOpenTests`, `NativeDocumentJourneyTests`, `MultiWindowLifecycleTests`, `DocumentSessionIsolationTests`, `MindNodeArchiveTests`; production link and `git diff --check`. Check no `canvas.model =` is used to switch sessions, no single-URL Finder guard remains in production, and no source `.mindnode` path becomes `fileURL`.
- [ ] **Step 5: Review then commit.** Read-only spec/quality review of verified identity dedup and failed-URL isolation; stage only the listed files and commit `Open independent Finder and imported document sessions`.

### Task 3B: Stage Close and Quit Before Releasing Documents

**Files:** Modify `Sources/App.swift`, `Sources/WindowSession.swift`, `Sources/DocumentSession.swift` only if needed; create `Tests/MultiDocumentCloseTests.swift`.

**Interfaces:** `WindowSession.prepareClose(documents:) -> Bool` asks the injected confirmation callback for **every** affected document before any `remove`; AppDelegate offers `closeDocument(_ document: DocumentSession, in owner: WindowSession) -> Bool` for later `⌘W`/tab X. `WindowSession.remove(_:)` invalidates Find/color-panel ownership and requests registry rebind so `AppDelegate.activeSession` never falls back to `sessionsByWindow` when a registered coordinator has no active document. The final document delegates to native window close, rather than keeping a blank phantom window.

- [ ] **Step 1: Write RED tests.** In two never-ordered windows with A/B dirty and C clean, inject per-document confirmation that first saves A and then rejects B (Cancel), plus a separate injected `save-failure` fixture and a `commitPendingEditors() == false` editor case. Assert no document or window is released on **any** refusal, A's successful save remains durable, B stays dirty, Find panel and selected roots stay attached, and quit returns `.terminateCancel`. Then approve all, close only one multi-document window, assert other window untouched, and reopen via `⌘N` after final closure. Remove a non-last tab and assert the removed document is inaccessible from AppDelegate/menu/Find, including when `NSApp.keyWindow` refers to its old owner window.
- [ ] **Step 2: Verify RED.** Compile/run `MultiDocumentCloseTests` alone; expect missing explicit `closeDocument` seam or stale routing/early release. Do not show modal UI under `HEADLESS_TEST`.
- [ ] **Step 3: Implement staged transaction.** Keep `prepareClose` synchronous and short-circuit on Cancel/editor refusal/Save failure without removing any member. Only after all confirmations pass may `closeDocument` remove one or native `windowWillClose` detach all; if the last tab is requested, call the normal window close route. For a registered window, `activeSession` must return its `WindowSession.active` *even if nil*, never `sessionsByWindow[key]`; reserve the map solely for the explicit legacy unregistered fixture. Clear panels and color ownership on removal as well as on window close; ensure all-window quit preflights every window before any are released.
  The registered-window route must use an explicit branch, not `?? sessionsByWindow[key]`:
  ```swift
  if let key = NSApp.keyWindow {
      if let owner = windowSessions.first(where: { $0.window === key }) {
          return owner.active  // nil is intentional after removal, never a legacy fallback.
      }
      if key === findSession?.findWindow, let found = findSession,
         isLiveSession(found) { return found }
      // Only the deliberately unregistered legacy fixture may use sessionsByWindow[key].
  }
  ```
- [ ] **Step 4: Verify GREEN and regressions.** Compile/run `MultiDocumentCloseTests`, `MultiDocumentOpenTests`, `MultiWindowLifecycleTests`, `NativeDocumentJourneyTests`, `SearchWorkbenchTests`; production link and diff check. Inspect that Save As errors leave all sessions registered even if an earlier session already saved.
- [ ] **Step 5: Review then commit.** Read-only review of cancel-on-close, failed editor commit and removed-session unreachable invariants; stage only listed files and commit `Stage multi-document close and quit decisions`.

### Task 3C: Cross-Session Save As and UI-State Ownership

**Files:** Modify `Sources/App.swift`, `Sources/WindowSession.swift`, `Sources/StyleInspector.swift`, `Sources/DocumentSession.swift`, and `Sources/OpenMindFlowFile.swift` only to add a default-preserving destination-identity precondition; create `Tests/MultiDocumentBindingTests.swift`; adapt `Tests/AppLanguageSettingsTests.swift` only if needed.

**Interfaces:** AppDelegate checks a candidate destination against every *other* live `DocumentSession.nativeIdentity` before any Save As publish; a match throws `NativeMapFile.FileError.conflict` and neither bytes nor dev/inode may change. `AppDelegate.refreshLanguageForAllDocuments()` iterates `windowSessions.flatMap(\.documents)`; document-bound color panel changes must target only a still-live active owner, or be disabled when no such owner exists.

- [ ] **Step 1: Write RED tests.** Save/open A and B in distinct tabs/windows. Try Save As A to B's actual URL and a hardlink alias, assert conflict and B's original bytes **and** `lstat` dev/inode unchanged; A remains dirty and retains its URL/Undo. Change language and assert both windows' titles/Find/toolbar/workbenches refresh, not just the key window. Create a never-ordered color-panel callback fixture: switch A→B then close A; any stale color callback cannot mutate A or B incorrectly. Invoke Node, Insert Image/Video and save menu selectors while a settings window is key and after all document windows close; no panel or crash may occur.
- [ ] **Step 2: Verify RED.** Compile/run `MultiDocumentBindingTests` alone; expect missing cross-session alias guard or singleton language/color behavior, not a modal panel hang.
- [ ] **Step 3: Implement destination and UI binding.** Share one AppDelegate destination validator across explicit and menu Save As paths, compare the candidate's same-descriptor verified identity to other registered baselines, then invoke the existing `DocumentSession.saveCurrentMap(to:)` without changing the 0.4 writer's SHA/inode rules. Reject on uncertainty rather than overwrite another open document. The current `NativeMapFile.write` rechecks its *own* `lastSeen` identity at publication but cannot establish what AppDelegate validated **before** the writer began; add an opt-in expected-destination identity (or expected absence) to its descriptor-relative `lastSeen` check, and pass the AppDelegate preflight identity through `DocumentSession.saveCurrentMap(to:)` for this guarded path. Preserve old callers' default behavior and the second `latest == lastSeen` check. Include a deterministic HEADLESS_TEST path-swap between AppDelegate validation and writer start: the guarded write must conflict without touching the replacement inode/bytes. Refuse document-bound menu actions when `activeSession == nil` *before* showing any file panel. On session activation/removal retarget or clear global `NSColorPanel` ownership and refresh every window's localized strings, Find status and toolbar.
  The stable part of the validator compares a verified destination identity only with *other* sessions:
  ```swift
  let opened = windowSessions.flatMap(\.documents).filter { $0 !== session }
  if let chosen = try? NativeMapFile.readWithFileIdentity(destination).identity,
     opened.contains(where: { $0.nativeIdentity == chosen }) {
      throw NativeMapFile.FileError.conflict
  }
  ```
  This excerpt does not satisfy the race requirement by itself: the final publication must revalidate a destination identity through the writer's descriptor-relative check, or reject a destination that cannot be proven unchanged. Review must reject a check-then-rename-only implementation.
- [ ] **Step 4: Verify GREEN and regressions.** Compile/run `MultiDocumentBindingTests`, `MultiDocumentCloseTests`, `MultiDocumentOpenTests`, `DocumentSessionIsolationTests`, `NativeDocumentJourneyTests`, `MindNodeArchiveTests`, `VideoCanvasTests`, `AppLanguageSettingsTests`, `SearchWorkbenchTests`; production link and diff check. Read-only review must explicitly inspect cross-session Save As TOCTOU and stale color-target safety.
- [ ] **Step 5: Review then commit.** Stage only scoped files and commit `Bind saves and UI state to live document sessions`. Task 79 visible tabs then consumes the same `WindowSession.documents` and `closeDocument` interface. Do not ship this intermediate state.
