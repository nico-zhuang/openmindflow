import Foundation

enum L10n {
    private static let key = "language"

    static func choice(defaults: UserDefaults = .standard) -> String {
        let saved = defaults.string(forKey: key) ?? "system"
        return ["system", "zh-Hans", "en"].contains(saved) ? saved : "system"
    }

    static func language(defaults: UserDefaults = .standard,
                         preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let selected = choice(defaults: defaults)
        guard selected == "system" else { return selected }
        let first = preferredLanguages.first?.lowercased() ?? ""
        return first == "zh" || first.hasPrefix("zh-hans") || first.hasPrefix("zh-cn") ||
            first.hasPrefix("zh-sg") || first.hasPrefix("zh-my") ? "zh-Hans" : "en"
    }

    @discardableResult
    static func setLanguage(_ value: String, defaults: UserDefaults = .standard) -> Bool {
        guard ["system", "zh-Hans", "en"].contains(value) else { return false }
        if value == "system" { defaults.removeObject(forKey: key) }
        else { defaults.set(value, forKey: key) }
        return true
    }

    static func text(_ english: String, defaults: UserDefaults = .standard) -> String {
        language(defaults: defaults) == "zh-Hans" ? chinese[english] ?? english : english
    }

    private static let chinese: [String: String] = [
        "OpenMindFlow": "OpenMindFlow", "Quit OpenMindFlow": "退出 OpenMindFlow",
        "MindMap": "思维导图", "Quit MindMap": "退出思维导图", "File": "文件", "Edit": "编辑",
        "View": "视图", "Node": "节点", "Save": "保存", "Undo": "撤销", "Redo": "重做",
        "Cut": "剪切", "Copy": "复制", "Paste": "粘贴", "Select All": "全选",
        "Open Map…": "打开导图…", "Import MindNode…": "导入 MindNode…",
        "Save As…": "另存为…", "Save As MindNode Copy…": "另存 MindNode 副本…",
        "Export MindNode…": "导出 MindNode…",
        "Show/Hide Outline": "显示/隐藏大纲", "Show/Hide Style": "显示/隐藏样式",
        "Show/Hide Style Inspector": "显示/隐藏样式检查器", "Appearance": "外观",
        "System": "跟随系统", "Follow System": "跟随系统", "Follow Theme": "跟随主题", "Light": "浅色", "Dark": "深色",
        "Settings…": "设置…", "Settings": "设置", "General": "常规", "Keyboard Shortcuts": "快捷键",
        "About": "关于", "About OpenMindFlow": "关于 OpenMindFlow",
        "Automatically check for updates": "自动检查更新", "Check for Updates…": "检查更新…",
        "A newer OpenMindFlow version is available": "OpenMindFlow 有新版本",
        "Version %@ is available on GitHub Releases. Open the official release page?": "GitHub Releases 上有 %@ 版本。要打开官方发布页面吗？",
        "View Release": "查看发布页", "Later": "稍后",
        "No newer release is available.": "暂无新版本。",
        "You are using the latest available public release.": "当前已是最新的公开发布版本。",
        "Unable to check for updates.": "暂时无法检查更新。",
        "OpenMindFlow is independently developed. Editable maps save as .mflw; MindNode v9 packages import, and supported edits export as copies without touching originals. It is not affiliated with or endorsed by IdeasOnCanvas. Open-source license unspecified.": "OpenMindFlow 独立开发。可编辑并保存 .mflw；支持导入 MindNode v9，兼容编辑可另导出副本，原件不变。与 IdeasOnCanvas 无关联，亦未经背书。开源许可尚未确定。",
        "Settings Page": "设置页面", "Shrink new nodes to fit content": "缩小新节点宽度以适应内容",
        "Restore Defaults": "恢复默认值", "Shortcut already in use": "该快捷键已被使用",
        "Tab": "Tab 键", "Return": "回车键", "Option + Return": "Option + 回车键",
        "Shift + Return": "Shift + 回车键", "Option + Tab": "Option + Tab 键",
        "Command + Return": "Command + 回车键", "Control + Tab": "Control + Tab 键",
        "Control + Return": "Control + 回车键", "Control + Shift + Tab": "Control + Shift + Tab 键",
        "Control + Shift + Return": "Control + Shift + 回车键",
        "Option + Shift + Return": "Option + Shift + 回车键",
        "Command + Shift + Return": "Command + Shift + 回车键",
        "Interface Language": "界面语言", "Language": "语言",
        "Insert Image…": "插入图片…", "Could not import image": "无法导入图片",
        "Insert Video…": "插入视频…", "Could not import video": "无法导入视频",
        "Could not export MindNode copy": "无法导出 MindNode 副本",
        "MindNode export supports plain titles, folding and same-parent order of existing nodes only. Other edits remain safe in .mflw; no MindNode copy was written.": "MindNode 导出目前仅支持原有节点的纯文本标题、折叠状态及同一父节点下的顺序调整。其他编辑仍可安全保存在 .mflw；没有生成 MindNode 副本。",
        "Video": "视频", "Image": "图片",
        "Export PDF…": "导出 PDF…", "Export PNG…": "导出 PNG…", "Export JPG…": "导出 JPG…",
        "Export Markdown…": "导出 Markdown…", "Could not export map": "无法导出导图",
        "Find…": "查找…", "Find": "查找", "Search nodes": "查找节点", "No matches": "无匹配节点",
        "Next Result": "下一个结果",
        "Arrange Map": "整理布局", "Zoom In": "放大", "Zoom Out": "缩小",
        "Fit Content": "缩放以适应内容",
        "Language changes immediately": "语言更改立即生效",
        "Simplified Chinese": "简体中文", "English": "英语", "Fit Map": "适合窗口",
        "New idea": "新想法", "Central idea": "中心主题", "Add Child": "添加子节点",
        "Attach": "附加",
        "Collapsed": "已折叠", "Expanded": "已展开", "child": "个子节点", "children": "个子节点",
        "Map outline": "导图大纲", "Empty map — press Tab to create the first idea.": "导图为空——按 Tab 创建第一个想法。",
        "Edit Title": "编辑标题", "Font…": "字体…", "New Child": "新建子节点",
        "New Sibling": "新建同级节点", "New Sibling Before": "在前方新建同级节点",
        "Create Relationship": "创建关联线", "Delete Relationship": "删除关联线",
        "Line Style": "线条样式", "Dotted": "点线", "Start Arrow": "起点箭头", "End Arrow": "终点箭头",
        "New Parent": "新建父节点", "New Main Node": "新建主节点",
        "Detach Node": "分离节点", "Fold/Unfold": "折叠/展开", "Delete": "删除",
        "Place on Left": "放置在左侧", "Place on Right": "放置在右侧",
        "Node Width": "节点宽度", "Auto": "自动", "Narrow (170 pt)": "窄（170 点）",
        "Medium (240 pt)": "中（240 点）", "Wide (320 pt)": "宽（320 点）",
        "Extra Wide (480 pt)": "特宽（480 点）", "Custom Width…": "自定义宽度…",
        "Custom Node Width": "自定义节点宽度", "Enter a width from 60 to 1000 points.": "输入 60 到 1000 点之间的宽度。",
        "Width in points": "宽度（点）", "Apply": "应用", "Cancel": "取消",
        "Untitled": "未命名", "Save changes to this map?": "保存对此导图的更改？",
        "Opening another file, closing the window, or quitting will discard unsaved changes.": "打开其他文件、关闭窗口或退出会丢弃未保存的更改。",
        "Discard Changes": "丢弃更改", "Unsupported format": "不支持的格式",
        "Select a .mflw document, legacy .mindmap.json file, or use Import MindNode.": "请选择 .mflw 文稿或旧版 .mindmap.json；MindNode 请使用“导入 MindNode”。",
        "The document operation was cancelled.": "文稿操作已取消。",
        "Open one .mflw document at a time in this candidate.": "当前候选版本每次只能打开一个 .mflw 文稿。",
        "Could not open map": "无法打开导图", "Could not open MindNode": "无法打开 MindNode",
        "Could not save map": "无法保存导图",
        "Select a MindNode v9 binary-plist file or directory package. Import is editable; Save creates an independent .mflw document.": "选择 MindNode v9 二进制 plist 文件或目录包。导入后可编辑，保存时创建独立的 .mflw 文稿。",
        "Select a .mindnode v9 binary-plist file or directory package.": "选择 .mindnode v9 二进制 plist 文件或目录包。",
        "Only MindNode v9 binary-plist files or directory packages can be imported into an editable .mflw document. The source remains untouched.": "仅支持将 MindNode v9 二进制 plist 文件或目录包导入可编辑的 .mflw 文稿；原件保持不变。",
        "Save as an independent .mflw document; never overwrite a MindNode source.": "请另存为独立的 .mflw 文稿；绝不覆盖 MindNode 原件。",
        "FONT": "字体", "CONNECTION": "连接线", "Family": "字体", "Font family": "字体名称",
        "Preview": "预览", "Font preview": "字体预览", "Size": "字号", "Font size": "字号",
        "Align": "对齐", "Paragraph alignment": "段落对齐", "Left": "左对齐",
        "Center": "居中", "Right": "右对齐", "Justify": "两端对齐",
        "Color": "颜色", "Connection color": "连接线颜色", "Width": "宽度",
        "Connection width": "连接线宽度", "Connection line style": "连接线样式",
        "Line": "线型", "Solid": "实线", "Dashed": "虚线",
        "Mixed": "混合", "Default": "默认", "Custom": "自定义", "Unavailable": "不可用",
        "Unavailable: %@": "不可用：%@",
        "No selection": "未选中节点", "More…": "更多…",
        "Teal": "青绿", "Blue": "蓝色", "Coral": "珊瑚色", "Gold": "金色", "Gray": "灰色",
        "Hairline": "极细", "Thin": "细", "Medium": "中等", "Bold": "粗", "Heavy": "极粗",
        "Edit Note": "编辑注释", "Style": "样式", "Notes": "注释", "Themes": "主题",
        "Note status": "注释状态", "Has note": "有注释", "Note exceeds 64 KiB or document limit": "注释超过 64 KiB 或文稿大小上限",
        "ROOT": "主节点", "CANVAS": "画布", "Rounded": "圆角", "Rectangle": "矩形",
        "Shape": "形状", "Root shape": "主节点形状", "Fill": "填充", "Root fill": "主节点填充",
        "Fixed width": "固定宽度", "Canvas Background": "画布背景",
        "Tropical": "热带", "Slate": "石板", "Coffee": "咖啡",
        "Rainbow": "彩虹", "Candyland": "糖果乐园"
    ]
}
