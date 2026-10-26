# OpenMindFlow Polish and Local Release Preparation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不碰运行中旧/新候选与来源文件的前提下实现用户指定图标、精简 UI、空白粘贴和媒体拖放、稳定吸附、About 和安全更新检查，制作仅供本机验证的新候选/DMG。

**Architecture:** 模型 `MapModel` 原子追加独立根与清选择；`MapCanvas` 负责画布锚点、AppKit pasteboard/drag 和吸附候选显示；`StyleInspector` 自持三个文字 tab；`AppDelegate` 负责 toolbar、Settings/About、更新检查入口。图标作为 tracked `Assets/OpenMindFlow.icns` 由新的拒绝覆盖脚本复制到全新 App Bundle。更新检查独立为可注入 transport，真实安装/正式发行不属于可自动完成的局部实现。

**Tech Stack:** Swift 6.2.1 / arm64 macOS 26 / AppKit / Foundation URLSession / AVKit / AVFoundation / `swiftc -D HEADLESS_TEST`；独立本地 ad-hoc Bundle 和只读 `hdiutil verify`。

## Global Constraints

- 不运行 `build.sh`、可见 GUI/AX/global HID 或多测试通配符；只编译列出的 `Tests/*.swift` 名称。
- 不覆盖现有 `build/MindMap.app`、`build/MindMap-Feedback-20261026.app`、`build/OpenMindFlow-Candidate-20261026.app`、`build/OpenMindFlow-WindowFix-20261027.app`、`dist/MindMap-First-Release-Preview-20261024.zip` 及任何 `.mindnode`/用户导出；不关闭运行中的进程。
- 不上传 GitHub Release、不 push/merge，不把 ad-hoc DMG 称为 Gatekeeper/Developer ID 公证发行；无正式 LICENSE 时不得假称特定许可证。
- 具体交互和剩余人工验收以 `docs/superpowers/specs/2026-10-27-openmindflow-polish-design.md` 为准。

---

### Task 1: Integrate verified icon and non-overwriting local bundle builder (shared task task-63)

**Files:** Create `Assets/OpenMindFlow.icns`, `scripts/build-openmindflow-local.sh`, `Tests/run-icon-package-safe.sh`.

**Interfaces:** 只接受明确新路径的 `.app` 输出和新 bundle ID/version/build 参数；导出供交付调用的完整 ad-hoc 打包入口，不触碰旧包。

- [ ] **RED:** 针对不存在的 `Assets/OpenMindFlow.icns`、新脚本及 Info `CFBundleIconFile` 的安全 shell 测试先失败；对用户 ZIP/ICNS 的 SHA-256 做只读比对。
- [ ] **GREEN:** 拷贝 v2.1 fallback ICNS；使用 `swiftc Sources/*.swift -framework AppKit -framework AVKit -framework AVFoundation` 仅在新 `.app` 中构建；设置 `LSMinimumSystemVersion` 26.0、`Contents/Resources/OpenMindFlow.icns`、完整 ad-hoc 签名并拒绝存在路径。
- [ ] **VERIFY:** `bash Tests/run-icon-package-safe.sh` 对全新 scratch app plist、icon hash、`codesign --verify --strict`、第二次拒绝覆盖分别取有效退出码；不运行 app。提交资产/脚本/测试。

### Task 2: Inspector text tabs and compact toolbar

**Files:** Modify `Sources/StyleInspector.swift`, `Tests/StyleInspectorTests.swift` (shared task task-64); modify `Sources/App.swift:2328-2364`, `Tests/ToolbarCompactTests.swift` (Lead).

**Interfaces:** 文字 Style/Notes/Themes，仍用段索引 0/1/2；`NSToolbar.displayMode = .iconOnly`，默认标识 `main,child,sibling,fold,fit,outline,style`，Undo/Redo 保留 Edit 菜单/允许定制。

- [ ] **RED:** 离屏断言 Style/Notes/Themes 的 `.label(forSegment:)` 与 `.image(forSegment:) == nil`、内边距顶部实测；新工具栏断言七个默认项/九个允许项与 iconOnly，运行各目标 `swiftc -D HEADLESS_TEST Sources/*.swift Tests/StyleInspectorTests.swift ...` 及 `Tests/ToolbarCompactTests.swift` 观察预期失败。
- [ ] **GREEN:** 最小文字 tab 和工具栏 ID/模式更新，不改各 selector、page/note commit；仅在内部空白实测超阈值时调整约束。
- [ ] **VERIFY:** 各聚焦测试编译运行 0/0，`AppLanguageSettingsTests` 与 `OutlineWorkbenchTests` 安全离屏通过后分别提交 scoped 改动。

### Task 3: Root insertion, blank selection and bounded media ingestion

**Files:** Modify `Sources/MapModel.swift`, create `Tests/BlankRootInsertionTests.swift` (shared task task-65); modify `Sources/App.swift:1174-1280,1720-1740`, add `Tests/BlankCanvasPasteTests.swift`, `Tests/CanvasMediaDropTests.swift` (Lead).

