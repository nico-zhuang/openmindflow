# MindNode → MindMap 行为覆盖基线（进行中）

目标改为先系统逆向再尽可能独立还原，不再把“能编辑＋v9 只读导入”视为终点。原版证据为 `/Applications/MindNode.app` 的 `MainMenu.nib` 静态解码（Evidence `ev_8edbba1393dc332a57ef570d62842545cea8a7f7eaedfceee22e29eb84b8f512`），详见[全部静态菜单条目](2026-10-20-mindnode-menu-inventory.md)。当前原型证据为 `Sources/App.swift`、`Sources/MapModel.swift`、`Sources/Layout.swift` 与 `Sources/MindNodeImporter.swift`。未启动原版，不观察私人文档。

| 功能群 | 原版静态证据 | 当前原型 | 尚需验证/实现 |
| --- | --- | --- | --- |
| 节点创建编辑 | New Child Tab、New Sibling Return、New Sibling Before ⌥Return、New Parent ⌥Tab、New Main Node ⇧Return、Edit Title ⌘Return | Tab 子节点/空图首根，Return 非根同级，⌥Return 前插同级，⌥Tab 新父节点，⇧Return 新主节点；模型、无窗口 AppKit 文本命令与构建已验证 | ⌘Return 显式编辑标题、编辑焦点及运行时按键语义 |
| 移动/拖动 | Move above/below/left/right of sibling ⌘方向键、Detach Node ⌘D、Layout/Balance Children；静态符号另显示 CanvasUI 拖动开始/更新/结束、重连及插入区域估计器，仍**不证明鼠标拖拽的落点规则** | 空白区拖动平移画布；节点拖到另一节点中部改挂为子节点，拖到上下边缘重排同级；模型防循环并可撤销，纯落点逻辑有无界面测试；尚未 GUI 验证；⌘↑/⌘↓已接入相邻同级重排，⌘⇧D 分离选中非根节点为主节点，未覆盖左右方向 | 自由定位/独立节点、拖动预览、左右移动快捷键及运行时手感；当前四分之一高度落点为独立近似，须以原版临时空白图证据校准 |
| 结构与选择 | Indent/Outdent、Select All Subnodes、Select Next/Previous Main Node、Fold/Unfold、Unfold All、Focus Mode | 方向键选单节点、折叠当前节点 | 多选、缩进/反缩进、焦点模式及作用域 |
| 剪贴板/重复 | Cut/Copy/Paste、Duplicate、Duplicate Single Node、Copy Selected Nodes | 未实现节点剪贴板 | 多节点复制与原版剪贴板格式；不得复制原版私有实现 |
| 图面/视图 | Zoom In/Out、Actual Size、Zoom to Fit/Selection、Center Node/Main Node、Mind Map/Outline | 自有固定树布局、画布平移、滚轮/捏合缩放 | 双向布局、自动排版、概览/聚焦/大纲与视觉还原 |
| 内容与辅助 | Notes、Links、Tasks、Boundaries、Connections、Node Groups、文字样式等静态菜单条目 | 标题纯文本＋子树＋折叠 | 功能与文件模型未覆盖；优先区分原版可用性和具体行为 |
| 文档 | Open/Save/Export/Revert 等菜单 | `.mindmap.json` 原子保存；v9 目录包 binary plist 只读导入部分字段 | 原格式多版本、资源/样式/附件及写出未实现；绝不回写原包 |

**拖动静态补充**：对原版随包框架执行 `nm -gU -arch arm64`、用 `xcrun swift-demangle --compact` 解码符号（不启动 App）。`CanvasUI.MNCNodeDraggingInteraction` 暴露拖动生命周期及 `rewireDraggedNodes(to:adaptStyle:dragIsOngoing:)`；`CanvasHostCore.Action.MoveNodes` 包含可选新父节点和插入位置；菜单 `Detach Node` 静态键为大写 `D`＋Command，⌘⇧D 属按键推断而非原版运行时观测；`MindNodeCore.MNCNodeInsertActionEstimator` 暴露带优先级的插入矩形和自动脱离阈值配置；OutlineUI 另有表格落点验证与接受路径。这些是**可调用结构的静态证据**，不提供阈值数值、拖动手势或最终运行时规则。

**证据等级**：本表“原版”列均为编译菜单/框架符号的静态观察；“当前”列为源码与无界面断言；除历史一次合成导入 GUI 测试外，不宣称运行时等价。菜单项存在不等于同一文档、权限或模式下可用。安装包中的授权/购买菜单不作为逆向绕过或复刻目标。

**本轮最小闭环**：模型的同级移动和跨父节点改挂已按失败断言→实现→无界面测试验证；画布按起始命中位置区分节点拖放与空白区平移，拖放区域为上/下各四分之一高度与中部，未做 GUI 验证，也未更新当前打开的旧安装包。下一批核对原版临时空白图的真实落点、自由定位及 ⌘方向键，再决定是否调整近似规则。
