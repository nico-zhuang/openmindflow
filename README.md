<div align="center">
  <img src="docs/images/openmindflow-icon.png" width="92" alt="OpenMindFlow 项目图标：深蓝底上的根节点与三条彩色分支">
  <h1>OpenMindFlow</h1>
  <p><strong>在 Mac 上梳理想法的原生思维导图编辑器。</strong><br>建立和整理分支，用独立的 <code>.mflw</code> 文稿保存作品。</p>
  <p>
    <img src="https://img.shields.io/badge/macOS-26%2B%20%7C%20arm64-1c3556?style=flat-square" alt="macOS 26 或更新版本，Apple Silicon arm64">
    <img src="https://img.shields.io/badge/release-v0.6.1-19a9a2?style=flat-square" alt="v0.6.1 已发布">
  </p>
  <p>Language / 语言<br>
    <a href="README.md" aria-label="当前语言：简体中文"><img src="https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-%E5%BD%93%E5%89%8D-19a9a2?style=for-the-badge" alt="简体中文 · 当前页面"></a>
    <a href="README.en.md" aria-label="Switch to English"><img src="https://img.shields.io/badge/English-Switch%20language-596579?style=for-the-badge" alt="English · Read in English"></a>
  </p>
  <p><a href="https://github.com/nico-zhuang/openmindflow/releases/tag/v0.6.1" aria-label="打开 v0.6.1 下载页面（目前仅授权账号可访问）"><img src="https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-v0.6.1-1c3556?style=for-the-badge" alt="下载 v0.6.1 · 目前仅授权账号可访问"></a></p>
  <p><a href="#快速开始">安装与运行</a> · <a href="#核心体验">核心体验</a> · <a href="#当前状态与已知限制">当前状态</a></p>
</div>

> **产品展示说明**：目前没有经过核对的 **v0.6.1 实际应用窗口截图或操作 GIF**。上方展示的是项目图标，不是界面截图；旧原型的离屏画布图也不会冒充当前版本。取得真实窗口素材并完成权限与内容审查后再补充展示。

OpenMindFlow 面向想把思路整理成可继续编辑的导图文稿的人：从一个主题出发，添加节点、调整分支与布局，在画布和大纲之间切换。它是一款独立开发的 macOS 应用，不要求先安装 MindNode；对 MindNode v9 文件的互通只有明确的部分支持，详见下文。

## 核心体验

以下能力存在于 **v0.6.1 标签所对应的源码**，并有发行时的自动化验证记录；并不表示每项都完成了本轮真实桌面手测。

| 能做什么 | 对使用者的价值与目前状态 |
| --- | --- |
| **画布上整理结构** | 创建、编辑、移动和折叠节点与分支，按需整理布局；核心编辑代码和离屏测试存在，实际鼠标手感仍需逐项验收。 |
| **从大纲回到画布** | 大纲、样式与笔记面板帮助定位内容和调整表达；支持简体中文 / English 界面选择，不会翻译文稿文字。 |
| **分别管理多个想法** | 多文稿窗口与标签分别保存各自编辑状态，避免把不同导图挤在一份文件里；真实窗口交互仍有待复核。 |
| **保存与输出** | 自有 `.mflw` 文稿可以保存后重开；另有 PDF、PNG、JPEG、Markdown 导出。Markdown 是文本层级摘要，**不会无损带出媒体、笔记或关系线**。 |
| **有限读取 MindNode v9** | 可导入支持的二进制 plist 文件或目录包；只允许部分可保真的修改导出到**新副本**，不改写原件，也未证明被原 MindNode 接受。 |

## 快速开始

**系统：**macOS 26 或更新版本、Apple Silicon（arm64）。已发行的 **v0.6.1／build 8** 是产品的 Stable 渠道标签，不代表 Apple 公证或已经完成广泛桌面验收。

