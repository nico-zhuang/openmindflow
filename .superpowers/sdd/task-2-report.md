# OpenMindFlow 0.6 Task 2 — Release checker

**Status: DONE_WITH_CONCERNS** — checker and injected tests pass; `Sources/App.swift` remains owned by the concurrent UI agent and still calls the obsolete API as of this task's verification. Lead must integrate and run the full application build after that owner updates the call. Board task-87 remains **in progress** for Lead review; Lead was asked to claim its latest revision because this delegated toolset exposes no board operation. No files staged or committed.

## Scope

Modified only `Sources/ReleaseChecker.swift` and `Tests/ReleaseCheckerTests.swift` for implementation/tests, and this report. Did not edit the app, tab strip, build scripts, docs, user documents or authentication. Existing unrelated historical Task 2 evidence below is retained verbatim. `git status --short` also showed another agent's untracked `Tests/TabStripSurfaceTests.swift`, not owned or touched here.

## TDD RED / GREEN

- **RED** after replacing the old single-object tests with release-array cases: `swiftc Sources/ReleaseChecker.swift Tests/ReleaseCheckerTests.swift -o /tmp/openmindflow-release-task87-tests` → exit **1**, compiler diagnostics `cannot find type 'ReleaseCheckOutcome' in scope`, `cannot find type 'ReleaseChannel' in scope`, old `check(currentVersion:completion:)` rejects `channel:`, and missing `ReleaseChecker.releasesPage`. These are missing-interface failures, not syntax errors.
- **GREEN** after checker implementation: `swiftc Sources/ReleaseChecker.swift Tests/ReleaseCheckerTests.swift -o /tmp/openmindflow-release-task87-tests && /tmp/openmindflow-release-task87-tests` → exit **0**, `release list channels, semver, restrictions, trust boundaries and one-shot tests passed`. Repeated after extra numeric Beta test; exit **0** with the same output. `git diff --check -- Sources/ReleaseChecker.swift Tests/ReleaseCheckerTests.swift .superpowers/sdd/task-2-report.md` → exit **0** (no diagnostics).

## Behavior verified and caveats

- Exact HTTPS GitHub Release list endpoint with `?per_page=30`, no cookies, 10-second request timeout, and canonical `releasesPage`. Injected fetch retained. Default live fetch uses ephemeral cookie-free session, explicitly rejects redirects, and cancels streaming response once 128 KiB is exceeded; callbacks are one-shot.
- Stable excludes prereleases; Beta includes both channels; numeric core and Beta ordinal comparison selects highest valid release regardless of list order, with stable final outranking same-core Beta. Rejects malformed/overflow/leading-zero versions and metadata type errors; drafts, mismatched tag/prerelease and noncanonical Release URLs cannot win. Empty/ineligible list reports `noPublishedRelease`, eligible but not newer reports `upToDate`, 403/404 report `accessRestricted`; all other HTTP/redirect/response-URL failures do not claim up-to-date.
- Tests cover malicious URLs, invalid responses, oversized body/list, shuffled releases, numeric Beta ordering, current Beta downgrade prevention and duplicate callbacks. Live private GitHub access is deliberately not tested anonymously; no token or auto-install. Full app build **not claimed** while concurrent `App.swift` owner has not yet migrated the old checker call to the new channel/outcome API.

## Important Task 2 reviewer finding — real URLSession delegate coverage

