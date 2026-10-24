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
        "MindMap": "思维导图", "Quit MindMap": "退出思维导图", "File": "文件", "Edit": "编辑",
        "View": "视图", "Node": "节点", "Save": "保存", "Undo": "撤销", "Redo": "重做",
        "Cut": "剪切", "Copy": "复制", "Paste": "粘贴", "Select All": "全选",
        "Open MindNode (Read-only)…": "打开 MindNode（只读）…", "Open Own JSON…": "打开本应用 JSON…",
        "Show/Hide Outline": "显示/隐藏大纲", "Show/Hide Style": "显示/隐藏样式",
        "Show/Hide Style Inspector": "显示/隐藏样式检查器", "Appearance": "外观",
        "System": "跟随系统", "Follow System": "跟随系统", "Light": "浅色", "Dark": "深色",
        "Settings…": "设置…", "Settings": "设置", "Interface Language": "界面语言", "Language": "语言",
        "Insert Image…": "插入图片…", "Could not import image": "无法导入图片",
        "Export PDF…": "导出 PDF…", "Export PNG…": "导出 PNG…", "Export JPG…": "导出 JPG…",
        "Export Markdown…": "导出 Markdown…", "Could not export map": "无法导出导图",
        "Find…": "查找…", "Find": "查找", "Search nodes": "查找节点", "No matches": "无匹配节点",
        "Next Result": "下一个结果",
        "Arrange Map": "整理布局",
        "Language changes immediately": "语言更改立即生效",
        "Simplified Chinese": "简体中文", "English": "英语", "Fit Map": "适合窗口",
        "New idea": "新想法", "Central idea": "中心主题", "Add Child": "添加子节点",
        "Collapsed": "已折叠", "Expanded": "已展开", "child": "个子节点", "children": "个子节点",
        "Map outline": "导图大纲", "Empty map — press Tab to create the first idea.": "导图为空——按 Tab 创建第一个想法。",
        "Edit Title": "编辑标题", "Font…": "字体…", "New Child": "新建子节点",
        "New Sibling": "新建同级节点", "New Sibling Before": "在前方新建同级节点",
        "New Parent": "新建父节点", "New Main Node": "新建主节点",
        "Detach Node": "分离节点", "Fold/Unfold": "折叠/展开", "Delete": "删除",
        "Node Width": "节点宽度", "Auto": "自动", "Narrow (170 pt)": "窄（170 点）",
        "Medium (240 pt)": "中（240 点）", "Wide (320 pt)": "宽（320 点）",
        "Extra Wide (480 pt)": "特宽（480 点）", "Custom Width…": "自定义宽度…",
        "Custom Node Width": "自定义节点宽度", "Enter a width from 60 to 1000 points.": "输入 60 到 1000 点之间的宽度。",
        "Width in points": "宽度（点）", "Apply": "应用", "Cancel": "取消",
        "Untitled": "未命名", "Save changes to this map?": "保存对此导图的更改？",
        "Opening another file, closing the window, or quitting will discard unsaved changes.": "打开其他文件、关闭窗口或退出会丢弃未保存的更改。",
        "Discard Changes": "丢弃更改", "Unsupported format": "不支持的格式",
        "Select an existing .mindmap.json file; use Open MindNode for a read-only import.": "选择现有 .mindmap.json 文件；只读导入请使用“打开 MindNode”。",
        "Could not open map": "无法打开导图", "Could not open MindNode": "无法打开 MindNode",
        "Could not save map": "无法保存导图",
        "Select a MindNode v9 binary-plist file or directory package. Import is read-only; Save creates a new .mindmap.json file.": "选择 MindNode v9 二进制 plist 文件或目录包。导入只读；保存将创建新的 .mindmap.json 文件。",
        "Select a .mindnode v9 binary-plist file or directory package.": "选择 .mindnode v9 二进制 plist 文件或目录包。",
        "Save only as .mindmap.json; original .mindnode documents cannot be overwritten.": "只能保存为 .mindmap.json；不会覆盖原始 .mindnode 文档。",
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
        "Hairline": "极细", "Thin": "细", "Medium": "中等", "Bold": "粗", "Heavy": "极粗"
    ]
}
