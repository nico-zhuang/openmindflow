# OpenMindFlow Repository Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 原地改名为私有 `nico-zhuang/openmindflow`，不损及 v0.6.0，更新可信检查器，并独立发布 v0.6.1 稳定包。

**Architecture:** 源码先固定新唯一 GitHub origin、维持拒绝重定向的安全契约；0.6.1 建包与 DMG 使用复制出的专用严格脚本而不改 0.6 模板。离线测试和复核后才改 GitHub 远端；实体镜像验证、ZIP 哈希、完整回归通过后再推分支和新 tag/Release。

**Tech Stack:** Swift 6.2、AppKit、Foundation URLSession、macOS 26 arm64、Bash、`gh` CLI、`hdiutil`。

## Global Constraints

- 已批准设计：`docs/superpowers/specs/2026-10-29-openmindflow-repository-migration-design.md`。只对 owner `nico-zhuang` 的**同一个 PRIVATE 仓库**改名；不转移 owner、创建第二仓库、更改 `main` 或公开可见性。
- 不编辑、重签、覆盖、删除 v0.6.0 tag/Release/两个下载资产及所有历史 0.4/0.5 App/DMG/ZIP/脚本；不改 `scripts/build-openmindflow-0.6-stable-local.sh` 或 `scripts/package-openmindflow-0.6-stable-dmg.sh` 及其两个安全测试。
- `0.6.1` / build `8` / `v0.6.1` / `stable`；bundle ID `com.nicozhuang.openmindflow`，`.mflw` UTI `local.openmindflow.document`，图标 SHA-256 `3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3`，最低 macOS 26 arm64；仅 ad-hoc 签名、未公证。
- 所有新产物仅在新建的本 UID、0700、无 symlink 的 `/private/tmp/openmindflow-local-[A-Za-z0-9]+` 独立目录；不覆盖 `/Applications`、`dist/`、既有目录或用户源 `.mindnode`；只按精确设备血缘卸载**自己**的私有镜像，未知状态保留并报告。
- 禁止 `Tests/AppAccessibilityTests.swift` 和会抢前台的 `Tests/TabRenameKeyWindowTests.swift`，不把离屏位图当作用户实机验收。私有仓库匿名 403/404 只能引导浏览器登录，不嵌 token、不自动安装、不声称已有 LICENSE。

---

### Task 1: Checker canonical path with RED/GREEN

**Files:** `Sources/ReleaseChecker.swift`; `Tests/ReleaseCheckerTests.swift`; inspect read-only `Tests/AboutSettingsTests.swift`, `Tests/SettingsVisualLayoutTests.swift` and `Sources/App.swift`.

**Interfaces:** `ReleaseChecker.endpoint`, `.releasesPage` retain `URL` type and exact static access; `check(currentVersion:channel:completion:)` and `ReleaseCheckOutcome` unchanged.

- [ ] In checker tests, set independent expected endpoint to `https://api.github.com/repos/nico-zhuang/openmindflow/releases?per_page=30` and expected browser page to `https://github.com/nico-zhuang/openmindflow/releases` (do not reuse production constants). Assert old response URL `https://api.github.com/repos/nico-zhuang/mindnode-reconstruction/releases?per_page=30` returns `.invalidResponse`, old tag page `https://github.com/nico-zhuang/mindnode-reconstruction/releases/tag/v1.10.0` cannot produce `.newer`, and redirect fixture never fetches its destination; retain 403/404, 128 KiB, 30-entry, one-shot cases.
- [ ] Run `scratch="$(mktemp -d /private/tmp/omf-repo-checker-XXXXXXXX)"; swiftc -suppress-warnings Sources/ReleaseChecker.swift Tests/ReleaseCheckerTests.swift -o "$scratch/ReleaseCheckerTests" && "$scratch/ReleaseCheckerTests"`; expected **RED** for new exact URL assertions while production still points old path.
- [ ] Change only the two static constants in `Sources/ReleaseChecker.swift` to the new exact API and page strings above; do **not** add redirect follow, legacy aliases or credentials.
- [ ] Re-run checker, then `scratch="$(mktemp -d /private/tmp/omf-repo-about-XXXXXXXX)"; swiftc -suppress-warnings -D HEADLESS_TEST Sources/*.swift Tests/AboutSettingsTests.swift -framework AppKit -framework AVKit -framework AVFoundation -o "$scratch/AboutSettingsTests" && "$scratch/AboutSettingsTests"`, plus `SettingsVisualLayoutTests` and `AppLanguageSettingsTests` using the same safe command form; expected exit 0. Ensure `git diff --check`; independent reviewer assesses trust boundaries and UI fallback. Commit only tested checker/test changes after approval.

### Task 2: Dedicated build8 scripts and safety fixtures

**Files:** create `scripts/build-openmindflow-0.6.1-stable-local.sh`, `scripts/package-openmindflow-0.6.1-stable-dmg.sh`, `Tests/Stable061BuildSafetyTests.sh`, `Tests/Stable061DmgSafetyTests.sh`; the four 0.6 files are read-only templates.

**Interfaces:** builder takes exact `.../OpenMindFlow-Stable-0.6.1.app`; packager takes that App and same-parent unique `OpenMindFlow-Stable-0.6.1-*.dmg`. Both keep the existing private-parent, symlink, version, codesign, APFS lineage and no-foreign-detach contract.

