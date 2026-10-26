# OpenMindFlow 窗口与左侧主干：2026-10-27 手测反馈跟进

## 用户实证与验收界线

- 用户对 2026-10-26 独立候选的截图表明：最大化后仅窗口中央原始内容大小的暗灰画布有背景，外围为纯黑；用户还亲自报告四边无法用鼠标拉大。这两项是**旧候选的问题**，不能用 `.resizable` 声明或程序化 `setFrame` 宣称实体手势已经修复。
- 另一张用户截图表明：左侧一级分支带两个后代时，从根节点到该一级分支的青色主干明显弯曲，期望更平直。图中根边连接高度约 463 px，左侧一级分支下划线约 499 px；用户未提供源文档或可安全读取的工作区内保存路径，不能假设其节点曾被手动定位。
- 原 2026-10-26 候选 App 可能包含未保存内容；不得关闭、替换、操作它。旧手测 App、首版预览 ZIP、原始 `.mindnode` 同样受保护。

## 复现与根因

合成、**从未显示/激活**的 AppKit 窗口在 `1280×700` 内容上运行 `Tests/WindowContentSizingTests.swift`，请求改为 `1800×1050`：RED 编译退出 0、运行退出 1；`NSWindow.frame` 一度变成 `1800×1082`，但 content、split、canvas 均滞留 `1280×700`，同步布局还会把窗口弹回初始大小。离屏约束诊断发现 `NSSplitViewController` 上名为 `NSViewController.preferredContentSize.width/height` 的固定 `1280×700` 约束优先级 **501**，高于 `NSWindow-current-width/height` 的 **500**。此固定约束能同时解释旧窗口最大化后的中央绘制矩形和程序化尺寸被弹回，亦与用户实体边缘不能拉大的观察一致；但只有新候选的用户手势能最终确认后者。`Sources/App.swift` 只移除 `split.preferredContentSize`，窗口构造和 `setContentSize` 仍分别提供明确初始尺寸。

左侧青色曲线并非 Bézier 数学溢出：自动布局居中的是一级节点的框，`branchConnectorEndpoints` 从根节点中线连接到子节点下划线；框的中线虽相同，下划线却低约半个一级节点高度减 7 点。调整仅是**线条端点**：左侧首级连接在根节点侧边允许范围内顺着下划线高度水平进入，并在越过顶部/底部内边距时连续钳制，右侧/非首级连接不变；节点、导入原生坐标及持久化数据均不移动。

## 验证状态

- 初次离屏尺寸回归 RED 编译 0/运行 1；删去固定首选尺寸后同一回归 GREEN 编译 0/运行 0，检查内容/分栏/画布在 `1280×700 → 1800×1050 → 980×600` 三档均同尺寸，并比较放大后两端角落与放大前实际背景像素。
- 左侧主干新断言 RED 编译 0/运行 133；只修正内部连接端点后 GREEN。独立复审指出越过 `root.maxY−inset` 的离散回弹，于是又加外侧/临界点 RED 编译 0/运行 133，改用连续钳制后聚焦 `LeftBranchCanvas`、`LeftBranchLayout`、`Layout`、`WindowContentSizing`、`CanvasCommand` 皆编译及运行退出 0。
- 首轮 40 组中 39 组通过，`OutlineWorkbenchTests` 编译 0/运行 133：既有合成测试在附加分栏控制器后未执行实际 `AppDelegate` 已有的明确 `window.setContentSize`，去掉首选尺寸后测试窗自收缩至 500×500；仅将测试启动顺序与生产一致，附加后设置 1000×700 并同步离屏布局，仍验证整窗画布及六次侧栏切换，聚焦重新编译/运行 0/0。第二轮全新完整矩阵在 `/var/folders/nk/l61l2jns4sx3pqkx4zzbsy740000gn/T/OpenMindFlow-window-fix-verified.YhWFg8CW/exits.tsv` 列出 40 组分别编译/运行 **0/0**，`LeftBranchInteractionTests --review/--model/--drag` 三模式各 **0**，总命令退出 **0**；此前首轮仅记为中间诊断而不冒称PASS。
- 本机 arm64 新候选为 `build/OpenMindFlow-WindowFix-20261027.app`（bundle ID `local.openmindflow.windowfix.20261027`）及 `dist/OpenMindFlow-WindowFix-20261027.zip`；Info.plist lint 与 ZIP 完整性通过。首次直编译包只有 linker-generated ad-hoc 可执行签名，`codesign --verify` 曾因未封口的 bundle 退出 1；新候选仍未启动，已只对其执行本机 `codesign --force --sign - --timestamp=none` 并重新打包，`codesign --verify --strict` 退出 0。最终 ZIP SHA-256 `5d6cafa9ab27a749d9b3e355af5723599e5aed65ce575cb5ef1f5d9a1b8395b1`；包内与 App 可执行文件 SHA-256 同为 `ab06a8b8be3a8a0f04b64f7fdfaa4d716e3ec45bd081e553f0ed629898b87579`。仍只有本地 ad-hoc 资源封口，无团队 ID/开发者身份/公证，不是第二个正式签名预览；旧候选、旧手测 App、首版预览及旧 `build/MindMap.app` 的受保护哈希均复核不变。
- **真实窗口四边实体鼠标拖拽、新候选最大化视觉与用户图上的具体主干视觉仍未在新候选亲测**。没有执行全局 HID、旧 AX/可见自动化或使任何受保护 App 失焦/退出的操作。使用新路径和新 bundle ID 交由用户复测，不能把窗口 frame 设置、离屏位图或静态 `.resizable` 冒充物理PASS。
