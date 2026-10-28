# OpenMindFlow Settings and Stable Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver distinct light/dark document tab chrome, polished three-page native Settings, meaningful stable/Beta GitHub update checks, and a separately built 0.6.0 stable artifact in the existing private repository.

**Architecture:** Keep `DocumentTabStrip` paint changes independent of `AppDelegate`. Change `ReleaseChecker` through injected transport and explicit release-channel/outcome types; then bind it to the three grouped Settings pages in `AppDelegate`, retaining existing preference keys. New 0.6-only guarded build/package scripts reuse safe 0.5 behavior without editing the old scripts; publication is a final verified step.

**Tech Stack:** Swift 6.2, AppKit, URLSession, Foundation, macOS arm64 26, shell, GitHub CLI.

## Global Constraints

- Approved design: `docs/superpowers/specs/2026-10-29-openmindflow-settings-stable-release-design.md`.
- Work only on `feature/native-editor-v2`; do not alter original `.mindnode`, existing running apps, historical 0.4/0.5 bundles, `.mflw` payloads or old packaging scripts.
- Settings has exactly General, Keyboard Shortcuts and About pages; preserve `checkUpdatesAutomatically` default false, language/appearance/node/shortcut preference semantics and bilingual accessibility.
- Current remote is private. Anonymous API 403/404 cannot mean up-to-date; no token in bundle, no visibility change or assertion that anonymous automatic checks work on a private repo.
- Tags `vX.Y.Z-beta.N` + GitHub prerelease=true versus `vX.Y.Z` + prerelease=false; new candidate is 0.6.0 stable only by explicit user decision. Ad-hoc is not Apple Developer ID or notarization.
- Headless compilation: `swiftc -suppress-warnings -D HEADLESS_TEST Sources/*.swift Tests/NAME.swift -framework AppKit -framework AVKit -framework AVFoundation -o PRIVATE/NAME`. Do not run `Tests/AppAccessibilityTests.swift` or global AX/HID.

---

### Task 1: Distinct adaptive tab strip [independent `Sources/DocumentTabStrip.swift`]

**Files:** Modify `Sources/DocumentTabStrip.swift`; create `Tests/TabStripSurfaceTests.swift`.

**Interfaces:** Existing `TabStripView.draw(_:)`; no model or document transfer API changes.

- [ ] Write isolated AppKit test constructing `TabStripView` for `.horizontal` and `.vertical` with `.aqua` and `.darkAqua`; render an opaque bitmap of an unselected, non-drop area; assert background differs from resolved `NSColor.windowBackgroundColor`, alpha is opaque, boundary separator differs, and selected title remains identifiable. Use `NSApp.setActivationPolicy(.prohibited)` and no global screen or user window.
- [ ] Compile/run test against untouched source; confirm failure because existing `draw` returns before painting when `previewIndex == nil`.
- [ ] Implement opaque appearance-adaptive neutral fill and one-pixel separator in `draw(_:)` **before** insertion-preview guard; ensure horizontal separator sits at canvas edge and vertical at canvas edge. Preserve drag insertion drawing over background; do not change `MapCanvas.canvasBackground`.
- [ ] Rerun new test and `TabChromeInteractionTests`, `DocumentTabStripTests`, `TabDragSignalTests`, and `DocumentTabTransferTests`; inspect rendered Aqua/Dark strips; commit just Task 1 scope.

### Task 2: Release list parsing, channels and private-error outcome [independent `Sources/ReleaseChecker.swift`]

**Files:** Modify `Sources/ReleaseChecker.swift`, `Tests/ReleaseCheckerTests.swift`.

**Interfaces:** `ReleaseChannel: String` (`stable`, `beta`), `ReleaseCheckOutcome` (`newer(ReleaseInfo)`, `upToDate`, `noPublishedRelease`), `ReleaseCheckError.accessRestricted`; `ReleaseChecker.check(currentVersion: String, channel: ReleaseChannel, completion: @escaping (Result<ReleaseCheckOutcome,Error>) -> Void)`. Preserve injection `init(fetch: @escaping Fetch)` and single callback; `ReleaseChecker.releasesPage` is the exact canonical browser target.

- [ ] Replace old single-object fixture with JSON Release array tests. Add RED cases: stable ignores newer `v1.11.0-beta.2`; Beta accepts it; stable final `v1.11.0` outranks same-core Beta; shuffled list chooses numeric max; drafts and tag/prerelease mismatches cannot win; current `1.11.0-beta.2` never downgrades to `1.11.0-beta.1`; empty `[]` differs from up-to-date; 403/404 are `accessRestricted`; invalid URL, oversized body, mismatch response URL and duplicate callbacks fail safely. Test request targets exact `/releases?per_page=30`, no cookies, 10s timeout.
- [ ] Compile/run RED; ensure failures represent absent enum/signature and old `/latest` assumption, not syntax typos.
- [ ] Parse strict ASCII `v?major.minor.patch(-beta.positiveInteger)?`, compare numeric three-part core then stable > same-core Beta, reject overflow/leading zero or unexpected suffix; enforce draft/prerelease consistent with tag, canonical HTTPS exact release URL, finite count and response bytes. Select highest eligible newer version by channel; distinguish `[]` from eligible-but-old releases. Keep no-redirect ephemeral URLSession and one-shot callback semantics.
- [ ] Rerun tests incl. adversarial `ReleaseCheckerTests`; commit only the checker and its tests. Do not call AppKit or embed credentials here.

