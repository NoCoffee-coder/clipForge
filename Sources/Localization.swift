import Foundation

// MARK: - Localization

/// Simple zh/en localization, mirroring Rust i18n/translations.ts
enum L10n {

    static let table: [String: (zh: String, en: String)] = [
        "app_name": ("ClipForge", "ClipForge"),
        "search_placeholder": ("搜索…", "Search…"),
        "settings": ("设置", "Settings"),
        "show_main": ("显示主面板", "Show Main Panel"),
        "quit": ("退出", "Quit"),
        "total_count": ("共%d条", "%d items"),
        "select_hint": ("[↑↓]选择", "[↑↓]Select"),
        "paste_hint": ("[⏎]粘贴", "[⏎]Paste"),
        "hide_hint": ("[Esc]隐藏", "[Esc]Hide"),
        "auto_hide_hint": ("点窗口外自动隐藏", "Auto-hide on blur"),
        "pin": ("置顶", "Pin"),
        "unpin": ("取消置顶", "Unpin"),
        "delete": ("删除", "Delete"),
        "copy": ("复制", "Copy"),
        "open_json": ("在独立窗口打开", "Open in window"),
        "open_html": ("在浏览器打开", "Open in browser"),
        "save_image": ("保存图片", "Save Image"),
        "just_now": ("刚刚", "just now"),
        "minutes_ago": ("%d分前", "%dm ago"),
        "hours_ago": ("%d时前", "%dh ago"),
        "days_ago": ("%d天前", "%d days ago"),

        // Settings sections
        "settings_title": ("ClipForge 设置", "ClipForge Settings"),
        "section_general": ("通用", "General"),
        "section_json": ("JSON", "JSON"),
        "section_html": ("HTML", "HTML"),
        "section_image": ("图片", "Image"),
        "section_hotkey": ("快捷键", "Hotkeys"),
        "storage_limit": ("历史记录上限", "History limit"),
        "theme": ("主题", "Theme"),
        "theme_system": ("跟随系统", "System"),
        "theme_light": ("亮色", "Light"),
        "theme_dark": ("暗色", "Dark"),
        "language": ("语言", "Language"),
        "autostart": ("开机自启", "Launch at login"),
        "hide_dock": ("隐藏 Dock 图标", "Hide Dock icon"),
        "hide_menu_bar_icon": ("隐藏菜单栏图标", "Hide menu bar icon"),
        "json_auto_format": ("自动格式化 JSON", "Auto-format JSON"),
        "json_indent": ("缩进", "Indent"),
        "json_external_tool": ("外部 JSON 工具", "External JSON tool"),
        "browse": ("浏览…", "Browse…"),
        "json_external_tool_default": ("系统默认应用", "System default app"),
        "json_external_tool_hint": ("留空时使用系统默认应用打开 JSON；也可选择 .app 或可执行文件",
                                    "Leave empty to open JSON with the system default app; or pick a .app bundle / executable"),
        "html_retention": ("临时文件保留天数", "HTML retention days"),
        "image_auto_save": ("自动保存到本地", "Auto-save images"),
        "image_use_original_timestamp": ("使用原图复制时间作为文件时间",
                                        "Use original copy time for saved file"),
        "image_save_path": ("保存路径", "Save path"),
        "image_naming_template": ("命名模板", "Naming template"),
        "template_vars": ("可用变量：{date} {time} {app} {n} {hash}",
                         "Vars: {date} {time} {app} {n} {hash}"),
        "hotkey_main_label": ("显示/隐藏主面板", "Show/Hide main panel"),
        "hotkey_json_label": ("JSON 独立窗口", "JSON viewer window"),
        "hotkey_html_label": ("HTML 浏览器打开", "Open HTML in browser"),
        "feedback": ("反馈", "Feedback"),
        "feedback_hint": ("如果点击按钮没有反应，请发送邮件到 taolux2021@163.com",
                          "If the button doesn't work, email taolux2021@163.com"),
        "retention_1d": ("1 天", "1 day"),
        "retention_7d": ("7 天", "7 days"),
        "retention_15d": ("15 天", "15 days"),
        "retention_30d": ("30 天", "30 days"),
        "retention_forever": ("永久", "Forever"),
        "indent_2": ("2 空格", "2 spaces"),
        "indent_4": ("4 空格", "4 spaces"),

        // Type filter
        "filter_all": ("全部", "All"),

        // Keyboard hints (status bar)
        "hint_select": ("↑↓ 选择", "↑↓ select"),
        "hint_paste": ("⏎ 粘贴", "⏎ paste"),
        "hint_pin": ("⌘P 置顶", "⌘P pin"),

        // Search
        "clear": ("清空", "Clear"),

        // Preview
        "preview_empty": ("选一条记录预览", "Select an item to preview"),

        // Common
        "back": ("返回", "Back"),
    ]

    static func t(_ key: String, language: String) -> String {
        guard let entry = table[key] else { return key }
        return language == "en" ? entry.en : entry.zh
    }

    static func t(_ key: String, language: String, _ args: CVarArg...) -> String {
        let format = t(key, language: language)
        return String(format: format, arguments: args)
    }
}
