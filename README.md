<div align="center">
  <img src="docs/images/openmindflow-icon.png" width="108" alt="OpenMindFlow 图标：深蓝底上的根节点与三条彩色分支">
  <h1>OpenMindFlow</h1>
  <p><strong>原生画布，自有文稿，谨慎互通。</strong></p>
  <p>一款独立的 macOS 思维导图编辑器。整理想法、编辑分支，并将作品保存为自己的 <code>.mflw</code> 文件。</p>
  <p>
    <img src="https://img.shields.io/badge/macOS-26%2B%20%7C%20arm64-1c3556?style=flat-square" alt="macOS 26+，arm64">
    <img src="https://img.shields.io/badge/release-v0.6.1-19a9a2?style=flat-square" alt="稳定渠道 v0.6.1">
    <img src="https://img.shields.io/badge/repository-private-596579?style=flat-square" alt="私有仓库">
  </p>
  <p>Language / 语言<br>
    <a href="README.md" aria-label="当前语言：简体中文"><img src="https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-%E5%BD%93%E5%89%8D-19a9a2?style=for-the-badge" alt="简体中文 · 当前页面"></a>
    <a href="README.en.md" aria-label="Switch to English"><img src="https://img.shields.io/badge/English-Switch%20language-596579?style=for-the-badge" alt="English · Read in English"></a>
  </p>
</div>

在原生画布上编辑节点与分支，保存为可重开的 `.mflw` 文稿；需要借用 MindNode v9 文件时，只导入支持的结构，并向新副本导出。

> **获取说明**：仓库和 Release 均为**私有**，只有获授权的 GitHub 账号可以访问。当前稳定渠道仅为产品版本标记；App 采用 ad-hoc 签名，**没有 Developer ID 签名或 Apple 公证**，也没有自动安装器。

## 从这里开始

