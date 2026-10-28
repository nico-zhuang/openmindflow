# OpenMindFlow v0.6.0 — 稳定版构建与发行记录

> **私有仓库；仅 ad-hoc 签名，未经 Developer ID 签名或 Apple 公证。** “稳定版”是此版本的发布渠道，并非 Apple 安全认证、对所有人的公开下载承诺或无条件格式互操作承诺。仓库目前没有 LICENSE；请勿据此宣称可以公开再分发。

## 已构建的独立文件

| 文件 | SHA-256 |
| --- | --- |
| `OpenMindFlow-Stable-0.6-20261029.dmg` | `b731afbe161c00b4b5305ca6401669527c1fcc47782b98823f6b7d6083b42cfc` |
| `OpenMindFlow-Stable-0.6-20261029.zip` | `991e27186f970eaa837983df5918b74a8fdc5da1399851af62d520601b4b41d0` |
| App 内 `Contents/MacOS/OpenMindFlow` | `5031b75ca72a13a1a9040e54e928befa59884deaf53032f7f6182d614812ce05` |
| App 内 `Contents/Resources/OpenMindFlow.icns` | `3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3` |

本机保留：[App](</private/tmp/openmindflow-local-pSoUNQY6/OpenMindFlow-Stable-0.6.app>)、[DMG](</private/tmp/openmindflow-local-pSoUNQY6/OpenMindFlow-Stable-0.6-20261029.dmg>)、[ZIP](</private/tmp/openmindflow-local-pSoUNQY6/OpenMindFlow-Stable-0.6-20261029.zip>)，均在同一个全新用户私有、0700 的 `/private/tmp/openmindflow-local-pSoUNQY6` 中，不覆盖历史候选。App 为 macOS 26 arm64；bundle ID `com.nicozhuang.openmindflow`，短版本 `0.6.0`、构建号 `7`、包内标记 `v0.6.0`／`stable`；`.mflw` 编辑关联仍是 `local.openmindflow.document` Editor/Owner。

## 本版改动

- 主窗口横／竖标签栏在浅色、深色下增加独立不透明中性色底与画布侧一像素边线；保留选中、悬停关闭、竖排加号、拖动和画布自身配色。
- 设置窗口改为约 620×470 的三个原生独立页面：通用、快捷键、关于。中英双语和 Aqua/Dark 对齐；切页移动键盘焦点且不改变已保存的快捷键与偏好语义。关于页清晰展示版本、Stable/Beta 渠道、可选自动检查、立即检查、状态和官方 Releases 入口。
- 更新只读取经严格限制与认证的 `nico-zhuang/mindnode-reconstruction` GitHub Releases 元数据，Stable 限 `vX.Y.Z`／非 prerelease，Beta 限 `vX.Y.Z-beta.N`／prerelease；Beta 渠道可接受更新的稳定终版。数值顺序而非 API 顺序，拒绝无效 tag、站外 URL、重定向和超量响应。默认关闭自动检查，手动检查不会自动下载或安装。对于私有仓库匿名 403/404，展示登录 GitHub 查看官方 Releases 的可操作跳转；首屏恰满 30 条且无法证明有更新时也不误报“没有版本”或“已是最新”。
- 原生 `.mflw` 是带 `OMFLW001` 魔数、长度和 SHA-256 校验的**二进制 property list** 文稿，不是重命名的 JSON。MindNode v9 仅在已验证的有限结构内导入与另存可保真编辑后的**新副本**，原件从不自动写入；不支持的编辑会拒绝原格式导出但仍可保存 `.mflw`。

## 验证与边界

- 稳定 App 从源码提交 `ff4ef1d49713e74e6ce7c2393085e71fa5eab92d` 生产编译；Info.plist 的七项版本/渠道/系统元数据与 `.mflw` UTI 用 plist 解析再次确认。`codesign --verify --deep --strict` 对 App 通过；`codesign -dv` 明确显示 `Signature=adhoc`、`TeamIdentifier=not set`。
- 最终安全离屏矩阵的 **80/80 套件和 3/3 个交互子模式重新顺序执行通过**（最终命令退出 0）；明确排除会请求全局 AX/HID 的 `AppAccessibilityTests.swift` 和会抢前台的 `TabRenameKeyWindowTests.swift`，不将它们算作通过。首次全量编译矩阵编译了全部 80 套件，但其中 `MultiDocumentBindingTests` 因沿用旧设置窗口“弹窗是直接子视图”的**测试夹具假设**在第 41 行崩溃（首次矩阵 79 通过／1 失败，退出 1）。批准后的新版设置把语言选框放进 General 页面；仅将该测试改为按精确 `general-language` 标识递归定位，不更改产品源码或弱化跨两文稿/两查找面板的断言。该测试重新编译后独立通过，并与其他 79 个针对同一未改生产源码编译的测试二进制一起在单次最终矩阵全部复跑绿灯；测试变更经独立只读复核无阻断发现。
- 新 DMG 经 `hdiutil verify`，打包脚本在私有挂载点以 `-readonly -nobrowse` 验证源／暂存／镜像中 App 的签名和逐文件 SHA-256 清单相同，并验证 `/Applications` 快捷方式；挂载由脚本确认归属后安全卸载，发行镜像随后再次验证且确认未留挂载。ZIP `unzip -t` 成功；解压后的 App 严格验签，4 个正规文件逐一 SHA-256 与源 App 完全一致，版本、tag、channel 再次从解压包检查。
- 首次**未发布**的调试 DMG 因 macOS APFS 将物理镜像 `diskNs1` 合成为独立容器卷 `diskMs1` 而在卸载归属检查中安全拒绝（退出 2）；没有对其他镜像执行卸载。新脚本以实际镜像、物理分区、APFS 容器、挂载卷四级关系验证，相关正例/异源及畸形元数据负例均通过。失败调试镜像由负责人再次核对唯一镜像路径、挂载点和设备关系后只卸载属于它的磁盘，另一个新建私有目录重新构建了上述最终文件。历史 0.5 脚本未修改。
- 独立离屏 AppKit 位图覆盖中文／英文 × Aqua／Dark 的三个设置页及 403/404、Beta 提醒、长版本号；可见文字与边距检查不等于人在真实桌面亲手验收。用户先前仅实机确认 **0.5 重命名修复**，没有对这个 0.6 签名包的新设置/导航手感、系统 VoiceOver、Finder 双击、原 MindNode 打开导出副本做全面实体复验。避免用合成 importer 往返冒充原 MindNode 应用验收。
- 用户的旧 0.4 App 可执行文件/DMG/ZIP、已确认的 0.5 重命名修复 App 可执行文件/DMG/ZIP，以及旧 0.5 构建/打包/安全测试脚本，已按固定 SHA-256 重新核对且未变化。没有关闭用户运行中的旧应用、覆盖用户旧包、安装新 App、操作原 `.mindnode` 或执行全局 AX/HID。

## 私有仓库更新检查的现实限制

仓库保持 **PRIVATE**。不向 App 内写入 GitHub token，也不更改仓库可见性，所以对未登录的普通安装者无法自动比对真实私有 Release：403/404 明确标为“请在浏览器登录 GitHub 查看 Releases”，绝不说已是最新版。只有将来所有权人授权公开或提供真正可信的公开发布源，才能保证无凭据在线版本比对。正式发布时须确认 GitHub tag 为 `v0.6.0`、Release `prerelease=false` 并在发布后复查元数据；今后 Beta 用 `vX.Y.Z-beta.N` 且 `prerelease=true`，不把旧 0.5 本地候选冒充稳定或 Beta 发布。此版没有自动安装、Developer ID、Apple 公证和正式开源授权。