### Task 3: Three-page native Settings layout and update status [after Task 2]

**Files:** Modify `Sources/App.swift`, `Sources/Localization.swift`, `Tests/AppLanguageSettingsTests.swift`, `Tests/AboutSettingsTests.swift`; create `Tests/SettingsVisualLayoutTests.swift` if existing test structure is insufficient.

**Interfaces:** AppDelegate may inject a `ReleaseChecker` transport for tests; use Task 2 result enum and stable/beta preference key `updateChannel`; current build `OpenMindFlowReleaseVersion` fallback to bundle numeric version. Keep existing selectors `chooseLanguage`, `chooseSettingsAppearance`, `chooseShrinkNewNodes`, `chooseNodeShortcut`, `resetNodeShortcuts`, `showAbout`.

- [ ] Add RED tests on unmodified UI: 620×470 grouped three-page geometry in Aqua/Dark and English/Chinese, long label and six shortcut row nonoverlap, About version/credits/disclosure, channel stable default and Beta selection persistence, manual Check Now injected 403/404 inline actionable status plus exact GitHub browser button, success newer/up-to-date/empty status, auto-check opt-in OFF and channel consistency. Set NSApplication activation `.prohibited`; no live network or modal alerts in tests.
- [ ] Verify RED on old fixed 540×390 placement and absent channel/status, without disturbing running apps.
- [ ] Refactor Settings page layout to consistent compact nav, aligned groups and keyboard list with bottom restore. Preserve identifiers for behavior tests, update recursive view lookup only where nested containers require it; ensure bilingual relabeling refreshes new headings/status/segment. About exposes current version, explicit stable/Beta selector with short caution, opt-in checkbox, Check Now, truthful status and trusted GitHub link. `checkForUpdates` uses injected checker; do not show false “latest public release” on unauthorized/empty response. Preserve no automatic installation and no implicit network on Settings open.
- [ ] Rerun layout, `AppLanguageSettingsTests`, `AboutSettingsTests`, `LocalizationTests`, `ReleaseCheckerTests`, and scoped GUI bitmap verification; commit Task 3 UI/tests.

### Task 4: Unique 0.6 stable packaging and verified private GitHub Release [after Tasks 1–3]

**Files:** Create `scripts/build-openmindflow-0.6-stable-local.sh`, `scripts/package-openmindflow-0.6-stable-dmg.sh`, `Tests/StablePackageSafetyTests.sh`; update `README.md`, distribution notes and any tracked release record. Do not change `scripts/build-openmindflow-tabs-0.5-local.sh` or `scripts/package-openmindflow-tabs-0.5-dmg.sh`.

- [ ] Add RED script tests: reject previously occupied app/dmg, symlink, non-0700 or protected target; require stable Info.plist version `0.6.0`, explicit release tag/channel, unchanged `.mflw` UTI, icon SHA-256 and signature. Run against nonexistent new script first.
- [ ] Create new scripts with exact path/owner/permissions and exclusive output constraints; compile production with `Sources/*.swift`, copy verified icon, write 0.6.0/build 7/stable Info.plist, ad-hoc sign, verify. DMG script retains source/stage/mount signature and manifest equality, read-only mount and safe detachment. ZIP extraction must independently reverify signature and bytes; never delete old releases.
- [ ] Run final safe headless suite, new bundled key-window rename regression, independent native settings/nav visual checks, independent code review, DMG verify/mount, ZIP roundtrip, old 0.4/0.5 SHA checks and `git diff --check`; document precisely what was not physically tested on the new candidate.
- [ ] Commit only verified changes. Push feature branch without force; create stable `v0.6.0` tag/Release in existing **private** GitHub repository only after confirming no existing tag/release, unique artifact SHA, exact signed build and tests. Release title Stable, `prerelease=false`, body clearly states private access and ad-hoc/non-notarized limitation, bounded MindNode v9 interoperability, no automatic installation. Verify GitHub release API metadata, assets download SHA and branch status. Do not change visibility, merge main or represent stable as notarized.

## Self-review

All four user requests map to Tasks 1–4. Task 2 and Task 1 have disjoint production/test files and can execute in parallel; Task 3 depends on Task 2 API, Task 4 depends on all three. Maintain TDD RED/GREEN, independent AppKit render versus physical user's visual judgment, and truthfully report the private-repo anonymous-update limitation.