1. 目前仓库及 Release **仍为私有**：在获得访问权限的 GitHub 浏览器会话打开 [v0.6.1 Release](https://github.com/nico-zhuang/openmindflow/releases/tag/v0.6.1)，下载 [DMG](https://github.com/nico-zhuang/openmindflow/releases/download/v0.6.1/OpenMindFlow-Stable-0.6.1-20261029.dmg) 或 [ZIP](https://github.com/nico-zhuang/openmindflow/releases/download/v0.6.1/OpenMindFlow-Stable-0.6.1-20261029.zip)。应用不收取 GitHub 令牌，也不会自动下载安装更新。
2. 选 DMG 时用 Finder 打开，确认其中的 OpenMindFlow App 和 `/Applications` 快捷方式；若选择安装到“应用程序”，由你确认后拖入该快捷方式。选 ZIP 时用 Finder／归档实用工具，或使用下方已验证的 `ditto` 解压命令；**不要用 `unzip -q`** 把 AppleDouble `._` 文件散落进已签名 App。打开前按自己的 macOS 安全策略核对来源与校验值；真实 Finder 拖放、安装及首次启动尚未在本轮独立验收。
3. 启动后可新建导图、添加节点，再把作品保存为 `.mflw`；重要文稿在扩展测试覆盖前保留独立备份。App 仅使用 **ad-hoc 签名**，无 Developer ID 签名、Apple 公证或自动安装器；签名校验不证明发布者身份，遇到系统拦截请不要为了试用而关闭系统保护。

例如把 ZIP 下载到“下载”文件夹且保留原文件名后，在全新私有目录解包并验签（如果浏览器改了文件名，先替换命令中的 ZIP 路径）：

```bash
unpacked="$(mktemp -d /private/tmp/openmindflow-unpack-XXXXXXXX)"
ditto -x -k "$HOME/Downloads/OpenMindFlow-Stable-0.6.1-20261029.zip" "$unpacked"
codesign --verify --deep --strict "$unpacked/OpenMindFlow-Stable-0.6.1.app"
```

**本轮已用原始 v0.6.1 ZIP 在同样的新目录完成 `ditto` 解包和严格验签**；这不等于自动安装或 GUI 首次打开验收。

<details>
<summary>v0.6.1 下载校验值（SHA-256）</summary>

| 文件 | SHA-256 |
| --- | --- |
| `OpenMindFlow-Stable-0.6.1-20261029.dmg` | `23994fb05bf22b98d77e632f73e0cf64e1470b65b603de0fabbe8bf10dee5bac` |
| `OpenMindFlow-Stable-0.6.1-20261029.zip` | `1bbf9e2681c7e0c3055c1772dae23da08192f206dfef64f83e6dd70c3ccbd886` |

可在 macOS 终端运行 `shasum -a 256 下载文件的路径`，将输出与表中相应行逐字对照；**命令中的路径是说明文字，不可原样粘贴当文件路径**。

</details>

### 从源码构建（可选）

默认 `main` 的 Swift 仍是早期原型，**不能**把旧 `build.sh` 当成 v0.6.1 构建方法。要构建已发行版本，应具备 Swift 命令行工具和仓库 SSH 读取权限，使用固定的 [v0.6.1 tag](https://github.com/nico-zhuang/openmindflow/tree/v0.6.1)，在全新、本人所有的私有临时目录中运行专用构建脚本：

```bash
scratch="$(mktemp -d /private/tmp/openmindflow-local-XXXXXXXX)"
git clone --depth 1 --branch v0.6.1 git@github.com:nico-zhuang/openmindflow.git "$scratch/source"
bash "$scratch/source/scripts/build-openmindflow-0.6.1-stable-local.sh" \
  "$scratch/OpenMindFlow-Stable-0.6.1.app"
codesign --verify --deep --strict "$scratch/OpenMindFlow-Stable-0.6.1.app"
```

上面的 `mktemp` 命令新建私有目录；脚本要求 `/private/tmp/openmindflow-local-*`、本人所有且权限为 `0700` 的目录，并拒绝覆盖已有 App。**本轮已在 macOS 26.5／arm64 的全新克隆目录按上述命令构建成功，Info.plist 为最低系统 26.0，严格 ad-hoc `codesign` 验证通过**；编译出现 AVFoundation 旧 API 弃用警告。构建不安装或自动启动 App，图形运行与 Finder 安装仍待独立验收。

**从 v0.6.0 升级：**旧二进制固定改名前的仓库地址并拒绝重定向，必须手动从新版 Release 下载 v0.6.1。旧 [v0.6.0 Release](https://github.com/nico-zhuang/openmindflow/releases/tag/v0.6.0) 与资产仍保留。

## 当前状态与已知限制

- **已做的验证**：v0.6.1 发行记录载有 **80/80 个安全离屏 Swift 套件 + 3/3 个交互子模式**，并记录 App、DMG 与按 macOS `ditto` 解压的 ZIP App 校验通过。它们是发行时记录，不是本次重跑的全量测试，也不是每个真实桌面操作都已验收。详见[发行证据](https://github.com/nico-zhuang/openmindflow/blob/v0.6.1/docs/2026-10-29-openmindflow-0.6.1-repository-migration.md)。
- **仍待实机确认**：当前版本真实窗口展示、Finder 双击 `.mflw`、鼠标拖放与缩放、系统 VoiceOver、实际 MindNode 打开由 OpenMindFlow 新导出的副本；重要数据请独立备份。不要把旧截图或合成窗口测试当成这些项目已通过。
- **兼容范围**：`.mflw` 是带 `OMFLW001` 标记、长度与 SHA-256 校验的**二进制 property list**，不是改名 JSON；旧 `.mindmap.json` 仅作迁移输入。MindNode v9 仅对受支持的二进制 plist 文件／目录包提供有限只读导入，ZIP 容器、新版本和未知结构并无广泛兼容承诺；无法保真导出的修改仍可另存 `.mflw`。
- **分支差异**：GitHub 默认 `main` 仍保留最早期 App 原型，此页描述的是已发行的 [v0.6.1 源码快照](https://github.com/nico-zhuang/openmindflow/tree/v0.6.1) 与包。持续开发在 [`feature/native-editor-v2`](https://github.com/nico-zhuang/openmindflow/tree/feature/native-editor-v2)；**不要直接从 `main` 预期构建同款发布包**。

## 与 MindNode 的关系

OpenMindFlow 是独立开发的软件，以 MindNode 的思维导图体验及 v9 文件互操作为研究参照；**不是 MindNode／IdeasOnCanvas 的官方产品，也没有官方隶属或背书**。MindNode 名称与商标属于其权利人；这里的兼容范围不等于官方格式完整支持。第三方代码、素材与适用许可仍须由维护者进一步审查，不做法律结论。

## 接下来的工作

1. 补做当前签名版的真实桌面交互、Finder 文稿关联、系统辅助功能及原 MindNode 接受副本验收；取得合规的真实窗口截图后再制作演示。
2. 把 MindNode v9 文件边界、拒绝原因与导出新副本的用户提示继续收紧，并维持原件只读保护。
3. 明确图标/第三方素材与源码的授权、私人历史记录的公开处理方式，以及未来发行签名、公证和外部反馈流程；这些不是已承诺上线的功能。

## 反馈、源码与许可

目前仓库 **Issues 未启用**，也没有正式外部贡献流程或 `LICENSE` 文件；请勿把当前可读源码或下载包理解为获得修改、再分发或开源许可证。维护者完成隐私、权利和受理流程后，再决定开放反馈入口及贡献规则。历史设计与早期实验记录可从[v0.6.1 旧版 README](https://github.com/nico-zhuang/openmindflow/blob/v0.6.1/README.md)检索；其中的本机测试路径不是公开下载入口。