- [ ] Copy the two 0.6 safety tests to new unique test filenames, then change their expected target script filenames and only new-release literals. Run both while new scripts do not yet exist: expected **RED** with explicit “script missing” rather than syntax errors.
- [ ] Copy the two hardened 0.6 scripts into the two new exact filenames only if the destinations do not exist. In the new copies replace all old release-specific script, app, DMG, stage/mount, volume, manifest, `0.6.0`/build `7`/tag literals with `0.6.1`/build `8`/tag `v0.6.1`; preserve bundle ID, icon digest, UTI, system floor and **all** mounted-image/APFS ownership checks (old script SHA must not change). Keep exact output basename and no-existing/symlink guards before `mkdir` or `hdiutil`.
- [ ] Run `bash -n` on four new files, `bash Tests/Stable061BuildSafetyTests.sh` and `bash Tests/Stable061DmgSafetyTests.sh`; require all existing negative-path, same-UID replacement, malformed/foreign APFS fixture and cleanup failures to pass, plus old 0.6 target rejection. Independently review test assertions and new diff against old scripts before commit.

### Task 3: Controlled GitHub rename and local remote

**Files:** only the actual GitHub repository name and local `.git/config` remote; no historical Release mutation.

- [ ] Confirm clean feature branch, owner/admin permission, target `nico-zhuang/openmindflow` not already resolved, original repo `PRIVATE`, default `main`, existing `v0.6.0` `prerelease=false` with exactly the old DMG/ZIP and fixed SHA; record original branch/tag SHA. Do not assume a 404 proves global slug availability—GitHub rename is final authority.
- [ ] Run `gh repo rename -R nico-zhuang/mindnode-reconstruction openmindflow --yes` **only once** after Tasks 1–2 reviews. If rejected, stop rather than rename a different repo or create a second repository.
- [ ] Read authenticated `gh api repos/nico-zhuang/openmindflow`, `gh api repos/nico-zhuang/openmindflow/releases/tags/v0.6.0` and `git ls-remote git@github.com:nico-zhuang/openmindflow.git` to verify same repo id, PRIVATE, default `main`, old tag/asset metadata and branch. Then `git remote set-url origin git@github.com:nico-zhuang/openmindflow.git` and confirm fetch/push URLs; do not change local folder or main.

### Task 4: Final build, docs, regression, release

**Files:** `README.md` current links/new 0.6.1 section; new `docs/2026-10-29-openmindflow-0.6.1-repository-migration.md`; release notes in new private scratch; no rewrites to historical spec/0.6 record.

- [ ] In a **new** checked UID/0700 scratch create exact `OpenMindFlow-Stable-0.6.1.app` using new builder. Confirm Info.plist version `0.6.1`, build `8`, tag `v0.6.1`, channel `stable`, persistent ID/UTI/icon, `codesign --verify --deep --strict` and `Signature=adhoc`.
- [ ] Package a never-existing `OpenMindFlow-Stable-0.6.1-20261029.dmg` with new packager. Confirm `hdiutil verify`, `-readonly -nobrowse` mounted App strict signature and per-file manifest, protected detach and image absent afterward; if identity is ambiguous retain mount and STOP. In the same new scratch create a never-existing `OpenMindFlow-Stable-0.6.1-20261029.zip`; `unzip -t`, extract to unused private directory, compare every file SHA against signed source App, check extracted metadata/signature.
- [ ] Compile and run all safe `Tests/*Tests.swift`: `scratch="$(mktemp -d /private/tmp/omf-repo-final-XXXXXXXX)"; for source in Tests/*Tests.swift; do name="${source##*/}"; name="${name%.swift}"; [[ "$name" == AppAccessibilityTests || "$name" == TabRenameKeyWindowTests ]] && continue; swiftc -suppress-warnings -D HEADLESS_TEST Sources/*.swift "$source" -framework AppKit -framework AVKit -framework AVFoundation -o "$scratch/$name" && "$scratch/$name" || exit 1; done`; execute three `LeftBranchInteractionTests` modes. Repeat targeted checker/About/settings suites after rename, compare 0.4/0.5/0.6 source scripts, previous binary/DMG/ZIP hashes and v0.6 tag/asset SHA. Independently review full migration diff.
- [ ] Update README current new Release/download URL only after known target; keep old 0.6 SHA and point old asset links at renamed repo. Record new asset hashes and clear warning: v0.6.0 built-in strict checker may not cross rename and requires manual browser download, PRIVATE access, ad-hoc/no notarization/no auto-install. Commit and push only `feature/native-editor-v2` without force; verify remote `v0.6.1` tag absent before creating it, push annotated new tag, publish `Stable` (`prerelease=false`) only after all test/build gates pass.
- [ ] Authenticated GitHub API verifies both `v0.6.0` and `v0.6.1` releases, private visibility, `v0.6.1` latest stable, exactly two new assets; download both into another unique private directory and re-check SHA. Confirm feature branch/tag point to intended commit, main not merged, local tree clean. Give user independent App/DMG/ZIP and caveats; do not mislabel synthetic UI tests as physical acceptance.
