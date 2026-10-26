import Foundation

@main enum LocalizationTests {
    static func main() {
        let suite = "local.mindmap.l10n-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        func fail(_ message: String) -> Never {
            defaults.removePersistentDomain(forName: suite)
            fputs("\(message)\n", stderr)
            exit(1)
        }
        guard L10n.choice(defaults: defaults) == "system",
              L10n.language(defaults: defaults, preferredLanguages: ["zh-Hans-CN", "en-US"]) == "zh-Hans",
              L10n.language(defaults: defaults, preferredLanguages: ["zh-CN", "en-US"]) == "zh-Hans",
              L10n.language(defaults: defaults, preferredLanguages: ["zh-Hant-TW", "zh-Hans-CN"]) == "en",
              L10n.language(defaults: defaults, preferredLanguages: ["en-US", "zh-Hans-CN"]) == "en" else {
            fail("System language must follow the first preferred language without converting Traditional Chinese to Simplified")
        }
        guard L10n.setLanguage("zh-Hans", defaults: defaults),
              L10n.choice(defaults: UserDefaults(suiteName: suite)!) == "zh-Hans",
              L10n.language(defaults: defaults) == "zh-Hans",
              L10n.text("View", defaults: defaults) == "视图",
               L10n.text("OpenMindFlow", defaults: defaults) == "OpenMindFlow",
               L10n.text("Quit OpenMindFlow", defaults: defaults) == "退出 OpenMindFlow",
              L10n.text("Show/Hide Style Inspector", defaults: defaults) == "显示/隐藏样式检查器",
              L10n.text("Save changes to this map?", defaults: defaults) == "保存对此导图的更改？",
              L10n.text("Map outline", defaults: defaults) == "导图大纲",
              L10n.text("Connection line style", defaults: defaults) == "连接线样式",
               L10n.text("Create Relationship", defaults: defaults) == "创建关联线",
               L10n.text("Insert Video…", defaults: defaults) == "插入视频…",
              L10n.text("Untranslated user node", defaults: defaults) == "Untranslated user node" else {
            fail("Simplified Chinese selection must persist and translate known UI keys only")
        }
        guard L10n.setLanguage("en", defaults: defaults),
              L10n.text("View", defaults: defaults) == "View",
               L10n.text("OpenMindFlow", defaults: defaults) == "OpenMindFlow",
               L10n.text("Quit OpenMindFlow", defaults: defaults) == "Quit OpenMindFlow",
              !L10n.setLanguage("fr", defaults: defaults),
              L10n.choice(defaults: defaults) == "en" else {
            fail("English selection must persist and reject unknown language values")
        }
        guard L10n.setLanguage("system", defaults: defaults),
              L10n.choice(defaults: defaults) == "system",
              defaults.object(forKey: "language") == nil else {
            fail("Returning to System must remove only the app language override")
        }
        defaults.set("invalid", forKey: "language")
        guard L10n.choice(defaults: defaults) == "system",
              L10n.language(defaults: defaults, preferredLanguages: ["en-US"]) == "en" else {
            fail("Invalid saved language must safely fall back to System")
        }
        defaults.removePersistentDomain(forName: suite)
        print("localized language choice, persistence and system fallback passed (no windows)")
    }
}