| 想做什么 | 入口 |
| --- | --- |
| 下载 v0.6.1 | [DMG](https://github.com/nico-zhuang/openmindflow/releases/download/v0.6.1/OpenMindFlow-Stable-0.6.1-20261029.dmg) · [ZIP](https://github.com/nico-zhuang/openmindflow/releases/download/v0.6.1/OpenMindFlow-Stable-0.6.1-20261029.zip) · [完整发行说明](https://github.com/nico-zhuang/openmindflow/releases/tag/v0.6.1) |
| 了解文件与兼容边界 | [原生文稿](#自己的文稿不是改后缀-json) · [MindNode v9](#mindnode-v9有界互操作) |
| 查看验证和演进记录 | [v0.6.1 发行记录](https://github.com/nico-zhuang/openmindflow/blob/v0.6.1/docs/2026-10-29-openmindflow-0.6.1-repository-migration.md) · [v0.6.1 旧版 README](https://github.com/nico-zhuang/openmindflow/blob/v0.6.1/README.md) |

**系统要求：**macOS 26 或更新版本，Apple Silicon（arm64）。当前包为 **v0.6.1／build 8**，bundle ID `com.nicozhuang.openmindflow`。下载前请先在浏览器登录有访问权限的 GitHub 账号；无需也不应向 App 提供 GitHub 令牌。

> **源码版本说明**：默认 `main` 目前仍保留早期原生编辑器原型。本文介绍的是已发行的 [v0.6.1 源码快照](https://github.com/nico-zhuang/openmindflow/tree/v0.6.1)与 App；后续开发在 [`feature/native-editor-v2`](https://github.com/nico-zhuang/openmindflow/tree/feature/native-editor-v2)。本次首页更新不合并两分支的应用代码。

## 用它整理什么

- **在画布上直接编辑**：建立主节点与子节点，移动、折叠和整理分支；大纲、样式与笔记面板帮助你在内容和结构之间切换。
- **不止一张图**：多个文稿可以用窗口与标签分别管理；可对选中节点进行常见的文字、连接与布局调整。这里展示的是已有能力，不代表与其他思维导图软件功能完全对等。
- **中英界面可选**：在设置中选择跟随系统、简体中文或 English；选择不会翻译你写的节点内容。仓库介绍也有[英文版](README.en.md)。
- **把文件留在自己手里**：默认用独立 `.mflw` 文稿保存，必要时再使用受限的 MindNode v9 导入和“导出新副本”。

## 文稿格式与兼容边界

### 自己的文稿，不是改后缀 JSON

`.mflw` 使用 `OMFLW001` 魔数、长度及 SHA-256 校验，正文为**二进制 property list**，不是把 JSON 换个扩展名。可在本应用中保存、重开和继续编辑；旧 `.mindmap.json` 仅作为迁移输入，不会因打开而原地回写。

### MindNode v9：有界互操作

可只读导入**已支持的 MindNode v9 二进制 plist 包／文件**。导入源 `.mindnode` 永远不是自动保存目标；能保真的有限修改可导出到**全新的副本**，不支持的改动会拒绝原格式导出，但仍可保存为 `.mflw`。这不等于支持所有 MindNode 文件、完整双向格式兼容，或已由原 MindNode 应用验收导出副本。OpenMindFlow 是独立项目，不隶属于 MindNode／IdeasOnCanvas。

## 安装与升级

1. 在有权限的浏览器会话中打开 [v0.6.1 Stable Release](https://github.com/nico-zhuang/openmindflow/releases/tag/v0.6.1)，下载 DMG 或 ZIP；App 不会自动下载或安装更新。
2. 如选 ZIP，请使用 macOS Finder／归档实用工具或 `ditto -x -k` 解压。此 ZIP 含 AppleDouble 元数据，直接以命令行 `unzip -q` 展开后验签会因新增的 `._` 文件而失败。
3. 依照自己的 macOS 安全策略检查 App 和来源；**ad-hoc 签名不证明发布者身份，也不等于 Gatekeeper 或公证通过**。不要将测试步骤用于正在使用的旧 App 或重要文稿。

**从 v0.6.0 升级须手动下载：**旧二进制固定改名前的仓库地址并拒绝重定向，不能依赖旧版“检查更新”发现新版。新版检查器只读取新仓库受限的 Releases 元数据；私有仓库匿名访问可能得到 403/404，此时仅提示登录浏览器查看，不会误报已是最新。v0.6.0 的 [Release](https://github.com/nico-zhuang/openmindflow/releases/tag/v0.6.0) 和原资产继续保留。

<details>
<summary>v0.6.1 文件校验值（SHA-256）</summary>

| 文件 | SHA-256 |
| --- | --- |
| `OpenMindFlow-Stable-0.6.1-20261029.dmg` | `23994fb05bf22b98d77e632f73e0cf64e1470b65b603de0fabbe8bf10dee5bac` |
| `OpenMindFlow-Stable-0.6.1-20261029.zip` | `1bbf9e2681c7e0c3055c1772dae23da08192f206dfef64f83e6dd70c3ccbd886` |

</details>

## 验证、限制与项目资料

v0.6.1 曾逐个通过 **80/80 个安全离屏 Swift 套件及 3/3 个交互子模式**，且源 App、DMG 和经 macOS `ditto` 解压的 ZIP App 均经过严格签名／文件校验。离屏测试**不等于**在真实桌面完成 Finder 双击、鼠标键盘手感、系统 VoiceOver 或原 MindNode 打开副本的验收。详细证据与排除项见[发行记录](https://github.com/nico-zhuang/openmindflow/blob/v0.6.1/docs/2026-10-29-openmindflow-0.6.1-repository-migration.md)。

目前仓库**没有 LICENSE**；私有可读或可下载不代表获得公开再分发许可。产品方向、早期候选与逐版验证可查阅[v0.6.1 标签下的旧版 README](https://github.com/nico-zhuang/openmindflow/blob/v0.6.1/README.md)；本轮首屏与双语组织方式的取舍见[Ask Five Pro 评议记录](https://github.com/nico-zhuang/openmindflow/blob/26538c930c88f5489572ad6c5fc2a37ba298d500/docs/2026-10-29-openmindflow-bilingual-readme-review.md)。历史文稿中的本机文件路径并非可公开下载的资产。
