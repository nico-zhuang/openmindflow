# OpenMindFlow 本地发行准备（0.3.0 / build 4）

本项目目前只构建**独立的本机 ad-hoc 签名测试包**。这份说明不构成正式公开发行许可或 Apple 公证证明；既有运行中的候选应用及其未保存内容、最早的签名预览、`.mindnode` 原件和用户导出都必须保持原样。不要运行旧 `build.sh`，它会写入已有 `build/MindMap.app`。

## 明确受限的本地流程

1. 先新建归当前用户所有、权限 `0700` 的 `/private/tmp/openmindflow-local-XXXXXXXX` 目录。构建器只接受此目录内**不存在**的 `.app` 输出；现有任何候选/保护路径都拒绝覆盖。`scripts/build-openmindflow-local.sh` 编译源码、置入 `Assets/OpenMindFlow.icns` 验证哈希、写 `local.openmindflow.native-editor`、版本 `0.3.0`、build `4`、最低 macOS `26.0`，然后对**完整应用包**做本地 ad-hoc 签名及 `codesign --verify --deep --strict`。
2. `scripts/package-openmindflow-local-dmg.sh` 只接收**同一私有目录内**的 `OpenMindFlow.app`，输出**该目录内**此前不存在的 `.dmg`；校验包名、bundle ID、版本、图标字节与签名后，将应用与指向 `/Applications` 的捷径置于临时镜像源目录。`hdiutil create -format UDZO` 生成压缩拖入式 DMG，`hdiutil verify`/`imageinfo` 校验镜像；不挂载镜像、不开启 Finder、不启动/聚焦 App、不联网。
3. `bash Tests/run-icon-package-safe.sh` 与 `bash Tests/run-local-dmg-safe.sh` 分别以一次性私有测试目录验证构建及打包拒绝规则。前者/后者使用受控自建临时资源；失败时保留其目录供排查，成功后仅在归属、路径和权限二次校验通过时清理。脚本有时可能遭遇系统镜像资源暂时不可用，不能把失败冒充成功；核查后可以选择**全新**输出路径重试。

示例（务必先检查这些名字尚不存在；此文档不代替脚本内的二次校验）：

```sh
scratch="$(mktemp -d /private/tmp/openmindflow-local-XXXXXXXX)"
app="$scratch/OpenMindFlow.app"
dmg="$scratch/OpenMindFlow-0.3.0-local.dmg"
bash scripts/build-openmindflow-local.sh "$app"
bash scripts/package-openmindflow-local-dmg.sh "$app" "$dmg"
codesign --verify --deep --strict --verbose=2 "$app"
hdiutil verify "$dmg"
shasum -a 256 "$app/Contents/MacOS/OpenMindFlow" "$dmg"
```

**不要将示例直接改为覆盖 `build/`、`dist/` 或任一运行中的包。**另存长期交付文件时应先确认其绝对路径为全新独立文件名，检查完整签名、ZIP 完整性与镜像 SHA-256；没有对现有 ZIP/DMG 的覆盖通道。

## 在线版本检查与正式发布的分界

- Settings → About 显示 `NicoZhuang | KEEPCRAZY | YoSoAi`、独立开发以及对 MindNode 的只读兼容/无 IdeasOnCanvas 关联说明。自动 GitHub Release 元数据检查**默认关闭**，只有用户明确勾选后下一次启动才查询；手动按钮可以主动查询。版本号须严格 `X.Y.Z`，GitHub 返回页必须指向仓库 `nico-zhuang/mindnode-reconstruction` 的相同稳定标签，否则不能提示新版本。若确认有新版本，**用户点选**后才在默认浏览器打开发布页；不会下载、替换、执行、安装或静默升级，也未验证该仓库公开可访问。
- 当前仓库未确定公开发布所需的软件许可证；没有 Developer ID 签名、公证、正式的镜像外观/安装验收、自动安装框架或可信 appcast。公开 GitHub Release、发布权限、合法可分发性和用户文件的隐私边界须经所有者另行确认。不要在没有这些前提和人工 GUI 验收时上传、推送、给出“可正式下载安装”的结论。
- Apple silicon/macOS 26 是当前构建目标；不同系统版本的兼容性和系统 Gatekeeper 首开行为没有独立验证。本地 ad-hoc 签名只能证明本机包资源完整，**不等于**被 Apple 开发者身份认可或通过 Gatekeeper。