**Interfaces:** `MapModel.clearSelection() -> Bool`, `MapModel.insertRoot(title: String, image: MapImage? = nil, video: MapVideo? = nil, at worldCenter: CGPoint) -> Bool`；canvas 清选择无脏/Undo；选中时延续原粘贴模式，空白时所有媒体/文本独立根；媒体解码与 8/16MiB+32MiB 文档预算优先于写入。

- [ ] **RED:** 编译/运行新增 model test 验证清选择和原子插入之前先失败；新增 canvas test 用本地命名 `NSPasteboard`（不改系统剪贴板）验证空白文本替换错误/媒体成子节点错误；模拟 `NSDraggingInfo` 或可测试的 `performDrop` 内核验证无外部拖入处理。
- [ ] **GREEN:** 模型创建新 UUID/root 世界坐标，先校验再保存一次；canvas 空白 click 清 `selectedIDs`、保留 blank paste point，统一有界媒体解码和 root/child routing；注册外部 Finder 文件 URL/图片拖入，只读粘贴板格式。
- [ ] **VERIFY:** 新模型/画布三套及旧 `MapModelTests`、`MapClipboardTests`、`ClipboardCanvasTests`、`CanvasImageTests`、`VideoCanvasTests`、`OwnDocumentTests`、`CanvasGestureTests` 逐个离屏通过，不启动任何可见窗口，提交分段修复。

### Task 4: Drag target stability without breaking collision previews

**Files:** Modify `Sources/App.swift:591-797,1838-1892`, `Tests/CanvasCommandTests.swift`, create `Tests/DragTargetLatchTests.swift`.

**Interfaces:** 每次拖动 cache 目标 UUID/位置/插入 index；目标显示时位置变化不修改 canonical 命中；明显离开/取消时解除；松开时仅重新验证锁定目标合法，执行一次模型 mutation/Undo。

- [ ] **RED:** 构造 preview spring tick 移动的同级目标，离屏 `NSEvent` 下断言 preview 和 mouseUp 不一致、随目标躲闪失败；增加离开/取消后不提交的案例。
- [ ] **GREEN:** 延迟吸附并锁定 canonical 目标，加迟滞和重验证；保持排斥视觉无重叠、现有 `.65` 命中及折叠隐藏子孙规则。
- [ ] **VERIFY:** `CanvasCommandTests`, `CanvasGestureTests`, `LeftBranchInteractionTests --review/--model/--drag`, `DragTargetLatchTests` 安全通过，审阅真实呈现与 canonical 候选一致性再提交。

### Task 5: About identity and conservative online update checks

**Files:** Modify `Sources/App.swift:2434-2651`, `Sources/Localization.swift`, `Tests/AppLanguageSettingsTests.swift`; create `Sources/ReleaseChecker.swift`, `Tests/ReleaseCheckerTests.swift`.

**Interfaces:** Settings segmented third `About`; About credits exact `NicoZhuang | KEEPCRAZY | YoSoAi`、独立开发、MindNode 只读兼容、IdeasOnCanvas 无关联；checkbox `checkUpdatesAutomatically` 默认 false；注入 transport 的 ReleaseChecker 仅验证公共 GitHub Releases 元数据，提示用户并将官方 Releases 页交给系统浏览器，不下载/替换 App。

- [ ] **RED:** 第三页/About 标签及中英动态切换、默认无网络、URL/版本/恶意 API URL 无副作用的离屏测试先失败。
- [ ] **GREEN:** Settings 加 About、checkbox/检查按钮、可替换 HTTPS transport；仅用户 opt-in 调度自动检查；跳浏览器前限制 host/repo/HTTPS，并复用当前 main bundle 版本。
- [ ] **VERIFY:** `AppLanguageSettingsTests`、`ReleaseCheckerTests`、`LocalizationTests` 和相邻菜单测试 0/0；记录自动下载/安装尚未实现，不宣传正式在线自动更新。

### Task 6: Local DMG and final independent hand-test candidate

**Files:** Create `scripts/package-openmindflow-local-dmg.sh`, `Tests/run-local-dmg-safe.sh`; update `README.md`, `docs/2026-10-26-candidate-manual-handtest.md`, new follow-up docs.

**Interfaces:** 只接受 Task 1 构建的唯一、此前不存在的 app 与 DMG 输出路径；`hdiutil create`、`hdiutil verify`、包签名与 icon/Info 哈希核对；文件名和内部图标叫 OpenMindFlow。

- [ ] **RED:** 离屏 shell 验证已有目标拒绝覆盖、错误 bundle ID 拒绝、缺图标拒绝先失败。
- [ ] **GREEN:** 构建全新独立路径的开发候选，真实 DMG 原型，绝不调用或覆盖已有候选，也不 publish/push。
- [ ] **VERIFY:** 40+ 显式安全离屏测试矩阵（逐个指定文件，绝不 `Tests/*.swift`）及新增测试 0/0；`codesign --verify --strict`, `hdiutil verify`, ZIP/DMG archive/app icon 哈希、独立只读复审通过；用户实机 GUI/拖拽仍未通过前在交付文字标作待用户醒来验。