- Reviewer identified that the synchronous injected-fetch assertions above never instantiated `BoundedReleaseFetch`. Added `ReleaseFixtureProtocol` with `URLSessionConfiguration.ephemeral.protocolClasses` and an internal `ReleaseChecker.sessionFetch(configuration:onRedirect:)` factory; the default live transport delegates to that same factory. The public `ReleaseChannel`, `ReleaseCheckOutcome`, and `check(currentVersion:channel:completion:)` interfaces are unchanged. Fixture intercepts requests in-process, never contacts GitHub, and uses no credentials or UI.
- **Test-first RED:** `swiftc Sources/ReleaseChecker.swift Tests/ReleaseCheckerTests.swift -o /tmp/openmindflow-release-task87-delegate-tests && /tmp/openmindflow-release-task87-delegate-tests` → exit **1**, `type 'ReleaseChecker' has no member 'sessionFetch'` (with cascading `.stable` inference diagnostic). A later assertion-first redirect-observer step produced exit **1**, `extra argument 'onRedirect' in call`. An initial protocol redirect fixture hung (exit **133** after the 3-second guard) even though diagnostic instrumentation confirmed the real `willPerformHTTPRedirection` delegate was invoked; completing the URLProtocol load after reporting its redirect resolved that fixture-specific stall. Temporary diagnostic prints were removed.
- The new tests assert the normal in-process response returns `.newer`, the real redirect delegate is invoked exactly once and the redirected URL is never fetched, and a streamed first **128 KiB** chunk plus one additional byte produces `.tooLarge` and calls `stopLoading` on the held transport. A bounded second-completion wait catches duplicate callbacks after redirect/cancel cleanup. **Mutation RED:** temporarily changing the redirect delegate's `completionHandler(nil)` to `completionHandler(request)` and rerunning the exact command failed with `Assertion failed: Delegate must not follow redirect` (exit **133**); the rejection was restored before final verification.
- **GREEN:** `swiftc Sources/ReleaseChecker.swift Tests/ReleaseCheckerTests.swift -o /tmp/openmindflow-release-task87-delegate-tests && /tmp/openmindflow-release-task87-delegate-tests` → exit **0**, stdout `release list channels, semver, restrictions, trust boundaries and one-shot tests passed`. `git diff --check -- Sources/ReleaseChecker.swift Tests/ReleaseCheckerTests.swift .superpowers/sdd/task-2-report.md` → exit **0**, no stdout. No full app build claimed: concurrent `Sources/App.swift` integration remains Lead/app owner responsibility. No staging or commits.

---

# Task 2 — native editor evidence

Branch: `feature/native-editor`. Scope: independent AppKit application; no original application launched, no REA MCP, no changes to `docs/static-evidence.md` or the import plan.

## TDD

1. Read `.superpowers/sdd/task-2-brief.md` first, then existing `Sources/MapModel.swift`, `Tests/MapModelTests.swift`, and the design spec. Added `Tests/LayoutTests.swift` **before** the layout implementation. It asserts stable frame coordinates across recomputation, distinct ordered sibling bounds, separated multiple roots, folded descendants hidden, empty roots, and JSON roots roundtrip (titles, IDs, folded state).
2. RED command: `swiftc Sources/MapModel.swift Tests/LayoutTests.swift -o /tmp/mindmap-layout-red`. Compiler exit **1**, `cannot find 'layout' in scope` (expected missing implementation). Later renamed the layout function to `mapLayout` because `NSView.layout()` shadows the unqualified global name in the app; tests use the same renamed API.
3. GREEN commands: `swiftc Sources/MapModel.swift Sources/Layout.swift Tests/LayoutTests.swift -o /tmp/mindmap-layout-tests && /tmp/mindmap-layout-tests` → `layout and JSON roundtrip tests passed`; `swiftc Sources/MapModel.swift Tests/MapModelTests.swift -o /tmp/mindmap-model-tests && /tmp/mindmap-model-tests` → `model tests passed`. Folded-parent child visibility is provided by existing `MapModel.addChild()` unconditionally clearing the parent's fold state (tested in existing model suite), and layout visits that child.

## Build

`bash build.sh` → `Built build/MindMap.app` (exit 0). `plutil -lint build/MindMap.app/Contents/Info.plist` → `OK`. `test -x build/MindMap.app/Contents/MacOS/MindMap` → executable exists. The build uses only installed `swiftc` and AppKit, with a real bundle Info.plist. No dependency, original artwork, or original app runtime is involved.

