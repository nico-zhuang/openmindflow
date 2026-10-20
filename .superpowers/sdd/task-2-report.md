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
