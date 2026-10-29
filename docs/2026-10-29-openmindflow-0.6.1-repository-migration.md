# OpenMindFlow v0.6.1 — 私有仓库改名与稳定版发行记录

> **产品稳定渠道，不是 Apple Developer ID 签名或公证。** 仓库仍为 PRIVATE，未提供 LICENSE；下载需拥有仓库访问权限并在浏览器登录。此版本没有自动下载、安装或静默升级。`v0.6.0` 的旧二进制硬编码原仓库 URL 且拒绝重定向，**不能依赖其“检查更新”跨仓库改名**；发布完成后，应手动在[新仓库的 v0.6.1 Release](https://github.com/nico-zhuang/openmindflow/releases/tag/v0.6.1)下载升级。

## 仓库与旧版本保护

- GitHub 将原 `nico-zhuang/mindnode-reconstruction` **原地改名**为 `nico-zhuang/openmindflow`。前后仓库 ID 均为 `1431869014`，PRIVATE、默认 `main` 和 owner `nico-zhuang` 不变；未创建第二仓库、未转移、未合并 `main`。本地功能分支仍是 `feature/native-editor-v2`，`origin` 的拉取和推送均更新为 `git@github.com:nico-zhuang/openmindflow.git`；本地文件夹保持原名，不影响远端仓库名。
- 旧 `v0.6.0` 标签仍指向 `a97efb468c8addd3d53eab9bf5a606a7a446caf8`，Release ID 仍为 `427069177`、`draft=false`、`prerelease=false`，两个资产按新仓库路径认证重新下载后 DMG SHA-256 为 `b731afbe161c00b4b5305ca6401669527c1fcc47782b98823f6b7d6083b42cfc`、ZIP SHA-256 为 `991e27186f970eaa837983df5918b74a8fdc5da1399851af62d520601b4b41d0`。旧 0.6 本机包及已确认的 0.5 修复包哈希亦再次不变；不修改旧发行标签、旧构建/打包脚本或用户文件。
- 新版 `ReleaseChecker` 只信任 `https://api.github.com/repos/nico-zhuang/openmindflow/releases?per_page=30` 的原始 HTTPS 响应和 `https://github.com/nico-zhuang/openmindflow/releases/tag/<有效标签>`，旧仓库响应 URL、旧标签页、重定向、站外 URL 和伪装参数均不接受。维持 128 KiB、30 条列表、Stable/Beta 版本规则与单次完成约束；私有仓库匿名请求 403/404 只引导登录查看，而非声称已是最新版。新 App 的可执行文件已确认嵌入两个新固定地址且不含旧 API 固定地址。

## 全新本地文件

| 内容 | 地址 | SHA-256 |
| --- | --- | --- |
| 独立 App | [OpenMindFlow-Stable-0.6.1.app](</private/tmp/openmindflow-local-Cz5BMNVm/OpenMindFlow-Stable-0.6.1.app>) | 可执行文件 `a10797ef489128491fc450b64bf52e17a18c35e5102ee48eb8a302bc853bb7a2` |
| DMG | [OpenMindFlow-Stable-0.6.1-20261029.dmg](</private/tmp/openmindflow-local-Cz5BMNVm/OpenMindFlow-Stable-0.6.1-20261029.dmg>) | `23994fb05bf22b98d77e632f73e0cf64e1470b65b603de0fabbe8bf10dee5bac` |
| ZIP | [OpenMindFlow-Stable-0.6.1-20261029.zip](</private/tmp/openmindflow-local-Cz5BMNVm/OpenMindFlow-Stable-0.6.1-20261029.zip>) | `1bbf9e2681c7e0c3055c1772dae23da08192f206dfef64f83e6dd70c3ccbd886` |

- 新 App 仅在本 UID、0700、实际新建且事先确认空白的 `/private/tmp/openmindflow-local-Cz5BMNVm` 构建，版本 `0.6.1`／build `8`／tag `v0.6.1`／`stable`；bundle ID `com.nicozhuang.openmindflow`、`.mflw` UTI `local.openmindflow.document` Editor/Owner、icon SHA-256 `3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3`、最低 macOS 26 arm64。App 独立严格验签，显示 `Signature=adhoc`。不能据此推定签名者身份、Gatekeeper 认可或公证。
- 专用 0.6.1 builder 和 packager 不接受旧 0.6 文件名，不删除或覆盖旧输出。DMG 打包时对来源、暂存及只读 `-nobrowse` 挂载 App 各自严格验签，来源与暂存、暂存与挂载的普通文件清单/SHA 完全一致，`/Applications` 捷径正确；以精确镜像→APFS 物理存储→容器→卷血缘验证后仅卸载归属明确的磁盘。打包日志记录自有 `disk6` 正常 eject；完成后二次 `hdiutil verify` 通过且 `hdiutil info -plist` 未再列出此精确镜像。对不明设备不得推测归属或强行卸载。
- ZIP `unzip -tq` 完整性通过、条目均限制在本 App 包（或其 AppleDouble 元数据）路径内。使用 macOS `ditto -x -k` 在另一个新建私有目录解压后，App 的**四个普通文件 SHA-256 逐一等于签名来源**，包内版本/渠道准确且严格 `codesign` 通过。命令行 `unzip -q` 会把 ZIP 内 macOS AppleDouble `._` 元数据旁文件直接展开到签名 bundle 内，导致严格签名将其判为“新增资源”；验签应使用 macOS Finder/Archive Utility 或 `ditto -x -k` 还原元数据。先前在独立临时解压目录中观察到的 `unzip -q` 签名失败不影响未修改的 ZIP 本身，也未用于发布验收。

## 自动化验证及人工边界

- 完整安全离屏矩阵重新逐个编译并运行 **80/80 个 Swift 套件和 3/3 个 LeftBranchInteraction 交互子模式**，命令退出 0；明确排除会请求全局 AX/HID 的 `AppAccessibilityTests.swift` 和会抢前台的 `TabRenameKeyWindowTests.swift`，不将它们算作通过。测试日志独立留存于 `/private/tmp/omf-rename-fullsafe-HWlPiVlu`，合成 AppKit 绘制不等于真实桌面验收。
- 更新检查器以新独立常量先 RED（旧地址下期望新版 URL 时退出 133），再 GREEN；真实 URLSession/URLProtocol 重定向和大包取消、旧仓库 URL 拒绝、403/404、稳定/Beta、单次调用均测试通过。关于页、设置视觉布局和语言相邻离屏套件通过。
- 新 builder 和 DMG packager 的独立安全夹具先在脚本缺席时 RED，后 GREEN；额外的来源→暂存 SHA 前置断言先 RED 后 GREEN。负例覆盖现存/符号链接/非私有目标、旧 0.6 名、重复镜像/挂载实体、异源 APFS 存储与容器、非镜像总线、未知设备或替换挂载点；没有使用测试夹具附挂或卸载实体磁盘。实体 DMG 的受控挂载卸载仅在全新自有镜像上由正式 packager 实施。
- 不启动应用、不覆盖 `/Applications`、既有 0.4/0.5/0.6 产物或 `.mindnode` 原件。`.mflw` 为有魔数、长度和 SHA-256 校验的非 JSON 二进制 property list；MindNode v9 仅有界只读导入、保真改动后另存**新副本**，不保证原 MindNode 应用必然接受。合成离屏测试不等于用户实际 Finder 双击、鼠标/键盘手感、系统 VoiceOver 或原 MindNode 应用导出副本验收。