## Launch / interaction evidence

`open build/MindMap.app` → exit 0; `pgrep -fl 'MindMap.app/Contents/MacOS/MindMap'` identified the independent process. macOS accessibility returned window `Untitled — MindMap`. System Events sent Tab; the window then exposed an `AXTextField`. Typing was reflected in that text field. Return resulted in a new blank native text field, and typing a sibling title followed by Cmd-S presented the macOS Save panel. A new own-format `Untitled.mindmap.json` was created; direct inspection confirmed one root and two different children with unique IDs, `ChildAChild B` and `Sibling`. This disposable test document was verified by exact path/content, the app was quit, and the document was removed. No pre-existing user document was opened or changed.

**Not verified:** Screen captures unexpectedly showed a different foreground application despite the MindMap process reporting `frontmost = true` via Accessibility. Accordingly the custom-drawn canvas, visible fold state, arrow navigation, Delete, Space, undo/redo, gestures, and zoom/pan were **not visually smoke-verified**. Their code compiles; layout/fold/model behavior has assertion coverage, but no claim of runtime UI parity is made. Do not infer visual control verification from the app launch or static code.

## Data safety and boundaries

Open and Save accept filenames ending only in `.mindmap.json`; `.mindnode` is neither opened nor written. JSON decoding failures show `NSAlert` without replacing the current model; saving encodes roots and writes atomically, showing `NSAlert` on errors. Opening another file or quitting with unsaved changes prompts Save/Cancel/Discard; canceled/failed saves abort the destructive action. Multiple roots are laid out separately; empty roots render an empty state. Shortcut editing uses native `NSTextField`; geometry is deliberately independent rather than copied.

## Post-review repair, independently verified

The review found unguarded window close, missing Shift+period, first-key IME bypass, dark contrast and inaccessible drawn nodes. Changes add a Save/Cancel/Discard guard to window close, forward first printable key events to native `NSTextField.currentEditor()`, add Shift+period, use dynamic system colors and expose labeled/selected/pressable accessibility nodes. `Tests/AppAccessibilityTests.swift` tests own-app accessibility and the unsaved close → Cancel → retained map → Discard → app exit flow.

Lead ran `bash build.sh`, the model/layout/import suites, `plutil -lint`, `open build/MindMap.app && swift Tests/AppAccessibilityTests.swift`, and bounded `swift Tests/AppAccessibilityTests.swift --close-flow`: all exited 0; the AX checks printed `own-app AX node, selected state and Press action passed` and `own-app close Save/Cancel/Discard prompt, cancel retention and confirmed exit passed`. Actual Chinese IME composition, dark/light screenshots, gestures and original app runtime parity remain unverified.

## Retained AX selection re-review repair

`MapCanvas` now synchronizes selected state on its shared `needsDisplay` invalidation path (used by keyboard, pointer, AX Press, model edits, undo/redo and model replacement) and posts `.selectedChildrenChanged` when selection changes. Existing native field editing and the guarded close path remain unchanged. The optional own-app `swift Tests/AppAccessibilityTests.swift --selection-refresh` retains root/child AX elements, creates a child with Tab, then AX-presses the retained root and verifies both retained `AXSelected` values flip without re-fetching those elements. Before the source change it exited **133** at `Retained root must become selected again` (after app startup); after the fix it prints `own-app retained AX selection refresh passed` and exits **0**. An initial immediate-after-open run found no node due to app startup timing; the red reproduction was rerun after startup. Fresh `bash build.sh` → `Built build/MindMap.app` (exit **0**); `swiftc -typecheck Tests/AppAccessibilityTests.swift` (exit **0**); model/layout/import suites printed their respective passed messages (each exit **0**). Fresh own-app combined `swift Tests/AppAccessibilityTests.swift --selection-refresh --close-flow` printed the initial AX, retained selection and Cancel/Discard exit passed messages (exit **0**). No original app, private user document, or REA MCP was used.
