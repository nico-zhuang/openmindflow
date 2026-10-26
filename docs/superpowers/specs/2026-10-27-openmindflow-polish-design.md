# OpenMindFlow 交互完善与本地发行准备设计（2026-10-27）

## 意图与安全边界

用户正在休息，明确授权在可行范围内自行推进并减少打断。本设计采用保守默认值，而不是替用户作出证书、仓库公开、第三方品牌归属或静默安装等不可逆决定。正在运行的 2026-10-26 旧候选与 2026-10-27 修复候选、旧 MindMap 手测包、首版签名预览、来源 `.mindnode` 和现有导出均不能关闭、覆盖或自动操作；新构建使用从未存在的新路径及 bundle ID。只运行列明的离屏测试，不运行 `Tests/AppAccessibilityTests.swift`、可见窗口测试、全局 HID 或遗留 `build.sh`。本设计无需实现源格式回写。

## 素材和产品身份

用户指定 `/Users/nicozhuang/岁金技术中心/DSH-test/OpenMindFlow-icon-package-v2.1.zip`（SHA-256 `eb73418867ceedad2bde43e60ae3e0abfa170f772505c149eb7cdc95a9b6248e`），包内 `fallback/OpenMindFlow.icns` SHA-256 `3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3`。现有机器未安装 Icon Composer，故仅接入该官方素材包提供的传统 `.icns`；不能声称已完成原生 `.icon` 或系统真实 Dock/浅深色视觉验收。所有新界面、候选包显示名 OpenMindFlow。增加新的**拒绝覆盖已有路径**的本地构建脚本，不运行硬编码旧身份/旧路径的 `build.sh`。

## 窗口与交互设计

- 检查器只有 Style、Notes、Themes 三个文字 tab，保留原先页索引、编辑提交和无关联 Notes 禁用语义。按离屏几何判定内部顶部空隙；只调整检查器内部排布，不误把系统标题栏/工具栏空间当作检查器空白，也不破坏 260–320pt 宽度。
- 顶部原生 toolbar 使用 `.iconOnly` 和本地化 tooltip，默认留下 New Main、New Child、New Sibling、Fold/Unfold、Fit Map、Outline、Style 七项；Undo/Redo 保留菜单快捷键和可定制工具栏 allowed ID。不能复制 MindNode 的品牌资产或原生代码。
- 空白单击仅取消视觉/模型选择，不进入 Undo 或脏状态；后续在空白锚点粘贴文本、有效图片或视频成为新的独立根节点，并保持屏幕到世界坐标换算。已有显式选择时维持旧子节点/编辑行为。一次有效插入只生成一份 Undo；非法、超大小、已损坏、非视频/非图片或超 32MiB 文档预算的数据不产生任何节点/Undo。以 `MapImage` ≤8MiB、`MapVideo` ≤16MiB 的真实解码校验为准，读取文件前先查文件字节数；不按扩展名盲信、不能无限 `Data(contentsOf:)`。拖入使用 canvas 的 AppKit 目标视图协议，接收 Finder 的文件 URL 与系统图片 pasteboard；不可抢占原有内部节点拖拽。
- 节点拖动的候选父节点基于**不被动画位移改写的 canonical 几何**锁定 UUID/插入位置，保留适度避让作为视觉反馈；小幅 hover 范围内以迟滞维持吸附，明确离开/取消时解除。松开执行所显示的同一候选，重新验证当前模型有效性；无效则不提交而非悄悄吸附到其他节点。既有碰撞无重叠和 `.65` 子命中阈值不得无依据删除。

## 设置 About、开源声明与更新

- Settings 增加第三个 About tab，显示 `NicoZhuang | KEEPCRAZY | YoSoAi`；明确独立开发、`.mindnode` **只读导入**、与 IdeasOnCanvas **无关联/无背书**。仓库目前无 LICENSE，未获具体许可选择；本轮不擅自标记为 MIT/Apache，不假冒某许可已经生效。先用准确的开源意向及源码入口文字；正式开源许可仍待所有权人选择，避免误称法律状态。
- About 提供「自动检查更新」开关（默认关闭，先经用户自主打开才网络访问）和「现在检查」按钮。Foundation 更新服务通过可替换的 HTTPS transport 向预期的 `nico-zhuang/mindnode-reconstruction` GitHub Releases API 获取最新公开版本，严格检验域、JSON、版本号与 URL，只弹提示并由用户确认后在浏览器打开可信仓库的 Releases 页面；联网失败和仓库尚无 Release 不干扰使用。此阶段**不会静默下载/替换运行的 App，不能声称拥有自动安装**。完整内置自动下载/安装需要稳定产品 bundle ID、可信 EdDSA appcast（例如经过审计的 Sparkle）、发布签名密钥及开发者签名策略，作为明确待办而非装作已实现。
- 建立本地 DMG 原型：唯一新 App 路径，验证本机 ad-hoc 完整资源签名、图标、版本和 ZIP/DMG 完整性；不上传或 GitHub 发布，不把本地 ad-hoc 包称作可公开安全安装。面向 GitHub 的正式 DMG 要 Apple Developer ID Application、hardened runtime、公证/装订、被隔离机上 Gatekeeper 实测、权利与 LICENSE 核准和拥有者发布授权；没有这些不能宣称交付正式在线更新。

## 分阶段验收

1. 素材接入及 About 信息、文字 tab/精简 toolbar：先离屏测试断言旧行为失败，再实现、复核动态语言切换与布局；严禁弹可见 GUI。
2. 模型插入根节点与清选择 → canvas 文本/图片/视频粘贴和 Finder 拖放 → 吸附 latch：每段单独 RED/GREEN、无效输入无副作用、一次 Undo；显式相邻旧测试。
3. 默认关闭的更新检查、DMG 本地脚本：仅注入模拟网络测试；正式 GitHub Release 上传、公证或自动安装不作为本轮完成条件。
4. 所有改动合并后重新完整运行显式安全离屏矩阵，独立只读复审，构建新身份候选并验工件哈希；是否开新窗口/实体拖边/视觉可用必须由用户醒来亲测，不能取旧候选图或离屏数据冒充实测。

## 需要用户后续定夺的真实阻塞

正式开源许可及权利范围、Developer ID/Apple 公证凭据、正式 GitHub 仓库可见性与发布权限、是否采用 Sparkle/EdDSA appcast、以及实际 Dock/icon/实体吸附外观，均不能在用户休息期间默默推定。其余可逆、可本地离屏验证的行为按上述默认执行。
