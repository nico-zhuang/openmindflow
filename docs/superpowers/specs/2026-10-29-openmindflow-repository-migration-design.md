# OpenMindFlow 私有仓库改名与 v0.6.1 稳定版迁移设计

日期：2026-10-29。用户在获知「不能只改 GitHub 仓库名；应同步更新检查器、测试、文档和 Git remote，发布后续版本，保留 v0.6.0」后明确要求实施。目标是把原私有仓库 `nico-zhuang/mindnode-reconstruction` **原地改名**为 `nico-zhuang/openmindflow`，不新建一个仓库、转移 owner、合并 `main`、覆盖旧 Release 或改变 PRIVATE 权限。本地工作继续在 `feature/native-editor-v2`；目录名可保留原状，不重命名用户机器上的仓库文件夹。

## 已知风险与边界

- 已签发的 v0.6.0 App 将 `api.github.com/repos/nico-zhuang/mindnode-reconstruction/releases?per_page=30` 与原仓库 Releases 页面写入二进制。它拒绝 HTTP 重定向，且只接受与自身固定页面完全一致的 release `html_url`；GitHub 改名后的重定向**不是**其兼容方案。旧版不可重签、改包或冒称可自动检出新版本；用户需要通过浏览器登录私有仓库、手动下载 v0.6.1。新版本仍不嵌 token、不自动下载安装，匿名私有 API 403/404 继续如实提示浏览器登录。
- v0.6.0 的 Git tag、Release、两个资产、SHA-256、已运行 App 与旧 0.4/0.5 包和脚本都保留。不可运行全局 AX/HID 或抢前台的 key-window 测试；独立合成 AppKit 离屏验证不等于实体人手验收。没有 Developer ID 身份，v0.6.1 仍仅 ad-hoc 签名、未公证；仓库仍无 LICENSE。
- 旧 0.6 构建脚本与打包脚本按 exact path/version/build 验证，只能作为**只读模板**，不能用当前新源码产出冒充 v0.6.0 的新包；也不能修改它们。包内 bundle ID 继续 `com.nicozhuang.openmindflow`，`.mflw` UTI `local.openmindflow.document`、图标 SHA-256 `3749b7b5f220896506f5851f488ecfd74b543e5e8ac71f3fc909b6ebf4b25af3`、macOS 26 arm64 不变。

## 迁移后的契约

1. **检查器**：唯一官方仓库固定为 `nico-zhuang/openmindflow`。请求 `https://api.github.com/repos/nico-zhuang/openmindflow/releases?per_page=30`，用户可见入口固定 `https://github.com/nico-zhuang/openmindflow/releases`。仍拒绝 HTTP 重定向、原仓库 `html_url` 和原 API response URL；严格核验 `vX.Y.Z` 稳定与 `vX.Y.Z-beta.N` Beta、官方标签页、上限 30 条/128 KiB、一次回调及 403/404 私有访问提示。App 的手动新版本跳转只能使用已验证的新 tag URL，故障回退只打开新官方页面。
2. **独立新包**：创建只接受新鲜 `/private/tmp/openmindflow-local-[A-Za-z0-9]+`（本 UID、0700、非 symlink）的专用 `build-openmindflow-0.6.1-stable-local.sh` 和 `package-openmindflow-0.6.1-stable-dmg.sh`。精确 App basename `OpenMindFlow-Stable-0.6.1.app`；DMG/ZIP 唯一输出名 `OpenMindFlow-Stable-0.6.1-20261029.dmg` / `.zip`。Info.plist 的短版本和发布版本均 `0.6.1`、build `8`、tag `v0.6.1`、channel `stable`；来源、暂存、挂载及 ZIP 解压版全部单独验签和核验每个普通文件哈希。保留原 0.6 包脚本既有的 APFS 实体血缘、挂载点归属和失败保留检查，不从路径猜测磁盘归属或卸载外来设备。绝不将新包直接复制到 `/Applications` 或现有 `dist/`。
3. **GitHub 与文档**：在新 checker/脚本的离线 RED/GREEN 和独立复核完成后，确认目标 slug 未占用、仓库管理员权限与旧 v0.6.0 tag/两个资产，再用 GitHub CLI 原地改名。仅在确认新路径确实指向原仓库、PRIVATE、`main` 默认分支与旧 tag/资产保持后，把本地 `origin` 改为新 SSH 地址；无 force push。历史设计与旧 release 记录仍反映发布时的原仓库事实；README 新增当前 v0.6.1 入口，并将当前可点击的 v0.6.0 Release/资产链接指向改名后的仓库，保持旧 SHA。单独写本轮发行记录，醒目说明旧版迁移期间无法依赖检查更新、ad-hoc 未公证、私有访问需要登录、无自动安装、MindNode v9 有界互操作。
4. **发布门槛**：安全离屏回归（除全局 AX/抢前台案例）、ReleaseChecker 真实 URLProtocol/私有/恶意 URL 测试、0.6.1 构建与 DMG 负例、安全只读挂载/受控卸载、ZIP 往返、旧版本脚本/资产哈希、独立代码审查均通过才推功能分支并新建 `v0.6.1` Stable Release（`prerelease=false`）。以已认证私有 GitHub API 与重新下载资产 SHA 确认 v0.6.0 和 v0.6.1 同时存在；若任何关键门槛失败，保留已迁移仓库与已验证源码，但不发布有缺陷工件，准确报告阻碍。
