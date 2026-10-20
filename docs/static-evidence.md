# MindNode 2026.0.2：只读证据与未验证项

来源：本机 `/Applications/MindNode.app`，主程序为通用 Mach-O；REA CLI `decode-interface-builder` 静态解码 `Contents/Resources/Base.lproj/MainMenu.nib`，没有启动应用。打包菜单给出的默认按键定义：

| 菜单动作 | 打包按键 | 证据性质 |
| --- | --- | --- |
| New Child | Tab | 静态菜单声明 |
| New Sibling | Return | 静态菜单声明 |
| New Sibling Before | Shift+Return | 静态菜单声明 |
| New Main Node | Option+Return | 静态菜单声明 |
| Fold/Unfold | Shift+. | 静态菜单声明 |
| Zoom Out | Command+- | 静态菜单声明 |
| Zoom to Fit | Command+= | 静态菜单声明 |

这些条目的键盘修饰掩码按 AppKit `NSEvent.ModifierFlags` 解读；启用条件、焦点状态、文字编辑模式中的实际效果仍未运行验证。软件可能在运行时覆盖静态菜单。

在应用包及嵌套 Framework/插件中，没有现成 `.mindnode` 文件；`MindNodeKitObjC.framework/Versions/A/Resources/ThemeMindMap.plist` 是主题用合成导图片段，不是 `.mindnode` 完整文档。`Info.plist` 对 `.mindnode` 声明了 package 与 data 两类 UTI，不能由扩展名断言文件容器。

用户随后明确授权只读检查 `/Users/nicozhuang/极境造物/会议纪要/` 下的文档。抽查三个 `.mindnode` 目录包，均含以 **Apple 二进制 property list** 编码的 `contents.xml`，版本值均为 `9`；内嵌 `canvas.mindMaps[*].mainNode`，节点有 `nodeID`（36 字符 UUID）、`title.text`（XML `<p>` 文本）、`subnodes`、`hasFoldedSubnodes`。三份样本分别含 1、2、1 张导图，共 91 个节点；另一份目录包为 0 张导图。此处仅记录格式与计数，不复制或输出正文，原件保持只读；其他版本与附件的语义尚未验证。
